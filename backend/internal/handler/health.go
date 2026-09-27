package handler

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// Healthz 只回答"进程还活着吗"，不碰任何外部依赖。
//
// 存活探针刻意不探数据库：数据库短暂抖动时，探针失败会触发一次重启，
// 而重启既治不好数据库，又让本可以自行恢复的服务多断一次。
// 判断"能不能接流量"是 Readyz 的事，两者职责不要混。
func Healthz(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// Readyz 回答"现在能正常提供服务吗"，包含数据库连通性。
// compose 的 healthcheck 和 nginx 的 depends_on 都打这个 ——
// 它才是决定要不要把流量导进来的信号。
func Readyz(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		sqlDB, err := db.DB()
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "degraded", "error": "无法取得数据库连接池"})
			return
		}

		// 带超时的 ping：数据库不可达时 TCP 连接可能要等很久才失败，
		// 不加超时会让这个探针自己挂住，探针挂住就等于探针失效。
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()

		if err := sqlDB.PingContext(ctx); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "degraded", "error": "数据库不可达"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	}
}
