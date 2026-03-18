#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================="
echo "🚀 欢迎使用 SHORT-V-DL 一键安装程序 (Mac/Linux)"
echo "================================================="

echo ""
echo "[1/3] 正在进入后端目录安装 Python 环境与依赖..."
cd "$ROOT_DIR/src/modules/media-crawler"
if command -v uv >/dev/null 2>&1; then
    uv sync
else
    if [[ ! -d ".venv" ]]; then
        python3 -m venv .venv
    fi
    .venv/bin/python -m pip install -r requirements.txt
fi

echo ""
echo "[2/3] 正在静默下载 Playwright 专属无痕浏览器内核 (约200MB，请耐心等待 1~3 分钟)..."
if command -v uv >/dev/null 2>&1; then
    uv run playwright install
else
    .venv/bin/playwright install
fi

echo ""
echo "[3/3] 正在进入前端目录安装 Node.js 界面控制台依赖..."
cd "$ROOT_DIR/src/modules/web-ui"
npm install

echo ""
echo "================================================="
echo "✅ 所有环境与依赖均已成功彻底安装！"
echo "👉 您现在可以随时无脑执行 ./start.sh 来闪电启动项目了！"
echo "================================================="
