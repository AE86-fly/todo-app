package store

import (
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"todo-app/internal/model"
)

// 这几个测试需要一个真实的 postgres。拿不到就跳过 —— 目的是让
// `go test ./...` 在没有数据库的环境里也是绿的，而不是红一片然后
// 所有人都学会忽略它。有数据库时它们才真正开始干活。
//
//	DB_HOST=localhost DB_PORT=5433 DB_USER=todo DB_PASSWORD=... DB_NAME=todo go test ./...
func testDB(t *testing.T) *gorm.DB {
	t.Helper()

	// connect_timeout 很关键：没有它，数据库不可达时 gorm.Open 会
	// 卡在 TCP 握手上很久，测试表现为"挂住"而不是"跳过"。
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable TimeZone=UTC connect_timeout=3",
		envOr("DB_HOST", "localhost"),
		envOr("DB_PORT", "5433"),
		envOr("DB_USER", "todo"),
		envOr("DB_PASSWORD", "todo"),
		envOr("DB_NAME", "todo"),
	)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		TranslateError: true,
		Logger:         logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Skipf("跳过：连不上测试数据库（%v）", err)
	}

	if err := db.AutoMigrate(&model.User{}, &model.Todo{}); err != nil {
		t.Fatalf("建表失败: %v", err)
	}
	return db
}

// newUser 造一个用户名唯一的用户，并在测试结束时删掉。
// 删用户会级联删掉他的待办，所以不需要单独清理 todos。
func newUser(t *testing.T, s *Store) model.User {
	t.Helper()

	name := fmt.Sprintf("t_%d_%d", time.Now().UnixNano(), os.Getpid())
	u, err := s.CreateUser(name, "not-a-real-hash")
	if err != nil {
		t.Fatalf("创建测试用户失败: %v", err)
	}
	t.Cleanup(func() {
		s.db.Unscoped().Where("id = ?", u.ID).Delete(&model.User{})
	})
	return u
}

// 空列表必须序列化成 []，不能是 null。
//
// 这是最容易误诊的一个坑：nil slice 经 encoding/json 变成 null，
// 前端拿到 null 再当数组用会直接抛异常白屏，而排查的人通常先怀疑前端。
func TestListTodosEmptyIsNotNil(t *testing.T) {
	s := New(testDB(t))
	u := newUser(t, s)

	todos, err := s.ListTodos(u.ID)
	if err != nil {
		t.Fatalf("查询失败: %v", err)
	}
	if todos == nil {
		t.Fatal("空列表返回了 nil —— 会被序列化成 null，前端会崩")
	}
	if len(todos) != 0 {
		t.Fatalf("新用户不该有待办，却拿到 %d 条", len(todos))
	}
}

func TestCreateAndListOrder(t *testing.T) {
	s := New(testDB(t))
	u := newUser(t, s)

	for _, title := range []string{"第一", "第二", "第三"} {
		if _, err := s.CreateTodo(u.ID, title); err != nil {
			t.Fatalf("创建 %q 失败: %v", title, err)
		}
	}

	todos, err := s.ListTodos(u.ID)
	if err != nil {
		t.Fatalf("查询失败: %v", err)
	}
	if len(todos) != 3 {
		t.Fatalf("期望 3 条，拿到 %d 条", len(todos))
	}
	// 新的在前。前端的插入顺序必须和这个一致（unshift 而不是 push），
	// 否则新建一条之后刷新页面，它的位置会跳。
	if todos[0].Title != "第三" {
		t.Errorf("列表第一条是 %q，期望最新的「第三」", todos[0].Title)
	}
}

