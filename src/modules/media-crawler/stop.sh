#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$ROOT_DIR/.mediacrawler.pid"
PORT_FILE="$ROOT_DIR/.mediacrawler.port"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No pid file found. Nothing to stop."
  exit 0
fi

pid="$(cat "$PID_FILE" 2>/dev/null || true)"
if [[ -z "$pid" ]]; then
  echo "Pid file empty. Cleaning up."
  rm -f "$PID_FILE" "$PORT_FILE"
  exit 0
fi

if ! kill -0 "$pid" 2>/dev/null; then
  echo "Process not running (pid $pid). Cleaning up."
  rm -f "$PID_FILE" "$PORT_FILE"
  exit 0
fi

echo "Stopping MediaCrawler (pid $pid)..."
kill "$pid" 2>/dev/null || true

for _ in {1..20}; do
  if kill -0 "$pid" 2>/dev/null; then
    sleep 0.5
  else
    break
  fi
done

if kill -0 "$pid" 2>/dev/null; then
  echo "Process did not stop in time, forcing..."
  kill -9 "$pid" 2>/dev/null || true
fi

rm -f "$PID_FILE" "$PORT_FILE"
echo "Stopped."
