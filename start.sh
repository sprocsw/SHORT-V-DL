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

if [[ -f "$PID_FILE" ]]; then
    while IFS= read -r old_pid; do
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "清理遗留的进程 PID: ${old_pid}..."
            kill -9 "$old_pid" 2>/dev/null || true
        fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
fi

cd "$ROOT_DIR/src/modules/media-crawler"
echo "🚀 正在闪电拉起后台 API 服务 (Port $API_PORT)..."
if command -v uv >/dev/null 2>&1; then
    nohup uv run python ../web-api/main.py --port "$API_PORT" > "$API_LOG" 2>&1 &
else
    nohup .venv/bin/python ../web-api/main.py --port "$API_PORT" > "$API_LOG" 2>&1 &
fi
API_PID=$!
echo "$API_PID" >> "$PID_FILE"

cd "$ROOT_DIR/src/modules/web-ui"
echo "🚀 正在闪电拉起前端 UI 服务 (Port $UI_PORT)..."
nohup npm run dev -- --port "$UI_PORT" --host > "$UI_LOG" 2>&1 &
UI_PID=$!
echo "$UI_PID" >> "$PID_FILE"

echo ""
echo "========================================="
echo "✅ 启动成功！程序已稳定挂载至后台。"
echo "👉 请直接在浏览器打开: http://localhost:$UI_PORT"
echo "========================================="
echo "若要停止服务，请运行 ./stop.sh"
