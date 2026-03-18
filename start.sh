#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$ROOT_DIR/.shortvdl.pid"
LOG_DIR="$ROOT_DIR/logs"
API_LOG="$LOG_DIR/web-api.log"
UI_LOG="$LOG_DIR/web-ui.log"

API_PORT=8081
UI_PORT=8080

mkdir -p "$LOG_DIR"

kill_port_process() {
    local port=$1
    local pid
    pid=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
        echo "发现端口 ${port} 被占用的进程: ${pid}，正在自动清除..."
        for p in $pid; do
            kill -9 "$p" 2>/dev/null || true
        done
        sleep 1
    fi
}

echo "正在检查和清理占用端口..."
kill_port_process "$API_PORT"
kill_port_process "$UI_PORT"

# 如果之前的 PID 文件存在，清理遗留进程
if [[ -f "$PID_FILE" ]]; then
    while IFS= read -r old_pid; do
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "清理遗留的进程 PID: $old_pid..."
            kill -9 "$old_pid" 2>/dev/null || true
        fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
fi

echo "正在检查和安装后端环境与浏览器内核..."
echo "👉 (如果这是首次运行，后台需要静默下载数百MB的浏览器依赖，请耐心等待 1~3 分钟，切勿关闭...)"
cd "$ROOT_DIR/src/modules/media-crawler"
# 启动 API 服务，确保使用 .venv 环境
if command -v uv >/dev/null 2>&1; then
    uv sync > /dev/null 2>&1
    uv run playwright install > /dev/null 2>&1
    nohup uv run python ../web-api/main.py --port "$API_PORT" > "$API_LOG" 2>&1 &
else
    .venv/bin/python -m pip install -r requirements.txt > /dev/null 2>&1 || true
    .venv/bin/playwright install > /dev/null 2>&1 || true
    nohup .venv/bin/python ../web-api/main.py --port "$API_PORT" > "$API_LOG" 2>&1 &
fi
API_PID=$!
echo "$API_PID" >> "$PID_FILE"

echo "正在启动前端 UI 服务 (Port $UI_PORT)..."
cd "$ROOT_DIR/src/modules/web-ui"
# 确保依赖已安装
if [[ ! -d "node_modules" ]]; then
    echo "正在安装前端依赖..."
    npm install > /dev/null 2>&1
fi
# 启动前端服务，绑定端口
nohup npm run dev -- --port "$UI_PORT" --host > "$UI_LOG" 2>&1 &
UI_PID=$!
echo "$UI_PID" >> "$PID_FILE"

echo ""
echo "🚀 启动成功！"
echo "👉 后端 API 地址: http://localhost:$API_PORT"
echo "👉 前端 UI 地址:  http://localhost:$UI_PORT"
echo "日志已保存至 $LOG_DIR 目录。"
echo "若要停止服务，请运行 ./stop.sh"
