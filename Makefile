# todo-app 的常用命令。目的是让"接下来该敲什么"不用去翻 README。
#
#   make help
#
# 需要 .env 的 target 会先把它读进环境（set -a; . ./.env; set +a），
# 这样 compose 和容器里跑的命令拿到的是同一份配置。
#
# ---------------------------------------------------------------------------
# 挂载编译（默认路线）
# ---------------------------------------------------------------------------
# 编译和测试都发生在容器里，但源码和产物都是宿主机的 —— 靠 bind mount 接进去，
# 不是拷贝。于是「环境一致」和「迭代快」可以同时拿到：
#
#   镜像构建一次长期复用；每次编译只是起一个临时容器，用完即删。
#   省掉的是打包镜像层和重建容器，跟编译器本身无关，所以是秒级。
#
# 为什么不直接用宿主机的工具链：宿主机装的 Go / Node 版本会漂移，编出来的东西
# 就可能和发布镜像里的不一致。用容器里那份，和 Dockerfile 的 builder 阶段
# 是同一个镜像、同一套环境变量，结论才有可比性。
#
# 每个工具链都留了 -host 后缀的宿主机版本作应急（Docker 挂了、或想极限速度）。
# 这套做法沿用 c-web/Makefile 里已有的模式。

SHELL := /bin/bash
COMPOSE := docker compose

# set -a 让后续所有赋值自动 export，省掉给每一行单独加 export 的啰嗦。
LOAD_ENV := set -a; . ./.env; set +a

# ---------- 挂载编译用的镜像与命令前缀 ----------

# 从 Dockerfile 的 builder 阶段构建，所以工具链和版本约束都来自那一处，
# 不在 Makefile 里重复一遍（重复就会漂移）。
GO_BUILDER  := todo-app-go-builder
WEB_BUILDER := todo-app-web-builder

# 所有容器内命令共用的前缀，避免每个 target 重复一长串 -v/-w。
#
# 两个 Go 缓存卷是必需的，原因值得记一笔：
# backend/Dockerfile 里的 `RUN --mount=type=cache,target=/go/pkg/mod` 是
# **cache mount，不会写进镜像层** —— 所以 builder 镜像里其实没有任何模块缓存。
# 不给 /go/pkg/mod 挂个持久卷的话，每次 docker run 都要把所有依赖重下一遍。
# c-web 的 gcc 没有这个问题，因为编译 C 不存在依赖缓存这回事。
GO_RUN := docker run --rm \
  -v "$(CURDIR)/backend":/src -w /src \
  -v todo-app-gomod:/go/pkg/mod \
  -v todo-app-gocache:/root/.cache/go-build

# 前端同理，另外多一个 node_modules 卷：
# 宿主机那份 node_modules 是给宿主机 npm 用的，挂进容器会因平台差异出问题，
# 所以容器里单独留一份在命名卷里。
WEB_RUN := docker run --rm \
  -v "$(CURDIR)":/ctx -w /ctx/web \
  -v todo-app-npmcache:/root/.npm \
  -v todo-app-nodemods:/ctx/web/node_modules

.PHONY: help up down logs ps restart build check verify \
        go-builder web-builder ensure-go-builder ensure-web-builder web-deps \
        build-go vet-go test-go test-store go-tidy \
        type-check build-web \
        build-go-host vet-go-host test-go-host type-check-host build-web-host \
        flutter-analyze flutter-test flutter-web flutter-linux \
        api-dev web-dev gui gui-stop psql clean clean-build-cache

help: ## 显示所有可用命令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------- 编排 ----------

up: ## 启动整套（会构建镜像）
	$(COMPOSE) up -d --build
	@echo "→ http://localhost:8081"

down: ## 停止并删除容器（保留数据卷）
	$(COMPOSE) down

restart: ## 重启所有服务
	$(COMPOSE) restart

ps: ## 查看各服务状态
	$(COMPOSE) ps

logs: ## 跟踪日志（Ctrl-C 退出）
	$(COMPOSE) logs -f

build: ## 只构建发布镜像，不启动
	$(COMPOSE) build

# ---------- 挂载编译：工具链镜像 ----------

go-builder: ## 构建 Go 工具链镜像（改过 go.mod 或 Dockerfile 后需要重跑）
	docker build --target builder -t $(GO_BUILDER) ./backend

web-builder: ## 构建 Node 工具链镜像（改过 package.json 或 Dockerfile 后需要重跑）
	docker build --target builder -t $(WEB_BUILDER) -f web/Dockerfile .

# 下面每个 target 都先跑这个：镜像不存在就建，存在就跳过。
# 一次 docker image inspect，开销可以忽略，换来的是第一次用不会报错。
ensure-go-builder:
	@docker image inspect $(GO_BUILDER) >/dev/null 2>&1 \
	  || $(MAKE) --no-print-directory go-builder

