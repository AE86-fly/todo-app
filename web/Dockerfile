# 前端的生产镜像：一个自包含的 nginx，构建好的静态文件已经躺在里面。
#
# 构建上下文是项目根目录（不是 web/），因为 nginx/nginx.conf 在根目录：
#   docker build -f web/Dockerfile -t todo-web .
#
# 为什么不用「拿一个容器把 dist 拷进共享命名卷」那种做法：
#   - 一次性容器和 restart: unless-stopped 直接冲突 —— 要么让它无限重启，
#     要么为它破例（而破例之后"每个服务都有重启策略"这条规则就不再成立了）
#   - 空的命名卷会让 nginx 在产物被写进去之前对任何请求返回 404，
#     而且没有干净的办法表达"等这个一次性容器成功退出再启动 nginx"
#   - cp -r 是增量覆盖、永不删除，卷只涨不缩，旧版本的哈希资源会一直留着
# 多阶段构建把产物直接放进镜像层，上面三个问题一并消失。

# ---------- 阶段一：构建 ----------
FROM node:24-alpine AS builder

WORKDIR /app

# 先只拷依赖清单 —— 依赖很少变，这一层能长期命中缓存。
# 反过来先 COPY . 再 npm ci，改一行 .vue 就会触发完整的依赖重装。
COPY web/package.json web/package-lock.json ./

# cache mount：npm 下载的包在多次构建之间保留，第二次起零下载。
#
# 用 npm ci 而不是 npm install：ci 严格按 lock 文件装，装出来的依赖树
# 在本地、在 CI、在镜像里完全一致；install 会顺手改 lock 文件，
# 构建结果就不再可复现了。这也是 lock 文件必须提交进仓库的原因。
RUN --mount=type=cache,target=/root/.npm \
    npm ci

COPY web/ .
RUN npm run build                       # → /app/dist

# ---------- 阶段二：运行 ----------
FROM nginx:alpine

# 只要构建产物。源码和 node_modules 都不进最终镜像。
COPY --from=builder /app/dist /usr/share/nginx/html

# 放进 conf.d 而不是替换 /etc/nginx/nginx.conf：
# 官方主配置里有 events / http 块和一堆默认设置，整个替换掉等于把它们
# 全扔了还得自己重配一遍。只提供一个 server 块、让主配置 include 它，
# 是最小且最不容易出错的改法。
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
