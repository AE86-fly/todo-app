package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"todo-app/internal/auth"
)

// ContextUID 是用户 ID 在 gin.Context 里的键。定义成常量而不是到处
// 写字面量字符串：拼错一个字母不会报错，只会让取值永远拿不到。
const ContextUID = "uid"

// JWTAuth 校验 Authorization: Bearer <token>，通过后把用户 ID 放进 context。
func JWTAuth(a *auth.Auth) gin.HandlerFunc {
	const prefix = "Bearer "

	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		// 用 EqualFold 而不是严格比较：HTTP 头字段名和 "Bearer" 这个
		// 认证方案名都是大小写不敏感的，各家客户端的写法并不统一，
		// 严格匹配会把本来能用的 token 拒掉。
		if len(header) <= len(prefix) || !strings.EqualFold(header[:len(prefix)], prefix) {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "缺少或格式不正确的 Authorization 头"})
			return
		}

		claims, err := a.Parse(strings.TrimSpace(header[len(prefix):]))
		if err != nil {
			// 不把 err 的细节回给客户端：验签失败的具体原因
			// （签名错 / 过期 / 算法不对）对攻击者是有效信息。
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "凭证无效或已过期"})
			return
		}

		// 放进 context 的一定是 uint —— claims.UID 的静态类型就是 uint。
		// 这条类型契约很关键：gin 的 c.GetUint 在类型对不上时既不报错也不
		// panic，而是静默返回 0。那会让后面所有查询悄悄变成 user_id = 0，
		// 表现为"列表永远是空的"，去查前端查数据库都查不出问题在哪。
		c.Set(ContextUID, claims.UID)
		c.Next()
	}
}
