#!/usr/bin/env bash
#
# 在本机跑 .github/workflows/ 里的 workflow（用 act）。
#
#   ./scripts/act.sh -l              # 列出 job
#   ./scripts/act.sh -j backend      # 只跑 backend
#   ./scripts/act.sh                 # 跑全部
#
# ---------------------------------------------------------------------------
# 为什么需要这层包装
# ---------------------------------------------------------------------------
# 这台机器上 **github.com 直连不通**，而 act 默认会用 git clone 从 github.com
# 拉取每一个 `uses:` 引用的 action —— 于是任何 workflow 都挂在第一步：
#
#   Unable to clone https://github.com/actions/setup-go:
#     dial tcp 20.205.243.166:443: i/o timeout
#
# 但实测 **codeload.github.com 是通的**（网络策略似乎只挡了 github.com 主站，
# 没挡 tarball 的 CDN 域名）。所以这里的做法是：
#
#   1. 经 codeload.github.com 把 action 的 tarball 抓到本地缓存（只抓一次）
#   2. 用 act 的 --local-repository 把仓库映射到本地目录
#
# **workflow 文件一个字都不用改** —— 验证的仍然是真实的那份 YAML。
# 这是关键的取舍：改 workflow 去迁就本机，就等于验证了另一份东西。
#
# ---------------------------------------------------------------------------
# 已知限制
# ---------------------------------------------------------------------------
# - **publish job 跑不了**：需要 registry 凭据（GITHUB_TOKEN），本机没有。
#   `-l` 能证明它的结构和依赖关系合法，仅此而已。
#
# - **e2e job 有额外风险**：它要执行 `docker compose up -d --build`，即在容器里
#   用 Docker。act 默认会挂宿主机的 docker socket（启动日志里的
#   "daemon socket 'unix:///var/run/docker.sock'" 就是它），但容器里还得有
#   docker CLI，且 compose 的端口发布、卷路径都可能在嵌套环境里行为不同。
#   这一条单独看结论，别让它牵连另外两个 job。
#
# - **GOPROXY**：workflow 里已经显式设成 goproxy.cn 了（和 backend/Dockerfile
#   保持一致）。不设的话默认的 proxy.golang.org 在这台机器上会卡满 5 分钟
#   再报 i/o timeout。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTIONS_CACHE="${ACTIONS_CACHE:-$HOME/.cache/act-actions}"

# workflow 里用到的全部 action。**加了新的 `uses:` 就要在这里补一行**，
# 否则 act 会退回 git clone 然后卡在 github.com 上。
ACTIONS=(
  "actions/checkout:v4"
  "actions/setup-go:v5"
  "actions/setup-node:v4"
  "docker/setup-buildx-action:v3"
  "docker/login-action:v3"
  "docker/build-push-action:v6"
)

if ! command -v act >/dev/null 2>&1; then
  echo "找不到 act。装法（github.com 不通，所以走 Go 模块代理）：" >&2
  echo "  go install github.com/nektos/act@latest     # 产物在 \$(go env GOPATH)/bin/act" >&2
  exit 1
fi

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
    # codeload 直连可用；失败时退到镜像。
    if ! curl -fsSL --max-time 120 -o "$tmp/a.tar.gz" \
         "https://codeload.github.com/$repo/tar.gz/refs/tags/$ref" 2>/dev/null; then
      echo "    codeload 失败，改用镜像..."
      curl -fsSL --max-time 120 -o "$tmp/a.tar.gz" \
        "https://gh-proxy.com/https://github.com/$repo/archive/refs/tags/$ref.tar.gz"
    fi
    mkdir -p "$dest"
    # tarball 里有一层 <name>-<ref>/ 前缀，剥掉它。
    tar -xzf "$tmp/a.tar.gz" -C "$dest" --strip-components=1
    rm -rf "$tmp"
  fi

  # 不带 host 前缀的写法能匹配任意 host/protocol（act 的文档里说明了）。
  LOCAL_REPOS+=(--local-repository "$repo@$ref=$dest")
done

echo "本地 action 缓存: $ACTIONS_CACHE"
echo

exec act -C "$REPO_ROOT" "${LOCAL_REPOS[@]}" "$@"
