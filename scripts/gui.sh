#!/usr/bin/env bash
#
# 在这台机器上把 Flutter Linux 桌面版显示出来。
#
#   ./scripts/gui.sh          启动，然后用浏览器打开 http://localhost:6080/vnc.html
#   ./scripts/gui.sh stop     全部停掉
#
# ---------------------------------------------------------------------------
# 为什么需要这么绕
# ---------------------------------------------------------------------------
# 两个环境问题叠加，导致这台机器上**任何** GUI 程序都看不见：
#
#   1. WSL 全局设了 WAYLAND_DISPLAY=wayland-0。GTK 只要看到这个变量就
#      优先选 Wayland 而**忽略 DISPLAY**，于是所有 GUI 程序都被路由到 WSLg。
#
#   2. 宿主是 Windows 10 build 19045，而 WSLg 是 Windows 11 的功能。
#      在 Win10 上 WSLg 退化成 [WARN:COPY MODE]：任务栏有条目，但窗口
#      打不开、看不到任何内容。
#
# 拿 glxgears（和 Flutter 毫无关系的最简 GL 程序）对照，表现**完全一致**，
# 所以这不是本项目代码的问题，改代码也没用。
#
# 这个脚本的做法是绕开 WSLg 整套东西：Xvfb 提供虚拟屏幕，x11vnc 把画面
# 导出来，websockify + noVNC 让浏览器直接看。**不需要在 Windows 上装任何
# 东西，也不需要管理员权限。**
#
# 注意 x11vnc 也必须清掉 WAYLAND_DISPLAY：它看到这个变量会以为整个会话是
# Wayland，直接拒绝启动，哪怕你已经用 -display 明确指定了 X display。
#
# ---------------------------------------------------------------------------
# 安全说明
# ---------------------------------------------------------------------------
# x11vnc 和 websockify 都只绑 127.0.0.1，外网碰不到。但 VNC 本身没设密码，
# 所以**本机上任何进程都能连**。演示用够了，别在有其他人的机器上这么跑。
# 用完执行 ./scripts/gui.sh stop。
#
# 依赖（都装在系统里，无需 pip/npm）：
#   xvfb x11vnc novnc websockify imagemagick xdotool

set -euo pipefail

APP_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/app/build/linux/x64/release/bundle/todo_app"
DISPLAY_NUM=":99"
VNC_PORT=5900
WEB_PORT=6080

# 这几个进程都不该看到 WAYLAND_DISPLAY，见上面的说明。
clean_env() {
  env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11 "$@"
}

running() { pgrep -x "$1" >/dev/null 2>&1; }

stop_all() {
  for p in todo_app x11vnc Xvfb; do
    running "$p" && { pkill -x "$p"; echo "  已停止 $p"; }
  done
  # websockify 是 python 脚本，进程名不是它自己，只能按命令行匹配。
  # 用 [w] 防止匹配到 grep/本脚本自己。
  pkill -f '[w]ebsockify --web' 2>/dev/null && echo "  已停止 websockify" || true
}

case "${1:-start}" in
  stop)
    echo "停止 GUI 相关进程..."
    stop_all
    exit 0
    ;;
  start) ;;
  *)
    echo "用法: $0 [start|stop]" >&2
    exit 1
    ;;
esac

if [[ ! -x "$APP_BIN" ]]; then
  echo "找不到可执行文件：$APP_BIN" >&2
  echo "先跑：make flutter-linux" >&2
  exit 1
fi

echo "清理可能残留的旧进程..."
stop_all
sleep 2

echo "1/4 启动虚拟屏幕 Xvfb $DISPLAY_NUM (1280x720x24)"
nohup Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
sleep 3

echo "2/4 启动应用（强制 X11，清掉 WAYLAND_DISPLAY）"
clean_env DISPLAY="$DISPLAY_NUM" GDK_BACKEND=x11 \
  XDG_RUNTIME_DIR="/run/user/$(id -u)" \
  nohup "$APP_BIN" >/tmp/todo-gui.log 2>&1 &
sleep 12

if ! running todo_app; then
  echo "应用没能启动，日志：" >&2
  cat /tmp/todo-gui.log >&2
  exit 1
fi

# 确认真的建出了窗口——只看进程存活是不够的，之前就是被这个骗过。
if DISPLAY="$DISPLAY_NUM" xwininfo -root -tree 2>/dev/null | grep -q '1280x720'; then
  echo "    窗口已创建 (1280x720)"
else
  echo "    警告：进程活着但没建出窗口，看看 /tmp/todo-gui.log"
fi

echo "3/4 启动 x11vnc（只绑回环）"
clean_env nohup x11vnc -display "$DISPLAY_NUM" -rfbport "$VNC_PORT" \
  -localhost -forever -shared -nopw -quiet >/tmp/x11vnc.log 2>&1 &
sleep 4

echo "4/4 启动 noVNC 网页端（只绑回环）"
nohup websockify --web=/usr/share/novnc "127.0.0.1:$WEB_PORT" "localhost:$VNC_PORT" \
  >/tmp/websockify.log 2>&1 &
sleep 4

echo
echo "就绪。用浏览器打开："
echo
echo "    http://localhost:$WEB_PORT/vnc.html"
echo
echo "（页面加载后如果停在「连接中」，点一下左侧边栏的连接按钮）"
echo "停止：./scripts/gui.sh stop"
