package db

import (
	"log"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"todo-app/internal/config"
	"todo-app/internal/model"
)

var DB *gorm.DB

// Init 连接数据库、配好连接池、建表。
func Init(cfg *config.Config) {
	dsn := cfg.DSN()

	var err error
	// 这个重试循环是给"宿主机直接 go run"兜底的：compose 里 api 服务已经靠
	// depends_on: condition: service_healthy 等 db 真的能用了才启动，用不上它。
	// 但在宿主机上直接跑时没有那层保护，数据库还没起来就会连不上。
	// gorm.Open 默认会 ping 一次，所以这个重试是真的有效，不是空转。
	for i := 1; i <= 10; i++ {
		DB, err = gorm.Open(postgres.Open(dsn), &gorm.Config{
			// TranslateError 把驱动的原生错误码翻译成 GORM 的语义错误。
			// 没有它，postgres 的 23505（唯一约束冲突）就只是一个普通 error，
			// 注册接口没办法区分"用户名被占用"和"数据库连不上"。
			// 注意这个开关只有在 dialector 实现了 ErrorTranslator 时才生效，
			// postgres driver 是实现了的（error_translator.go 里把 23505
			// 映射到 gorm.ErrDuplicatedKey）。
			TranslateError: true,
			Logger:         logger.Default.LogMode(logger.Warn),
		})
		if err == nil {
			break
		}
		log.Printf("等待数据库就绪... (%d/10): %v", i, err)
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		log.Fatalf("数据库连接失败: %v", err)
	}

	sqlDB, err := DB.DB()
	if err != nil {
		log.Fatalf("取出底层连接池失败: %v", err)
	}
	// 单实例、内存有限，不需要大池子。
	// SetConnMaxLifetime 是必要的：postgres 侧会主动切断空闲太久的连接，
	// 池子里留着已经死掉的连接，会在下一次请求时才暴露成错误。
	sqlDB.SetMaxOpenConns(10)
	sqlDB.SetMaxIdleConns(5)
	sqlDB.SetConnMaxLifetime(time.Hour)

	// 先 User 后 Todo：Todo 有指向 users 的外键，被引用的表必须先建好。
	if err := DB.AutoMigrate(&model.User{}, &model.Todo{}); err != nil {
		log.Fatalf("建表失败: %v", err)
	}
	// AutoMigrate 的能力边界要清楚：它只加表、加列、加索引，
	// 不删列、不改类型、不搬运数据。现在没有历史包袱所以够用，
	// 一旦表里有了真实数据、schema 又要变，就该换成版本化迁移工具
	// （golang-migrate 之类），别再指望它。
}