ensure-web-builder:
	@docker image inspect $(WEB_BUILDER) >/dev/null 2>&1 \
	  || $(MAKE) --no-print-directory web-builder

# 确保卷里的 node_modules 和 package-lock.json 一致。
#
# 判断依据是 lock 文件的哈希，而不是"node_modules 存在吗"——
# 后者在 package-lock.json 改了之后不会触发重装，会静默沿用旧依赖，
# 属于"本地好好的、CI 上挂了"那种最难查的故障。
#
# trim 到前 64 个字符是因为 sha256sum 的输出带文件名，
# 用 cut -d' ' 取字段要处理嵌套引号，直接截长度更省事也更不容易写错。
web-deps: ## 确保容器里的前端依赖和 package-lock.json 一致
	@$(MAKE) --no-print-directory ensure-web-builder
	@$(WEB_RUN) $(WEB_BUILDER) sh -c '\
	  want=$$(sha256sum package-lock.json | cut -c1-64); \
	  have=$$(cat node_modules/.lock-stamp 2>/dev/null); \
	  if [ "$$want" != "$$have" ]; then \
	    echo "  依赖有变化，在容器里装..."; \
	    npm ci && echo "$$want" > node_modules/.lock-stamp; \
	  fi'

# ---------- 挂载编译：后端 ----------

build-go: ## 容器内编译后端
	@$(MAKE) --no-print-directory ensure-go-builder
	$(GO_RUN) $(GO_BUILDER) go build ./...

vet-go: ## 容器内静态检查后端
	@$(MAKE) --no-print-directory ensure-go-builder
	$(GO_RUN) $(GO_BUILDER) go vet ./...

test-go: ## 容器内跑后端单元测试（不需要数据库）
	@$(MAKE) --no-print-directory ensure-go-builder
	$(GO_RUN) $(GO_BUILDER) go test ./... -count=1

go-tidy: ## 容器内 go mod tidy（go.mod/go.sum 直接写回宿主机）
	@$(MAKE) --no-print-directory ensure-go-builder
	@# 产物直接落在宿主机，这正是挂载编译比"容器里跑完再拷出来"省事的地方。
	$(GO_RUN) $(GO_BUILDER) go mod tidy

