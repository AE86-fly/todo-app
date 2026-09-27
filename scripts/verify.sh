#!/usr/bin/env bash
#
# 端到端验收。每一项都是断言，失败会以非零码退出 ——
# 这个脚本的意义在于"能红"，而不在于"能跑完并打印一堆 OK"。
#
#   ./scripts/verify.sh          # 默认打 127.0.0.1:8081
#   BASE=http://host:port ./scripts/verify.sh
#
# 每次运行都用带时间戳的用户名，所以可以反复跑，不会撞唯一约束。

set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8081}"
RUN_ID="$(date +%s)$$"
ALICE="alice_${RUN_ID}"
BOB="bob_${RUN_ID}"
PASSWORD="secret-${RUN_ID}"

pass=0
fail=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail + 1)); }

check() {
  # check <描述> <实际> <期望>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 —— 期望 [$3]，实际 [$2]"; fi
}

# 发请求并回一个 "状态码<TAB>响应体"。不用 -f，
# 因为 401/404 这些正是我们要断言的状态，不是错误。
req() {
  local method="$1" path="$2" token="${3:-}" body="${4:-}"
  local args=(-sS -o /tmp/verify.body -w '%{http_code}' -X "$method" "${BASE}${path}")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
  fi
  local code
  code="$(curl "${args[@]}")"
  printf '%s\t%s' "$code" "$(cat /tmp/verify.body)"
}

status() { printf '%s' "${1%%$'\t'*}"; }
body()   { printf '%s' "${1#*$'\t'}"; }

echo "→ 目标: $BASE"
echo

# ---------------------------------------------------------------
echo '[1] 静态页面与健康检查'
# ---------------------------------------------------------------
r="$(req GET /)"
check "GET / 返回 200" "$(status "$r")" "200"
if [[ "$(body "$r")" == *'<div id="app">'* ]]; then
  ok "首页里有 Vue 的挂载点"
else
  bad "首页里没有 <div id=\"app\">，nginx 发的可能不是 Vue 产物"
fi

r="$(req GET /readyz)"
check "GET /readyz 返回 200" "$(status "$r")" "200"
if [[ "$(body "$r")" == *'"status":"ok"'* ]]; then
  ok "/readyz 报告数据库连通"
else
  bad "/readyz 没有报告 ok：$(body "$r")"
fi

# SPA 兜底：直接访问前端路由不能 404，否则刷新页面就白屏
r="$(req GET /login)"
check "GET /login 走 SPA 兜底返回 200" "$(status "$r")" "200"

# ---------------------------------------------------------------
echo
echo '[2] 注册'
# ---------------------------------------------------------------
r="$(req POST /api/auth/register "" "{\"username\":\"$ALICE\",\"password\":\"$PASSWORD\"}")"
check "注册 alice 返回 201" "$(status "$r")" "201"
ALICE_TOKEN="$(body "$r" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
if [[ -n "$ALICE_TOKEN" ]]; then ok "拿到 alice 的 token"; else bad "响应里没有 token"; fi

if [[ "$(body "$r")" == *'"password"'* ]]; then
  bad "注册响应里泄露了 password 字段"
else
  ok "注册响应没有泄露密码字段"
fi

r="$(req POST /api/auth/register "" "{\"username\":\"$BOB\",\"password\":\"$PASSWORD\"}")"
check "注册 bob 返回 201" "$(status "$r")" "201"
BOB_TOKEN="$(body "$r" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"

# 重名必须是 409，而不是 500、也不是 201
r="$(req POST /api/auth/register "" "{\"username\":\"$ALICE\",\"password\":\"$PASSWORD\"}")"
check "重复用户名返回 409" "$(status "$r")" "409"

# 密码长度不满足 binding 约束
r="$(req POST /api/auth/register "" '{"username":"shortpw","password":"123"}')"
check "密码过短返回 400" "$(status "$r")" "400"

# ---------------------------------------------------------------
echo
echo '[3] 登录与鉴权'
# ---------------------------------------------------------------
r="$(req POST /api/auth/login "" "{\"username\":\"$ALICE\",\"password\":\"$PASSWORD\"}")"
check "正确密码登录返回 200" "$(status "$r")" "200"

r="$(req POST /api/auth/login "" "{\"username\":\"$ALICE\",\"password\":\"wrong-password\"}")"
check "错误密码返回 401" "$(status "$r")" "401"

r="$(req POST /api/auth/login "" '{"username":"nobody_at_all","password":"whatever123"}')"
check "不存在的用户返回 401（不是 404）" "$(status "$r")" "401"

r="$(req GET /api/todos)"
check "不带 token 访问待办返回 401" "$(status "$r")" "401"

r="$(req GET /api/todos "not-a-real-token")"
check "伪造的 token 返回 401" "$(status "$r")" "401"

