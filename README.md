# todo-app

一个覆盖完整技术栈的待办事项应用：Go 后端 + Vue 3 前端 + Flutter 客户端 + PostgreSQL，用 Docker Compose 编排，Nginx 统一入口。

支持注册/登录（JWT）和**用户数据隔离**——每个账号只能看到和操作自己的待办。

```
Flutter (web/移动/桌面) ┐
                        ├─→ Nginx ─→ Go (Gin + GORM, JWT 鉴权) ─→ PostgreSQL
Vue 3 (Web) ────────────┘
```

## 快速开始

```bash
cp .env.example .env
# 至少要填这两个，否则 compose 会直接拒绝启动：
#   POSTGRES_PASSWORD  任意强密码
#   JWT_SECRET         openssl rand -hex 32
$EDITOR .env

make up        # 构建并启动，然后访问 http://localhost:8081
make verify    # 端到端验收：35 项断言
```

## 端口

| 服务 | 宿主机 | 说明 |
|---|---|---|
| `web` (nginx) | `127.0.0.1:8081` | 唯一对外入口：Vue 静态文件 + `/api` 反代 + Flutter 的 `/app/` |
| `db` (postgres) | `127.0.0.1:5433` | 只绑回环，留给宿主机直连调试 |
| `api` (Go) | 不发布 | 只有同网络的 nginx 需要连它 |
| `web-dev` (Vite) | `127.0.0.1:5173` | 仅 `--profile dev` 时启动 |

这些端口全部刻意避开了兄弟项目 `c-web`（它占 80 和 5432），所以两个项目可以同时跑。

## 目录结构

```
backend/     Go 后端：cmd/server 入口，internal/ 下按职责分包
  internal/config      集中读环境变量 + 启动即校验
  internal/auth        bcrypt + JWT 签发校验
  internal/db          GORM 连接、连接池、建表
  internal/store       数据访问，把 gorm 错误翻译成自己的语义错误
  internal/handler     HTTP 处理
  internal/middleware  JWT 鉴权
web/         Vue 3 + Vite + Pinia + vue-router
app/         Flutter 客户端
nginx/       容器里 nginx 的 server 配置
scripts/     verify.sh 端到端验收
```

## 开发

三种工作方式，按你改哪一层选：

```bash
# 1. 只改前端 —— Vite 热重载，改一行立刻生效
make web-dev                    # → http://localhost:5173

# 2. 只改后端 —— 容器里跑（源码挂载），改完重启进程
make api-dev                    # → http://localhost:8080

# 3. Flutter 桌面版 —— 也需要后端在宿主机的 8080
make api-dev                    # 另一个终端
make flutter-linux && ./app/build/linux/x64/release/bundle/todo_app

# 4. 整套容器化 —— 和前端的最终形态一致
make up
```

前两种方式都需要数据库在跑，`docker compose up -d db` 即可。

**别绕过 `make api-dev` 自己拼命令**：`.env` 里用的是 `POSTGRES_*`（postgres 官方镜像的变量名），而后端读的是 `DB_*`。compose 里是靠 `environment:` 显式映射的，直接 `docker run` 没有那一层。少了映射，后端会拿着空密码去连，报 `28P01 认证失败` —— 而那个报错只会说密码不对，不会提示是变量名没对上。这个 target 里就是做了这次映射。

## 容器化的编译与测试（挂载编译）

**编译和测试都发生在容器里，宿主机不需要装 Go 和 Node。** 做法是把项目目录 bind mount 进容器，用容器里的工具链编译，产物直接写回宿主机 —— 不是拷贝，是同一个目录的两个视角。

```bash
make test-go          # 容器里跑后端单测
make type-check       # 容器里跑 vue-tsc
make check            # 上面这些 + Flutter 的合集
```

### 为什么不直接用 `docker compose up --build`

那条路每次都要打包镜像层、重建运行容器，几十秒起步。挂载编译省掉的正是这两件事（跟编译器本身无关），所以是秒级。代价只有一个：需要一个长期复用的工具链镜像，构建一次即可：

