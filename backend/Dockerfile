# ---------- 阶段一：编译 ----------
FROM golang:1.27-alpine AS builder

# 这台机器的 DNS 把 proxy.golang.org / sum.golang.org 解析到了不通的路径，
# 直连会一直等到超时。用 ARG 而不是写死 ENV：别的网络环境下可以用
# --build-arg 覆盖，而默认值保证在这台机器上开箱即用。
#
# GOSUMDB 不用改：go 会把校验和请求代理穿过 GOPROXY
# （先探 <proxy>/sumdb/sum.golang.org/supported），goproxy.cn 支持这个端点。
# 另外因为 go.sum 是提交进仓库的，构建过程本身并不需要查询校验和数据库。
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY}

# 禁止 go 自动下载工具链。
# 不设的话，一旦 go.mod 里的版本号高于镜像自带的，go 会去 proxy 拖一整个
# toolchain 下来 —— 能成功，但慢、意外，而且让构建时间变得不可预测。
ENV GOTOOLCHAIN=local

WORKDIR /src

# 先只拷依赖清单：依赖比代码变得少得多，这一层能长期命中缓存。
# 反过来先 COPY . 再下载，改一行 Go 代码就要重下全部依赖。
COPY go.mod go.sum ./

# cache mount：模块缓存在多次构建之间保留。
# 注意下面的 go build 必须挂同一个 cache —— cache mount 不在镜像层里，
# 不挂的话 build 阶段会以为依赖没下过，再下一遍。
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

# CGO_ENABLED=0 产出静态链接的二进制，直接丢进 alpine 就能跑。
# 依赖里没有需要 cgo 的：bcrypt 是纯 Go 实现，postgres 驱动走的 pgx 也是纯 Go。
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /out/server ./cmd/server

# ---------- 阶段二：运行 ----------
FROM alpine:3.21

# ca-certificates：出站 HTTPS 需要。
# tzdata：没有它 time.LoadLocation 会失败。本项目统一按 UTC 存储，
#   所以并非必需，但装上的成本是几十 KB，能省掉以后有人写下
#   time.LoadLocation("Asia/Shanghai") 时一个很难懂的报错。
RUN apk add --no-cache ca-certificates tzdata

# 别用 root 跑：这个进程直接暴露在网络请求下，是攻击面最大的一环。
# 8080 是大于 1024 的非特权端口，普通用户就能绑，不需要 root。
RUN adduser -S -D -H -u 10001 app

COPY --from=builder /out/server /usr/local/bin/server

USER app
EXPOSE 8080
ENTRYPOINT ["server"]
