package config

import (
	"fmt"
	"log"
	"os"
	"time"
)

// 配置全部从环境变量来，集中在这里读取和校验。
//
// 不在各处直接 os.Getenv 的原因：配置项一散开，就没人说得清"哪个变量没设
// 会导致什么后果"。集中之后，启动时一次性校验完，缺什么错什么立刻终止，
// 而不是等到某个请求打进来才崩。
type Config struct {
	Port       string
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	JWTSecret  []byte
	TokenTTL   time.Duration
}

// Load 读取并校验配置，任何一项不合法都直接终止进程。
//
// 这里刻意不给 JWT_SECRET 默认值。HS256 的全部安全性都押在这个 key 上，
// 给一个 "change-me" 式的默认值，等于让服务看起来启动成功了、
// 实际上任何人都能伪造 token —— 这比启动失败危险得多。
func Load() *Config {
	secret := os.Getenv("JWT_SECRET")
	// 32 字节是 HS256 摘要长度（SHA-256 输出 32 字节）。
	// 密钥短于摘要长度时会成为整体强度的短板。
	if len(secret) < 32 {
		log.Fatal("JWT_SECRET 未设置或长度不足 32 字节。请在 .env 里设置一个随机值，" +
			"例如 `openssl rand -hex 32` 的输出。")
	}

	return &Config{
		Port:       env("PORT", "8080"),
		DBHost:     env("DB_HOST", "localhost"),
		DBPort:     env("DB_PORT", "5432"),
		DBUser:     env("DB_USER", "todo"),
		DBPassword: env("DB_PASSWORD", ""),
		DBName:     env("DB_NAME", "todo"),
		JWTSecret:  []byte(secret),
		TokenTTL:   envDuration("TOKEN_TTL", 72*time.Hour),
	}
}

// DSN 拼出 postgres 连接串。
//
// 时区固定 UTC，不跟随宿主机。原因是运行镜像里没有 tzdata
// （CGO_ENABLED=0 的静态二进制 + 精简镜像），DSN 里写 Asia/Shanghai
// 会让服务端直接拒绝连接，报 invalid value for parameter "TimeZone"。
// 统一存 UTC、由客户端按本地时区渲染，省掉一整类跨时区问题。
func (c *Config) DSN() string {
	return fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable TimeZone=UTC",
		c.DBHost, c.DBPort, c.DBUser, c.DBPassword, c.DBName,
	)
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// envDuration 解析形如 "72h" / "30m" 的时长。解析不了就用默认值 ——
// 时长不是安全边界，值写得不对时退回默认比拒绝启动更合理。
func envDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		log.Printf("警告：%s=%q 不是合法时长，改用默认值 %s", key, v, fallback)
		return fallback
	}
	return d
}