```bash
make go-builder web-builder    # 改过 go.mod / package.json / Dockerfile 后才需要重跑
```

上面那些 target 会在镜像不存在时自动构建，所以第一次直接 `make test-go` 也不会报错。

### 为什么不直接用宿主机的工具链

宿主机装的 Go / Node 版本会漂移，编出来的东西就可能和发布镜像里的不一致。用容器里那份，和 `Dockerfile` 的 `builder` 阶段是**同一个镜像、同一套环境变量**，结论才有可比性。这也是 `backend/Dockerfile` 里那句注释的意思：

> 用容器里的 gcc 而不是宿主机的，是为了跟发布构建（Dockerfile 里同一个 builder 阶段）保持一致：同一份编译器，编出来的东西一样。

### 三个缓存卷

| 卷 | 缓存什么 | 为什么需要 |
|---|---|---|
| `todo-app-gomod` | `/go/pkg/mod` | **必需**。见下面的说明 |
| `todo-app-gocache` | `/root/.cache/go-build` | 让重复编译快起来 |
| `todo-app-npmcache` | `/root/.npm` | 让 `npm ci` 快起来 |
| `todo-app-nodemods` | 容器里的 `node_modules` | 宿主机那份是给宿主机 npm 用的，挂进容器会因平台差异出问题 |

**`todo-app-gomod` 为什么是必需的**：`backend/Dockerfile` 里的

```dockerfile
RUN --mount=type=cache,target=/go/pkg/mod go mod download
```

是 **cache mount，不会写进镜像层** —— 所以 `--target builder` 出来的镜像里其实**没有任何模块缓存**。不给 `/go/pkg/mod` 挂个持久卷，每次 `docker run` 都要把所有依赖重下一遍。

（`c-web` 里的 `build` target 不需要这一步，因为编译 C 不存在依赖缓存这回事。这是 Go 这边必须多出来的东西。）

清掉这些缓存：`make clean-build-cache`。注意它们不在 `compose.yaml` 里，是 `docker run -v` 自动创建的，所以 `docker compose down -v` 删不掉。

### 前端依赖的一致性

容器里的 `node_modules` 靠 `package-lock.json` 的**哈希**来判断是否需要重装，而不是"目录存不存在"：

```sh
want=$(sha256sum package-lock.json | cut -c1-64)
have=$(cat node_modules/.lock-stamp 2>/dev/null)
[ "$want" = "$have" ] || { npm ci && echo "$want" > node_modules/.lock-stamp; }
```

用存在性判断的话，`package-lock.json` 改了也不触发重装，会**静默沿用旧依赖** —— 属于"本地好好的、CI 上挂了"那种最难查的故障。哈希存在 `node_modules/.lock-stamp` 里，跟着卷一起持久化。

### 应急退路

Docker 出问题时，每个工具链都有宿主机版本，加 `-host` 后缀：

```bash
make test-go-host      # 需要本机装了 Go
make type-check-host   # 需要本机装了 Node
```

注意它们的工具链版本可能和发布镜像不同，结论不能直接当成"发布构建也长这样"。

**Flutter 不走容器**：Linux 桌面版需要显示服务（容器里没有），Windows exe 只能在 Windows 上编，两者都与容器内挂载编译不兼容，所以 Flutter 依旧用宿主机的 SDK。

## 验证

除 Flutter 外都在容器里跑（见上一节）。

| 命令 | 覆盖范围 |
|---|---|
| `make test-go` | 后端单元测试（10 个），不需要数据库 |
| `make test-store` | store 集成测试（7 个），需要 `db` 在运行 |
| `make vet-go` | 后端静态检查 |
| `make type-check` | 前端 TypeScript 类型检查 |
| `make build-go` / `build-web` | 容器内编译（产物写回宿主机） |
| `make flutter-analyze` / `flutter-test` | Flutter 静态检查与测试（6 个） |
| `make flutter-web` / `flutter-linux` | Flutter 两个平台的构建（web 已端到端验证；桌面版见下文说明） |
| `make verify` | 端到端：对已启动的服务跑 35 项断言 |
| `make check` | 上面这些的合集（见下），覆盖面与 CI 相同 |

