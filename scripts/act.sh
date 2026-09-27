#!/usr/bin/env bash
#
# 在本机跑 .github/workflows/ 里的 workflow（用 act）。
#
#   ./scripts/act.sh -l              # 列出 job
#   ./scripts/act.sh -j backend      # 只跑 backend
#   ./scripts/act.sh                 # 跑全部
#
# 默认就是普通的 act 调用 —— act 会自己从 github.com 拉取 action。
#
# ---------------------------------------------------------------------------
# 网络说明（这一节改过一次，之前的结论是错的）
# ---------------------------------------------------------------------------
# **github.com 在这台机器上是通的，但是间歇性的。**
#
# 早先的版本在这里写"github.com 直连不通"，那是从一次失败推广出来的错误结论。
# 实测：连续 10 次访问 github.com 全部 200，连接耗时 0.25 秒；
# `git clone https://github.com/actions/setup-go` 也完全正常。
#
# 但间歇性是真的：act 有一次确实在 `git clone` 上失败了，报
#   dial tcp 20.205.243.166:443: i/o timeout
# 同一个时刻 `flutter doctor` 也报 "Connection closed before full header"。
# 这两个是同一个现象的不同表现 —— 连接被中途掐断，而不是稳定地被墙。
#
# 问题在于 **act 的 clone 没有重试**：一次超时整个 job 就废了。
# 所以留一条绕路作为兜底，而不是当默认。
#
# ---------------------------------------------------------------------------
# 兜底：用本地 action 缓存（github.com 抽风时用）
# ---------------------------------------------------------------------------
#   ACT_LOCAL_ACTIONS=1 ./scripts/act.sh -j backend
#
# 做法是先从 codeload.github.com 抓 action 的 tarball 到本地（那个域名稳定得多），
# 再用 act 的 --local-repository 把仓库映射过去。
# **workflow 文件一个字都不用改** —— 这是关键：改 workflow 去迁就本机，
# 就等于验证了另一份东西。
#
# ---------------------------------------------------------------------------
# 已知限制
# ---------------------------------------------------------------------------
# - **publish job 跑不了**：需要 registry 凭据（GITHUB_TOKEN），本机没有。
#   `-l` 能证明它的结构和依赖关系合法，仅此而已。
#
# - **e2e job 会和正在运行的栈打架**。它执行 `docker compose up -d --build`，
#   而容器里的工作目录名恰好也叫 todo-app，于是 compose 推导出的项目名
#   和你本地那个栈**完全相同** —— 它不是在旁边另起一套，而是直接重建你的
#   容器、抢 8081 端口。实测确实如此（数据卷不受影响）。
#   所以跑 e2e 之前先 `docker compose down`，跑完再 `make up`。
#
# - **GOPROXY**：workflow 里已经显式设成 goproxy.cn 了（和 backend/Dockerfile
#   保持一致）。不设的话默认的 proxy.golang.org 会卡满 5 分钟再报 i/o timeout ——
#   这一条是稳定复现的，不是间歇性的。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTIONS_CACHE="${ACTIONS_CACHE:-$HOME/.cache/act-actions}"

if ! command -v act >/dev/null 2>&1; then
  echo "找不到 act。装法（走 Go 模块代理，比从 GitHub releases 下更稳）：" >&2
  echo "  go install github.com/nektos/act@latest     # 产物在 \$(go env GOPATH)/bin/act" >&2
  exit 1
fi

if [[ "${ACT_LOCAL_ACTIONS:-0}" != "1" ]]; then
  # 默认路径：让 act 自己去 github.com 拉。
  exec act -C "$REPO_ROOT" "$@"
fi

# ---- 以下是兜底路径，只在 ACT_LOCAL_ACTIONS=1 时走 ----

# workflow 里用到的全部 action。**加了新的 `uses:` 就要在这里补一行。**
ACTIONS=(
  "actions/checkout:v4"
  "actions/setup-go:v5"
  "actions/setup-node:v4"
  "docker/setup-buildx-action:v3"
  "docker/login-action:v3"
  "docker/build-push-action:v6"
)

mkdir -p "$ACTIONS_CACHE"
LOCAL_REPOS=()

for spec in "${ACTIONS[@]}"; do
  repo="${spec%%:*}"          # actions/checkout
  ref="${spec##*:}"           # v4
  name="$(basename "$repo")"  # checkout
  dest="$ACTIONS_CACHE/$name"

  if [[ ! -f "$dest/action.yml" && ! -f "$dest/action.yaml" ]]; then
    echo "  抓取 $repo@$ref ..."
    tmp="$(mktemp -d)"
    if ! curl -fsSL --max-time 120 -o "$tmp/a.tar.gz" \
         "https://codeload.github.com/$repo/tar.gz/refs/tags/$ref" 2>/dev/null; then
      echo "    codeload 失败，改用镜像..."
      curl -fsSL --max-time 120 -o "$tmp/a.tar.gz" \
        "https://gh-proxy.com/https://github.com/$repo/archive/refs/tags/$ref.tar.gz"
    fi
    mkdir -p "$dest"
    tar -xzf "$tmp/a.tar.gz" -C "$dest" --strip-components=1   # 剥掉 <name>-<ref>/ 前缀
    rm -rf "$tmp"
  fi

  # 不带 host 前缀的写法能匹配任意 host/protocol（act 文档里说明了）。
  LOCAL_REPOS+=(--local-repository "$repo@$ref=$dest")
done

echo "本地 action 缓存: $ACTIONS_CACHE"
exec act -C "$REPO_ROOT" "${LOCAL_REPOS[@]}" "$@"
