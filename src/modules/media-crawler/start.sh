#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$ROOT_DIR/.mediacrawler.pid"
PORT_FILE="$ROOT_DIR/.mediacrawler.port"
LOG_DIR="$ROOT_DIR/logs"
LOG_FILE="$LOG_DIR/webui.log"
DEFAULT_PORT="${PORT:-8080}"

is_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

is_port_in_use() {
  local port="$1"
  lsof -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

find_free_port() {
  local port="$1"
  while is_port_in_use "$port"; do
    port=$((port + 1))
  done
  echo "$port"
}

if is_running; then
  pid="$(cat "$PID_FILE")"
  echo "MediaCrawler already running (pid $pid)."
  if [[ -f "$PORT_FILE" ]]; then
    echo "Port: $(cat "$PORT_FILE")"
  fi
  exit 0
fi

rm -f "$PID_FILE" "$PORT_FILE"
mkdir -p "$LOG_DIR"

port="$(find_free_port "$DEFAULT_PORT")"
if [[ "$port" != "$DEFAULT_PORT" ]]; then
  echo "Port $DEFAULT_PORT in use, using $port."
fi

cd "$ROOT_DIR"
if command -v uv >/dev/null 2>&1; then
  CMD=(uv run uvicorn api.main:app --port "$port" --reload)
elif command -v python >/dev/null 2>&1; then
  CMD=(python -m uvicorn api.main:app --port "$port" --reload)
else
  echo "Neither uv nor python found on PATH."
  exit 1
fi

nohup "${CMD[@]}" > "$LOG_FILE" 2>&1 &
pid=$!
echo "$pid" > "$PID_FILE"
echo "$port" > "$PORT_FILE"

echo "MediaCrawler started (pid $pid) on port $port."
echo "Logs: $LOG_FILE"