`make check` = `vet-go` + `test-go` + `type-check` + `flutter-analyze` + `flutter-test`。加 `-host` 后缀可切回宿主机版本（应急用，见上一节）。

`scripts/verify.sh` 里的每一项都是**断言**（失败以非零码退出），不是打印给人看的日志。它专门覆盖了几处容易出错的边界：

- 空列表必须返回 `[]` 而不是 `null`
- 重复用户名必须是 409 而不是 500；数据库故障不能被伪装成"用户名已存在"
- 密码错误和不存在的用户必须返回一模一样的 401（否则就是个用户名枚举接口）
- **用户隔离**：bob 看不到、也删不掉 alice 的待办，且越权尝试后 alice 的数据原封不动
- 翻转两次必须回到原值（验证 `UPDATE ... RETURNING` 带回的是新值）

## 关于 Flutter 客户端

Flutter 代码在 `app/`，**web 和 Linux 桌面两个平台的构建都已验证**（`make flutter-web` / `make flutter-linux`）。

- **web**：产物由 nginx 在 `/app/` 下提供，与 Vue 前端同源，所以 API base URL 用的是相对路径 `/api`，不涉及跨域。
- **Linux 桌面**：产物在 `app/build/linux/x64/release/bundle/`，可执行文件旁边就是它需要的 `lib/` 和 `data/`，整个目录一起拷走就能运行。桌面版的 base URL 是 `http://127.0.0.1:8080/api`，所以跑它之前需要后端在宿主机的 8080 上（`make api-dev`，它连的是 compose 里那个 db）。

Android 未验证，需要 JDK + Android SDK。

### 平台判断为什么不用 `dart:io`

`lib/api/base_url.dart` 用的是 `package:flutter/foundation.dart` 里的 `kIsWeb` / `defaultTargetPlatform`，而不是 `dart:io` 的 `Platform`。这一点值得说明，因为直觉上两者的差别并不明显：

实测（Flutter 3.47.5 / Dart 3.13.4，`flutter build web --release`）：

| 写法 | 编译 | 浏览器里 |
|---|---|---|
| `import 'dart:io' show Platform;` | **通过**（53s，无报错） | **全白**，应用启动即崩 |
| `kIsWeb` + `defaultTargetPlatform` | 通过 | 正常渲染 |

也就是说 `dart:io` 在 web 上**不是编译错误**，而是**运行时崩溃**——这反而更麻烦：构建成功、镜像推上去了、部署也"成功"了，然后用户看到一片白。只有真的在浏览器里打开过才能发现。

用 foundation 还有一个附带好处：`kIsWeb` 是编译期常量，web 构建会直接把移动端分支整个 tree-shake 掉。可以自己验证 —— 产物里搜不到 `10.0.2.2`：

```bash
grep -c '10.0.2.2' app/build/web/main.dart.js   # → 0
```

### 挂载产物的一个坑

`make flutter-web` 在构建之后会**重启 web 容器**，不能省。`flutter build` 会删掉并重建 `build/web` 目录，而容器里的 bind mount 还指着已被删除的旧 inode —— 不重启的话容器里看到的是空目录，`/app/` 全 404，而宿主机上文件明明都在，很容易误判成 nginx 配置问题。

### 桌面版依赖