// 用户隔离：A 看不到、也删不掉 B 的待办。
// 这是这个项目的核心需求，不能只验 happy path。
func TestUserIsolation(t *testing.T) {
	s := New(testDB(t))
	alice := newUser(t, s)
	bob := newUser(t, s)

	aliceTodo, err := s.CreateTodo(alice.ID, "alice 的私事")
	if err != nil {
		t.Fatalf("创建失败: %v", err)
	}

	// bob 的列表里不该出现 alice 的待办
	bobTodos, err := s.ListTodos(bob.ID)
	if err != nil {
		t.Fatalf("查询失败: %v", err)
	}
	if len(bobTodos) != 0 {
		t.Fatalf("bob 看到了 %d 条不属于他的待办", len(bobTodos))
	}

	// bob 不能翻转 alice 的待办
	if _, err := s.ToggleTodo(bob.ID, aliceTodo.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("bob 翻转 alice 的待办，期望 ErrNotFound，实际 %v", err)
	}

	// bob 不能删 alice 的待办
	if err := s.DeleteTodo(bob.ID, aliceTodo.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("bob 删除 alice 的待办，期望 ErrNotFound，实际 %v", err)
	}

	// alice 的待办必须原封不动
	todos, err := s.ListTodos(alice.ID)
	if err != nil {
		t.Fatalf("查询失败: %v", err)
	}
	if len(todos) != 1 || todos[0].Done {
		t.Fatalf("alice 的待办被改动了: %+v", todos)
	}
}

// ToggleTodo 走的是 UPDATE ... SET done = NOT done RETURNING *，
// 这里验证返回的确实是翻转之后的值，而不是语句执行前的旧值。
func TestToggleReturnsUpdatedValue(t *testing.T) {
	s := New(testDB(t))
	u := newUser(t, s)

	created, err := s.CreateTodo(u.ID, "翻转我")
	if err != nil {
		t.Fatalf("创建失败: %v", err)
	}
	if created.Done {
		t.Fatal("新建的待办不该是已完成")
	}

	toggled, err := s.ToggleTodo(u.ID, created.ID)
	if err != nil {
		t.Fatalf("翻转失败: %v", err)
	}
	if !toggled.Done {
		t.Error("翻转后 Done 仍是 false —— RETURNING 带回的是旧值")
	}
	if toggled.ID != created.ID || toggled.Title != created.Title {
		t.Errorf("返回的记录不对: %+v", toggled)
	}

	// 再翻一次必须回到 false，且数据库里也是一致的
	again, err := s.ToggleTodo(u.ID, created.ID)
	if err != nil {
		t.Fatalf("二次翻转失败: %v", err)
	}
	if again.Done {
		t.Error("翻转两次应该回到未完成")
	}

	var fromDB model.Todo
	if err := s.db.First(&fromDB, created.ID).Error; err != nil {
		t.Fatalf("回查失败: %v", err)
	}
	if fromDB.Done {
		t.Error("数据库里的值和接口返回的不一致")
	}
}

func TestToggleMissingReturnsNotFound(t *testing.T) {
	s := New(testDB(t))
	u := newUser(t, s)

	if _, err := s.ToggleTodo(u.ID, 999999999); !errors.Is(err, ErrNotFound) {
		t.Errorf("翻转不存在的记录，期望 ErrNotFound，实际 %v", err)
	}
	if err := s.DeleteTodo(u.ID, 999999999); !errors.Is(err, ErrNotFound) {
		t.Errorf("删除不存在的记录，期望 ErrNotFound，实际 %v", err)
	}
}

// 用户名唯一约束必须被翻译成 ErrDuplicatedKey。
// 这条依赖 gorm.Config{TranslateError: true} 且 dialector 实现了
// ErrorTranslator —— 少了任何一半，注册接口就没法区分"重名"和"数据库故障"。
func TestCreateUserDuplicateIsTranslated(t *testing.T) {
	s := New(testDB(t))
	u := newUser(t, s)

	_, err := s.CreateUser(u.Username, "another-hash")
	if !errors.Is(err, gorm.ErrDuplicatedKey) {
		t.Fatalf("重复用户名期望 gorm.ErrDuplicatedKey，实际 %v", err)
	}
}

func TestFindUserByUsernameMissing(t *testing.T) {
	s := New(testDB(t))

	_, err := s.FindUserByUsername(fmt.Sprintf("nobody_%d", time.Now().UnixNano()))
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("期望 ErrNotFound，实际 %v", err)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