test-store: ## 容器内跑 store 集成测试（需要 db 在运行）
	@$(MAKE) --no-print-directory ensure-go-builder
	@# 网络名动态取，不写死 todo-app_default —— 项目名或 compose 文件改了就不对了。
	@# 取不到说明 db 没起来，直接给出提示，而不是让测试连一圈超时。
	@$(LOAD_ENV); \
	  net=$$(docker inspect todo-db \
	    --format '{{range $$k,$$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null); \
	  if [ -z "$$net" ]; then echo "db 没在运行，先 make up"; exit 1; fi; \
	  $(GO_RUN) --network "$$net" \
	    -e DB_HOST=db -e DB_PORT=5432 \
	    -e DB_USER="$$POSTGRES_USER" -e DB_PASSWORD="$$POSTGRES_PASSWORD" -e DB_NAME="$$POSTGRES_DB" \
	    $(GO_BUILDER) go test ./internal/store -v -count=1
	@# 这里同样要做 POSTGRES_* → DB_* 的映射，和 api-dev 里是同一个坑：
	@# .env 用 postgres 镜像的变量名，后端代码读的是 DB_*。

# ---------- 挂载编译：前端 ----------

type-check: ## 容器内跑前端类型检查
	@$(MAKE) --no-print-directory web-deps
	$(WEB_RUN) $(WEB_BUILDER) npm run type-check

build-web: ## 容器内构建前端（dist 直接写回宿主机）
	@$(MAKE) --no-print-directory web-deps
	$(WEB_RUN) $(WEB_BUILDER) npm run build

# ---------- 宿主机版本（应急退路） ----------
# Docker 出问题时用这些。注意工具链版本可能和发布镜像不同，
# 结论不能直接当成"发布构建也长这样"。

build-go-host: ## 宿主机编译后端（需要本机装了 Go）
	cd backend && go build ./...

vet-go-host: ## 宿主机静态检查后端
	cd backend && go vet ./...

test-go-host: ## 宿主机跑后端测试
	cd backend && go test ./... -count=1

type-check-host: ## 宿主机跑前端类型检查（需要本机装了 Node）
	cd web && npm run type-check

build-web-host: ## 宿主机构建前端
	cd web && npm run build

# ---------- 验证 ----------

verify: ## 端到端验收：对已启动的服务跑全部断言
	./scripts/verify.sh

# check 是 CI 的本地等价物：CI 里那些步骤，这里全都能跑、能看红绿。
# 先用 make check 把每一步做绿，CI 配置文件就只剩一层薄包装 ——
# 反过来先写 CI，就是写一份没人跑过的 YAML。
check: vet-go test-go type-check flutter-analyze flutter-test ## 本地跑一遍 CI 会跑的所有检查
	@echo "全部检查通过"

# ---------- Flutter（这三条不走容器） ----------
#
# 它们的构建没法用容器内挂载编译：
#   Linux 桌面版需要显示服务（容器里没有），Windows exe 只能在 Windows 上编。
# 所以 Flutter 依旧用宿主机的 SDK。

flutter-analyze: ## 静态检查 Flutter 代码
	cd app && flutter analyze

flutter-test: ## 跑 Flutter 测试
	cd app && flutter test

flutter-linux: ## 构建 Flutter Linux 桌面版
	@# 需要 clang / ninja / pkg-config / libgtk-3-dev / liblzma-dev，
	@# 缺任何一个 flutter doctor 会把 Linux toolchain 标成 ✗。
	cd app && flutter build linux --release
	@echo "→ app/build/linux/x64/release/bundle/todo_app"
	@# 桌面版的 base URL 是 http://127.0.0.1:8080/api，
	@# 所以要它真能用，得先在另一个终端跑 make api-dev。
	@echo "   （运行前先 make api-dev 把后端起到宿主机的 8080）"

flutter-web: ## 构建 Flutter web 产物并挂载到 nginx 的 /app/
	cd app && flutter build web --release --base-href=/app/
	@# 构建完必须重启 web 容器，不能省。
	@# flutter build 会删掉并重建 build/web 目录，而容器里的 bind mount
	@# 还指着已经被删掉的那个旧目录 inode —— 不重启的话，容器里看到的
	@# 是一个空目录，/app/ 下所有请求全部 404，且从宿主机看不出任何异常
	@# （宿主机上文件明明都在）。这个现象很容易被误判成 nginx 配置写错了。
	@$(COMPOSE) restart web >/dev/null
	@echo "→ http://localhost:8081/app/"

# ---------- 开发 ----------

web-dev: ## 启动 Vite dev server（热重载，:5173）
	$(COMPOSE) --profile dev up -d web-dev
	@echo "→ http://localhost:5173"

gui: ## 用浏览器看 Flutter 桌面版（绕开 WSLg，见 scripts/gui.sh 顶部说明）
	@./scripts/gui.sh start

gui-stop: ## 停掉 gui 启动的那一堆进程
	@./scripts/gui.sh stop

api-dev: ## 在容器里跑后端并热重载（:8080），需要 db 在运行
	@# 这里必须做一次变量名映射，不能直接 . ./.env 了事。
	@# .env 里用的是 POSTGRES_*（postgres 官方镜像的变量名），
	@# 而后端读的是 DB_*（见 internal/config/config.go）。
	@# compose 里是靠 environment: 显式映射的，这里没有那层，
	@# 少了这几行后端会拿着空密码去连，报 28P01 认证失败 ——
	@# 而报错信息里只会说密码不对，不会提示是变量名没对上。
	@$(LOAD_ENV); \
	  net=$$(docker inspect todo-db \
	    --format '{{range $$k,$$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null); \
	  if [ -z "$$net" ]; then echo "db 没在运行，先 make up"; exit 1; fi; \
	  $(GO_RUN) --network "$$net" \
	    -e PORT=8080 \
	    -e DB_HOST=db -e DB_PORT=5432 \
	    -e DB_USER="$$POSTGRES_USER" -e DB_PASSWORD="$$POSTGRES_PASSWORD" -e DB_NAME="$$POSTGRES_DB" \
	    -e JWT_SECRET="$$JWT_SECRET" \
	    -p 127.0.0.1:8080:8080 \
	    $(GO_BUILDER) go run ./cmd/server

api-dev-host: ## 在宿主机跑后端（需要本机装了 Go；连的是 compose 的 db）
	@$(LOAD_ENV); cd backend && \
	  DB_HOST=127.0.0.1 DB_PORT=5433 PORT=8080 \
	  DB_USER="$$POSTGRES_USER" DB_PASSWORD="$$POSTGRES_PASSWORD" DB_NAME="$$POSTGRES_DB" \
	  JWT_SECRET="$$JWT_SECRET" \
	  go run ./cmd/server

psql: ## 连进 compose 里的数据库
	@$(LOAD_ENV); \
	  docker compose exec db psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"

clean: ## 删掉容器和数据卷（数据会丢）
	$(COMPOSE) down -v

clean-build-cache: ## 删掉挂载编译用的缓存卷（下次会重新下载依赖）
	@# 注意这几个卷不在 compose.yaml 里，是 docker run -v 自动创建的，
	@# 所以 docker compose down -v 删不掉它们，得单独清。
	-docker volume rm todo-app-gomod todo-app-gocache todo-app-npmcache todo-app-nodemods