Linux 桌面构建需要这些系统包，已经装好了：

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
```

装不上（没有 sudo）时 `flutter doctor` 会把 Linux toolchain 标成 ✗，`flutter build linux` 也跑不了。

**关于"看不到界面"**：这台机器上做过完整排查，结论是**跑得起来、渲染也正常，但显示不出来**——而且这与本项目的代码无关。原因有两个叠加：

1. **WSL 全局设了 `WAYLAND_DISPLAY=wayland-0`。** GTK 只要看到这个变量就优先选 Wayland 而**忽略 `DISPLAY`**，于是所有 GUI 程序都被路由到 WSLg。这是最隐蔽的一环：你以为在用 Xvfb，其实根本没连上去。
2. **宿主是 Windows 10 build 19045，而 WSLg 是 Windows 11 的功能。** 在 Win10 上 WSLg 退化成 `[WARN:COPY MODE]`：任务栏有条目，窗口打不开、看不到内容。

拿 `glxgears`（与 Flutter 毫无关系的最简 GL 程序）对照，表现**完全一致**（任务栏有条目、窗口打不开），而它本身渲染正常（1054 FPS，llvmpipe）。`weston.log` 里 RAIL shell 也正常启动并正确识别出 Flutter 窗口（`appId:com.example.todo_app`）。所以断的是 WSLg → Windows 的**呈现**层，不是应用。

### 怎么看桌面版

```bash
make api-dev     # 一个终端：后端起到宿主机 8080
make gui         # 另一个终端：启动虚拟屏幕 + VNC
# 然后浏览器打开 http://localhost:6080/vnc.html
make gui-stop    # 用完停掉
```

`make gui` 会在 WSL 里起 Xvfb（虚拟屏幕）+ x11vnc + noVNC，**不需要在 Windows 上装任何东西，也不需要管理员权限**。原理和每一步的坑都写在 `scripts/gui.sh` 顶部的注释里。

已验证的完整链路：登录 → 待办列表 → 新增，后端日志确认 `POST /api/auth/login`、`GET /api/todos`、`POST /api/todos` 都返回成功。

其他可选路径：在 Windows 侧装 X server（VcXsrv 之类）并把 `DISPLAY` 指向宿主 IP；升级到 Windows 11；或把 `app/build/linux/x64/release/bundle/` 整个目录拷到有桌面的 Linux 机器上跑（它是自包含的）。

另外，桌面版的 base URL 是 `http://127.0.0.1:8080/api`，所以跑之前要先 `make api-dev` 把后端起到宿主机的 8080。

### Windows 原生 exe

**Flutter 不支持交叉编译**，`flutter build windows` 只能在 Windows 上用 Windows 版 SDK 跑，WSL 里的 Linux SDK 编不出来。所以 Windows 版的源码副本放在 `C:\Users\null\projects\todo-app\app`（从 WSL 的项目同步过去，见下面）。

前置条件（本机已全部就绪）：

| 需要 | 说明 |
|---|---|
| Windows 版 Flutter SDK | `C:\Users\null\flutter`（3.47.5） |
| Visual Studio 生成工具 2022 + C++ 工作负载 | `winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"`，约 4–7 GB |
| **开发者模式** | 必须。项目用了 `shared_preferences`，Flutter 构建时要为插件创建符号链接，普通用户默认没有这个权限 |

**Windows 访问不了 `storage.googleapis.com`**（WSL 能，Windows 不能），所以 Windows 侧跑 Flutter 必须走国内镜像：

```powershell
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
```

构建：

```powershell
cd C:\Users\null\projects\todo-app\app
flutter build windows --release --dart-define=API_BASE_URL=http://127.0.0.1:8081/api
```

