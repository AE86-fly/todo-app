package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"todo-app/internal/store"
)

type TodoHandler struct {
	store *store.Store
}

func NewTodoHandler(s *store.Store) *TodoHandler {
	return &TodoHandler{store: s}
}

// Register 挂到已经带 JWTAuth 中间件的子路由上，所以这里的每个路由
// 都自动要求认证 —— 鉴权在 main.go 里挂一次，不需要逐个路由重复声明。
func (h *TodoHandler) Register(g *gin.RouterGroup) {
	g.GET("/todos", h.list)
	g.POST("/todos", h.create)
	g.PATCH("/todos/:id/toggle", h.toggle)
	g.DELETE("/todos/:id", h.remove)
}

func (h *TodoHandler) list(c *gin.Context) {
	uid, ok := currentUserID(c)
	if !ok {
		return
	}

	todos, err := h.store.ListTodos(uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "读取列表失败"})
		return
	}
	c.JSON(http.StatusOK, todos)
}

func (h *TodoHandler) create(c *gin.Context) {
	uid, ok := currentUserID(c)
	if !ok {
		return
	}

	var body struct {
		Title string `json:"title" binding:"required,max=255"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	t, err := h.store.CreateTodo(uid, body.Title)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}
	c.JSON(http.StatusCreated, t)
}

func (h *TodoHandler) toggle(c *gin.Context) {
	uid, ok := currentUserID(c)
	if !ok {
		return
	}
	id, ok := pathID(c)
	if !ok {
		return
	}

	t, err := h.store.ToggleTodo(uid, id)
	if err != nil {
		// 不存在和不是你的都走这里，回同一个 404。
		if errors.Is(err, store.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "待办不存在"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}
	c.JSON(http.StatusOK, t)
}

func (h *TodoHandler) remove(c *gin.Context) {
	uid, ok := currentUserID(c)
	if !ok {
		return
	}
	id, ok := pathID(c)
	if !ok {
		return
	}

	if err := h.store.DeleteTodo(uid, id); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "待办不存在"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}
	c.Status(http.StatusNoContent)
}
