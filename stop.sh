#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$ROOT_DIR/.shortvdl.pid"

API_PORT=8081
UI_PORT=8080

echo "准备停止服务..."

if [[ -f "$PID_FILE" ]]; then
    while IFS= read -r pid; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "正在停止进程 PID: $pid..."
            kill -9 "$pid" 2>/dev/null || true
        fi
    done < "$PID_FILE"
    rm -f "$PID_FILE"
else
    echo "未找到进程记录文件 ($PID_FILE)。"
fi

# 双重保险：强制清理对应端口
kill_port_process() {
    local port=$1
    local pid
    pid=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
        echo "强制清理端口 ${port} 的驻留进程 (${pid})..."
        for p in $pid; do
            kill -9 "$p" 2>/dev/null || true
        done
    fi
}

kill_port_process "$API_PORT"
kill_port_process "$UI_PORT"

echo "✅ 服务已全部停止。"
