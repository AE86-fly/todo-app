package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// Claims 用强类型而不是 jwt.MapClaims。
//
// MapClaims 从 JSON 解出来的数字一律是 float64，取值要写
// claims["uid"].(float64) —— 裸断言，claims 里没有这个键就是一次 panic。
// 强类型 claims 让"字段不存在/类型不对"在 jwt 库内部变成普通 error。
type Claims struct {
	UID uint `json:"uid"`
	jwt.RegisteredClaims
}

type Auth struct {
	secret []byte
	ttl    time.Duration
}

func New(secret []byte, ttl time.Duration) *Auth {
	return &Auth{secret: secret, ttl: ttl}
}

// HashPassword 用 bcrypt。它是纯 Go 实现，不需要 cgo，
// 所以 CGO_ENABLED=0 的静态构建照样能用。
func HashPassword(pw string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
	return string(b), err
}

func CheckPassword(hash, pw string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(pw)) == nil
}

func (a *Auth) Generate(userID uint, username string) (string, error) {
	now := time.Now()
	claims := Claims{
		UID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   username,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(a.ttl)),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(a.secret)
}

// Parse 校验签名与时效，解出 claims。
//
// 下面两个选项都是必须的，缺任何一个都是安全漏洞：
//
//	WithValidMethods —— 锁死算法。不锁的话，攻击者可以把 JWT header 里的
//	  alg 改成 none，或者用 RS256 公钥当 HMAC 密钥来验签（算法混淆攻击）。
//
//	WithExpirationRequired —— v5 的 exp 语义是"有就校验，没有就放过"。
//	  不加这一条，一个不带 exp 的 token 就是永久有效的。
//	  这是 v5 相对 v4 的行为变化，很容易漏。
func (a *Auth) Parse(tokenStr string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenStr, claims,
		func(t *jwt.Token) (any, error) { return a.secret, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return nil, err
	}
	if !token.Valid {
		return nil, errors.New("token 无效")
	}
	return claims, nil
}
