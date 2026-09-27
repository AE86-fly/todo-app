package store

import (
	"errors"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"todo-app/internal/model"
)

// ErrNotFound 是所有"查不到/不属于你"的统一出口。
//
// store 把 gorm 的错误翻译成自己的语义错误，handler 就不需要 import gorm ——
// 换 ORM 或者改用手写 SQL 时，改动被关在这一层里。
var ErrNotFound = errors.New("记录不存在")

type Store struct{ db *gorm.DB }

func New(db *gorm.DB) *Store { return &Store{db: db} }

// ---------- 待办 ----------

// ListTodos 返回该用户的全部待办，新的在前。
func (s *Store) ListTodos(userID uint) ([]model.Todo, error) {
	// make(..., 0) 而不是 var todos []model.Todo 是必须的：
	// nil slice 会被 encoding/json 序列化成 null，前端拿到 null 再
	// 当成数组用（.map / v-for / as List）会直接抛异常、页面白屏。
	// 而排查的人通常会先怀疑前端 —— 空列表必须是 []，这是接口契约。
	todos := make([]model.Todo, 0)
	err := s.db.Where("user_id = ?", userID).Order("id desc").Find(&todos).Error
	return todos, err
}

func (s *Store) CreateTodo(userID uint, title string) (model.Todo, error) {
	t := model.Todo{UserID: userID, Title: title}
	err := s.db.Create(&t).Error
	return t, err
}

// ToggleTodo 原子地翻转 done，并返回更新后的记录。
//
// 不用"First 查出来 → 改字段 → Save"那套写法：那是读-改-写三步，
// 两个请求并发时会丢更新（用户连点两下，只翻转一次）。
// 这里让数据库在一条 UPDATE 里完成翻转，配 RETURNING 把新值带回来，
// 全程只有一条语句，没有中间状态可被插队。
func (s *Store) ToggleTodo(userID, id uint) (model.Todo, error) {
	var t model.Todo
	// WHERE 里的 user_id 就是用户隔离的全部实现。
	// RowsAffected == 0 同时覆盖"这条不存在"和"这条不是你的"两种情况 ——
	// 两者返回完全一样的响应，不泄露任何关于他人数据是否存在的信号。
	res := s.db.Model(&t).
		Clauses(clause.Returning{}).
		Where("id = ? AND user_id = ?", id, userID).
		Update("done", gorm.Expr("NOT done"))
	if res.Error != nil {
		return model.Todo{}, res.Error
	}
	if res.RowsAffected == 0 {
		return model.Todo{}, ErrNotFound
	}
	return t, nil
}

func (s *Store) DeleteTodo(userID, id uint) error {
	res := s.db.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Todo{})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

// ---------- 用户 ----------

// CreateUser 的错误可能是 gorm.ErrDuplicatedKey（用户名唯一约束冲突，
// 由 TranslateError 翻译而来），调用方用 errors.Is 判断。
func (s *Store) CreateUser(username, hashedPassword string) (model.User, error) {
	u := model.User{Username: username, Password: hashedPassword}
	err := s.db.Create(&u).Error
	return u, err
}

func (s *Store) FindUserByUsername(username string) (model.User, error) {
	var u model.User
	err := s.db.Where("username = ?", username).First(&u).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return model.User{}, ErrNotFound
	}
	return u, err
}
