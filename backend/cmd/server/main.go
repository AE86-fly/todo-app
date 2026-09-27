package main

import (
	"errors"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"todo-app/internal/auth"
	"todo-app/internal/config"
	"todo-app/internal/db"
	"todo-app/internal/handler"
	"todo-app/internal/middleware"
	"todo-app/internal/store"
)

func main() {
	cfg := config.Load()
	db.Init(cfg)

	a := auth.New(cfg.JWTSecret, cfg.TokenTTL)
	s := store.New(db.DB)

	// 用 gin.New() 而不是 gin.Default()：Default 会带上 gin 自带的
	// Logger 和 Recovery，但那个 Logger 把所有请求（含 Authorization 头
	// 所在的那行原始信息）按固定格式打到 stdout。这里显式声明中间件，
	// 至少让"打了什么日志"是可见、可控的。
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	r.GET("/healthz", handler.Healthz)
	r.GET("/readyz", handler.Readyz(db.DB))

	// 所有业务路由统一挂在 /api 下。
	// 前缀只在这一处出现 —— 各个 handler 的 Register 里写的是相对路径。
	// 原教程在前缀和组内路径里各写了一次 /api，结果拼成 /api/api/todos。
	api := r.Group("/api")

	// 公开接口：注册、登录。
	handler.NewAuthHandler(s, a).Register(api)

	// 需要认证的接口。
	//
	// 这里用 api.Group("") 而不是 r.Group("/api")：空字符串的 relativePath
	// 在 gin 里直接返回父组的绝对路径（joinPaths 对 "" 有特判），
	// 所以拿到的是同一个 /api 组，但中间件只作用在这个新组上 ——
	// 于是注册和登录保持公开，待办接口全部要求认证。
	authed := api.Group("")
	authed.Use(middleware.JWTAuth(a))
	handler.NewTodoHandler(s).Register(authed)

	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: r,
		// 读头的超时必须有：没有它，一个只连上却不发完请求头的客户端
		// 就能一直占着连接不放（Slowloris 那类资源耗尽）。
		ReadHeaderTimeout: 10 * time.Second,
	}

	log.Printf("服务已启动，监听 :%s", cfg.Port)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("服务异常退出: %v", err)
	}
}
