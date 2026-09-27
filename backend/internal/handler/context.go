package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"todo-app/internal/middleware"
)

// currentUserID 取出 JWTAuth 中间件放进 context 的用户 ID。
//
// 显式做带 ok 的断言，而不是用 c.GetUint：后者在类型对不上时静默返回 0，
// 于是所有查询变成 user_id = 0，表现为"列表永远空的"这种极难定位的现象。
// 这里类型不对就直接 401，把问题钉在它发生的地方。
// 正常流程下这个分支永远不会走到 —— 它是给"以后有人改坏了中间件"准备的。
func currentUserID(c *gin.Context) (uint, bool) {
	v, exists := c.Get(middleware.ContextUID)
	if !exists {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "未认证"})
		return 0, false
	}
	uid, ok := v.(uint)
	if !ok {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "凭证无效"})
		return 0, false
	}
	return uid, true
}

// pathID 解析路径里的 :id。
//
// 解析失败明确回 400，而不是忽略错误让它变成 0 —— 0 会一路查到
// "记录不存在"然后回 404，把一个客户端的输入错误伪装成资源不存在。
func pathID(c *gin.Context) (uint, bool) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil || id == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "id 必须是正整数"})
		return 0, false
	}
	return uint(id), true
}