# ---------------------------------------------------------------
echo
echo '[4] 空列表必须是 [] 而不是 null'
# ---------------------------------------------------------------
r="$(req GET /api/todos "$BOB_TOKEN")"
check "bob 首次查询返回 200" "$(status "$r")" "200"
# 这一条是整个套件里最容易误诊的：GORM 返回 nil slice 时 JSON 会变成 null，
# 前端把 null 当数组用会直接抛异常白屏，而排查的人通常会先怀疑前端。
check "空列表的响应体恰好是 []" "$(body "$r")" "[]"

# ---------------------------------------------------------------
echo
echo '[5] 增删改查'
# ---------------------------------------------------------------
r="$(req POST /api/todos "$ALICE_TOKEN" '{"title":"学习 JWT"}')"
check "alice 创建待办返回 201" "$(status "$r")" "201"
ALICE_TODO_ID="$(body "$r" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')"
if [[ -n "$ALICE_TODO_ID" ]]; then ok "拿到待办 id=$ALICE_TODO_ID"; else bad "响应里没有 id"; fi

r="$(req POST /api/todos "$ALICE_TOKEN" '{"title":"第二条"}')"
check "再创建一条返回 201" "$(status "$r")" "201"

r="$(req GET /api/todos "$ALICE_TOKEN")"
check "alice 看到 2 条" "$(body "$r" | grep -o '"id":' | wc -l | tr -d ' ')" "2"
# 后端按 id desc 排序，最新的在前。前端的插入顺序必须和它一致。
if [[ "$(body "$r")" == *'"title":"第二条"'*'"title":"学习 JWT"'* ]]; then
  ok "列表按新的在前排序"
else
  bad "列表顺序不对：$(body "$r")"
fi

# ---------------------------------------------------------------
echo
echo '[6] 用户隔离（本项目的核心需求）'
# ---------------------------------------------------------------
r="$(req GET /api/todos "$BOB_TOKEN")"
check "bob 仍然看不到 alice 的待办" "$(body "$r")" "[]"

r="$(req PATCH "/api/todos/$ALICE_TODO_ID/toggle" "$BOB_TOKEN")"
check "bob 翻转 alice 的待办返回 404" "$(status "$r")" "404"

r="$(req DELETE "/api/todos/$ALICE_TODO_ID" "$BOB_TOKEN")"
check "bob 删除 alice 的待办返回 404" "$(status "$r")" "404"

# 越权尝试之后，alice 的数据必须原封不动
r="$(req GET /api/todos "$ALICE_TOKEN")"
if [[ "$(body "$r")" == *'"done":false'* ]]; then
  ok "越权尝试后 alice 的待办未被改动"
else
  bad "alice 的待办被改动了：$(body "$r")"
fi

# ---------------------------------------------------------------
echo
echo '[7] 翻转与删除'
# ---------------------------------------------------------------
r="$(req PATCH "/api/todos/$ALICE_TODO_ID/toggle" "$ALICE_TOKEN")"
check "alice 翻转自己的待办返回 200" "$(status "$r")" "200"
if [[ "$(body "$r")" == *'"done":true'* ]]; then
  ok "翻转后返回的 done 是 true（RETURNING 带回的是新值）"
else
  bad "翻转后 done 不是 true：$(body "$r")"
fi

r="$(req PATCH "/api/todos/$ALICE_TODO_ID/toggle" "$ALICE_TOKEN")"
if [[ "$(body "$r")" == *'"done":false'* ]]; then
  ok "再翻一次回到 false"
else
  bad "二次翻转结果不对：$(body "$r")"
fi

r="$(req DELETE "/api/todos/$ALICE_TODO_ID" "$ALICE_TOKEN")"
check "alice 删除自己的待办返回 204" "$(status "$r")" "204"

r="$(req GET /api/todos "$ALICE_TOKEN")"
check "删除后剩 1 条" "$(body "$r" | grep -o '"id":' | wc -l | tr -d ' ')" "1"

r="$(req DELETE "/api/todos/$ALICE_TODO_ID" "$ALICE_TOKEN")"
check "重复删除返回 404" "$(status "$r")" "404"

r="$(req POST /api/todos "$ALICE_TOKEN" '{"title":""}')"
check "空标题返回 400" "$(status "$r")" "400"

r="$(req PATCH /api/todos/abc/toggle "$ALICE_TOKEN")"
check "非数字 id 返回 400（不是 404）" "$(status "$r")" "400"

# ---------------------------------------------------------------
echo
if [[ "$fail" -eq 0 ]]; then
  printf '\033[32m全部通过\033[0m：%d 项\n' "$pass"
else
  printf '\033[31m失败 %d 项\033[0m，通过 %d 项\n' "$fail" "$pass"
fi
rm -f /tmp/verify.body
exit "$((fail > 0 ? 1 : 0))"
