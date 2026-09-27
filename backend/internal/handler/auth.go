package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"todo-app/internal/auth"
	"todo-app/internal/model"
	"todo-app/internal/store"
)

type AuthHandler struct {
	store *store.Store
	auth  *auth.Auth
}

func NewAuthHandler(s *store.Store, a *auth.Auth) *AuthHandler {
	return &AuthHandler{store: s, auth: a}
}

// Register 把本组的路由挂到传进来的子路由上。
//
// 组内路径写相对值（"/auth/register"），前缀 /api 由 main.go 提供。
// 两边都写 /api 就会拼成 /api/api/xxx —— 这正是原始教程里的 bug：
// 它先 r.Group("/api") 又在组内 Group("/api/todos")，gin 的 joinPaths
// 把两段拼了起来，于是所有待办接口都 404。
func (h *AuthHandler) Register(g *gin.RouterGroup) {
	g.POST("/auth/register", h.register)
	g.POST("/auth/login", h.login)
}

type credentials struct {
	Username string `json:"username" binding:"required,min=3,max=64"`
	Password string `json:"password" binding:"required,min=8,max=128"`
}

func (h *AuthHandler) register(c *gin.Context) {
	var body credentials
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "密码处理失败"})
		return
	}

	u, err := h.store.CreateUser(body.Username, hash)
	if err != nil {
		// 只有真正的唯一约束冲突才回 409。
		//
		// 原始教程把 CreateUser 的**任何**错误都当成"用户名已存在"，
		// 于是数据库连不上、超时、权限不足全都回 409 —— 把基础设施故障
		// 伪装成用户输入问题，排查时会被带到完全错误的方向。
		if errors.Is(err, gorm.ErrDuplicatedKey) {
			c.JSON(http.StatusConflict, gin.H{"error": "用户名已被占用"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建用户失败"})
		return
	}

	h.respondWithToken(c, http.StatusCreated, u)
}

func (h *AuthHandler) login(c *gin.Context) {
	var body credentials
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	u, err := h.store.FindUserByUsername(body.Username)
	// "用户不存在"和"密码错误"返回完全一样的响应，且都走同一个分支。
	//
	// 分成两种错误信息会变成一个用户名枚举接口：攻击者可以靠响应差异
	// 批量判断哪些用户名已注册。顺带一提，这里的 bcrypt 比对即使在用户
	// 不存在时也应该消耗相当的时间，否则响应快慢同样会泄露用户是否存在 ——
	// 这一轮先不做等时处理，知道有这个残留就行。
	if err != nil || !auth.CheckPassword(u.Password, body.Password) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
		return
	}

	h.respondWithToken(c, http.StatusOK, u)
}

func (h *AuthHandler) respondWithToken(c *gin.Context, status int, u model.User) {
	token, err := h.auth.Generate(u.ID, u.Username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "签发凭证失败"})
		return
	}
	c.JSON(status, gin.H{"token": token, "user": u})
}
