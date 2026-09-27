package auth

import (
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// 32 字节，和 config 对 JWT_SECRET 的要求一致。
var testSecret = []byte("0123456789abcdef0123456789abcdef")

func newTestAuth(ttl time.Duration) *Auth { return New(testSecret, ttl) }

func TestPasswordHashRoundTrip(t *testing.T) {
	const pw = "correct horse battery staple"

	hash, err := HashPassword(pw)
	if err != nil {
		t.Fatalf("哈希失败: %v", err)
	}
	if hash == pw {
		t.Fatal("哈希结果和明文相同 —— 说明根本没做哈希")
	}
	if !CheckPassword(hash, pw) {
		t.Fatal("正确的密码没有通过校验")
	}
	if CheckPassword(hash, pw+"x") {
		t.Fatal("错误的密码通过了校验")
	}
	if CheckPassword(hash, "") {
		t.Fatal("空密码通过了校验")
	}
}

// bcrypt 每次加盐，同一个密码两次哈希必须不同，
// 否则说明实现退化成了无盐摘要（彩虹表可直接命中）。
func TestPasswordHashIsSalted(t *testing.T) {
	a, err := HashPassword("same-password")
	if err != nil {
		t.Fatalf("哈希失败: %v", err)
	}
	b, err := HashPassword("same-password")
	if err != nil {
		t.Fatalf("哈希失败: %v", err)
	}
	if a == b {
		t.Fatal("两次哈希结果相同 —— 没有加盐")
	}
}

func TestTokenRoundTrip(t *testing.T) {
	a := newTestAuth(time.Hour)

	token, err := a.Generate(42, "alice")
	if err != nil {
		t.Fatalf("签发失败: %v", err)
	}

	claims, err := a.Parse(token)
	if err != nil {
		t.Fatalf("解析失败: %v", err)
	}
	if claims.UID != 42 {
		t.Errorf("UID = %d，期望 42", claims.UID)
	}
	if claims.Subject != "alice" {
		t.Errorf("Subject = %q，期望 alice", claims.Subject)
	}
}

func TestParseRejectsExpiredToken(t *testing.T) {
	// 负数 TTL：签发出来就已经过期。
	a := newTestAuth(-time.Minute)

	token, err := a.Generate(1, "alice")
	if err != nil {
		t.Fatalf("签发失败: %v", err)
	}
	if _, err := a.Parse(token); err == nil {
		t.Fatal("过期的 token 通过了校验")
	}
}

// 这是 jwt v5 的行为陷阱：exp 的语义是"有就校验，没有就放过"。
// 如果没给解析器加 WithExpirationRequired，一个不带 exp 的 token
// 就是永久有效的 —— 而且它不是伪造的，是同一个密钥签出来的真 token。
// 这个测试就是那条选项的回归保护。
func TestParseRejectsTokenWithoutExpiry(t *testing.T) {
	a := newTestAuth(time.Hour)

	// 手工造一个只有 uid、没有 exp 的 token，密钥用的是真密钥。
	claims := Claims{UID: 1}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(testSecret)
	if err != nil {
		t.Fatalf("构造 token 失败: %v", err)
	}

	if _, err := a.Parse(token); err == nil {
		t.Fatal("不带 exp 的 token 通过了校验 —— 它等价于永不过期，必须拒绝")
	}
}

// alg=none 是最经典的绕过手法：把 header 的 alg 改成 none，
// 并去掉签名，指望服务端不验签就接受。
func TestParseRejectsAlgNone(t *testing.T) {
	a := newTestAuth(time.Hour)

	claims := Claims{
		UID: 1,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodNone, claims).
		SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("构造 alg=none token 失败: %v", err)
	}

	if _, err := a.Parse(token); err == nil {
		t.Fatal("alg=none 的 token 通过了校验")
	}
}

// 换算法的混淆攻击：用同一个密钥但改用 HS512 签名。
// WithValidMethods 把算法锁死在 HS256，所以这个也必须被拒。
func TestParseRejectsUnexpectedAlgorithm(t *testing.T) {
	a := newTestAuth(time.Hour)

	claims := Claims{
		UID: 1,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS512, claims).SignedString(testSecret)
	if err != nil {
		t.Fatalf("构造 token 失败: %v", err)
	}

	if _, err := a.Parse(token); err == nil {
		t.Fatal("用 HS512 签的 token 通过了校验 —— 算法没有被锁死")
	}
}

func TestParseRejectsForeignKey(t *testing.T) {
	a := newTestAuth(time.Hour)
	other := New([]byte("ffffffffffffffffffffffffffffffff"), time.Hour)

	token, err := other.Generate(1, "mallory")
	if err != nil {
		t.Fatalf("签发失败: %v", err)
	}
	if _, err := a.Parse(token); err == nil {
		t.Fatal("用别的密钥签的 token 通过了校验")
	}
}

func TestParseRejectsTamperedPayload(t *testing.T) {
	a := newTestAuth(time.Hour)

	token, err := a.Generate(1, "alice")
	if err != nil {
		t.Fatalf("签发失败: %v", err)
	}

	// 改掉 payload 段（中间那段）的一个字符，签名就不再匹配。
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("token 不是三段式: %q", token)
	}
	if parts[1][0] == 'A' {
		parts[1] = "B" + parts[1][1:]
	} else {
		parts[1] = "A" + parts[1][1:]
	}

	if _, err := a.Parse(strings.Join(parts, ".")); err == nil {
		t.Fatal("payload 被篡改的 token 通过了校验")
	}
}

func TestParseRejectsGarbage(t *testing.T) {
	a := newTestAuth(time.Hour)

	for _, s := range []string{"", "not-a-token", "a.b", "a.b.c", "....."} {
		if _, err := a.Parse(s); err == nil {
			t.Errorf("垃圾输入 %q 通过了校验", s)
		}
	}
}
