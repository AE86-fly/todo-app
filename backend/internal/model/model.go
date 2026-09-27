package model

import "time"

// User 账号。
type User struct {
	ID       uint   `gorm:"primaryKey" json:"id"`
	Username string `gorm:"uniqueIndex;size:64;not null" json:"username"`

	// json:"-" 保证密码哈希永远不会出现在任何 API 响应里。
	// 它是一道兜底：就算以后有人图省事把整个 User 结构体直接塞进返回体，
	// 也不会把哈希漏出去。
	Password string `gorm:"size:255;not null" json:"-"`

	CreatedAt time.Time `json:"createdAt"`
}

// Todo 一条待办。
type Todo struct {
	ID     uint `gorm:"primaryKey" json:"id"`
	UserID uint `gorm:"index;not null" json:"userId"`

	// 真实外键 + 级联删除。只有 UserID 这个整数列是不够的 ——
	// 数据库层面拦不住指向不存在用户的记录，删用户也会留下一堆孤儿待办。
	// json:"-" 是因为前端不需要嵌套的用户对象，UserID 已经够了。
	User User `gorm:"constraint:OnDelete:CASCADE" json:"-"`

	Title     string    `gorm:"size:255;not null" json:"title"`
	Done      bool      `gorm:"default:false;not null" json:"done"`
	CreatedAt time.Time `json:"createdAt"`
}