产物在 `build\windows\x64\runner\Release\`（`todo_app.exe` + `flutter_windows.dll` + `data\`，共约 27 MB，三个一起拷走才能运行）。

**为什么要指定 `API_BASE_URL`**：Windows 侧的 exe 连不上 WSL 里的 `127.0.0.1:8080`（实测 WSL2 的 localhost 转发对 8081 生效、对 8080 不生效），而 8081 上的 nginx 会把 `/api` 反代到后端。所以 Windows 版指向 8081。这个开关通过 `String.fromEnvironment` 在编译期注入，见 `lib/api/base_url.dart`。

**DPI 说明**：这台机器是 1920×1080 面板 + 150% 缩放（有效桌面 1280×720）。Flutter 的 Windows runner 会按 `Scale(size, dpi/96)` 创建窗口，所以窗口是 1920×1080 物理像素 = 1280×720 逻辑，这是正确的。

> 排查时踩的坑：PowerShell 默认是 **DPI 不感知**的，它读到的所有坐标都被 Windows 虚拟化过（除以 1.5）。用它测量窗口或抓图会得到"窗口只有 1280×720 且内容偏移"的错误结论 —— 实际两者都是对的。在脚本开头调用 `SetProcessDPIAware()` 后再测量才准。

### Android

需要 JDK + Android SDK，本机都没有。移动端访问宿主机后端时，Android 模拟器要用 `10.0.2.2`（`lib/api/base_url.dart` 里已按平台分支处理）。

另外 Flutter SDK 本身需要 `unzip`，缺了会直接报错退出（`Error: Missing "unzip" tool`）。在拿不到 sudo 的环境里可以免 root 装到用户目录：

```bash
mkdir -p ~/.local/bin ~/.local/deb && cd ~/.local/deb
curl -fLO http://archive.ubuntu.com/ubuntu/pool/main/u/unzip/unzip_6.0-28ubuntu4.1_amd64.deb
dpkg-deb -x unzip.deb ~/.local/            # dpkg-deb -x 不需要 root
ln -sf ~/.local/usr/bin/unzip ~/.local/bin/unzip
```

## 已知取舍

这些是有意为之，不是遗漏：

- **token 存在 localStorage / shared_preferences**，任何 XSS 都能读走。要收紧就得上 httpOnly + Secure 的 cookie，代价是额外处理 CSRF——那是另一个量级的工作。
- **没有 token 刷新**。签名密钥轮换的唯一效果是"所有人被登出"，因为是无状态 JWT、没有黑名单。要做真正的轮换需要 refresh token + 版本号校验，那要查库，就失去了无状态的意义。
- **登录没有限流**，可以被暴力破解。
- **`AutoMigrate` 只加表/列/索引**，不删列、不改类型、不搬运数据。表里有了真实数据之后，schema 变更应该换成 golang-migrate 之类的版本化迁移工具。
- **`container_name` 让服务无法水平扩容**（`--scale api=2` 会撞名）。这个项目不需要扩容，换来的是容器名可预测。

## 环境相关的注意事项

**本机的 `proxy.golang.org` 不通**（`sum.golang.org` 同样），所以 Go 依赖走 `goproxy.cn`：

- 宿主机：`go env -w GOPROXY=https://goproxy.cn,direct`
- 容器内：`backend/Dockerfile` 里的 `GOPROXY` ARG 已经设好，别的网络环境可以用 `--build-arg` 覆盖

Docker Hub 直连在这台机器上也不通，靠 daemon 配置的国内 mirror 拉镜像（`/etc/docker/daemon.json`）。

## 关于 `1.txt` / `2.txt`

根目录这两个文件是项目最初的教程式需求文档，保留作为参考。它们的代码**没有被执行验证过**，已知问题包括：后端 `gin.RouterGroup` 传参类型不匹配导致编译失败、路由前缀被拼成 `/api/api/todos`、`views/TodoView.vue` 被引用但从未给出、`App.vue` 没改成 `<router-view>` 导致路由失效，以及 CI 推的镜像在 compose 里无人引用。本项目的实现是这些问题的修正版，不是照抄。

## CI

`.github/workflows/ci.yml` 覆盖的步骤与 `make check` 相同（`go vet` / `go test` / `vue-tsc` / `flutter analyze` / `flutter test`），但**机制不同**：

| | 工具链来自 | 为什么 |
|---|---|---|
| `make check` | 容器（挂载编译） | 保证和发布构建同一套环境 |
| CI | runner 自带的 Go / Node（`setup-go` / `setup-node` 固定版本） | runner 本身就是一次性的、版本已被钉死，每次再构建两个工具链镜像纯属浪费 |

所以**本地绿了不代表 CI 一定绿**（工具链版本可能不同），反过来也一样。两边都跑才算数。

**它尚未在真实 runner 上运行过**——这个目录当前不是 git 仓库，没有 remote，`on: push` 不可能被触发。等 `git init` 并推到 GitHub 之后它才会真正生效。
