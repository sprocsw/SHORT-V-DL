@echo off
chcp 65001 >nul
setlocal

:: 获取脚本所在的根目录
set "ROOT_DIR=%~dp0"

echo =================================================
echo 🚀 欢迎使用 SHORT-V-DL 一键安装程序 (Windows)
echo =================================================
echo.

echo [1/3] 正在进入后端目录安装 Python 环境与依赖...
cd /d "%ROOT_DIR%src\modules\media-crawler"
where uv >nul 2>nul
if %ERRORLEVEL% equ 0 goto USE_UV
goto USE_VENV

:USE_UV
call uv sync
goto INSTALL_PLAYWRIGHT_UV

:USE_VENV
if not exist ".venv\" (
    python -m venv .venv
)
call .venv\Scripts\python.exe -m pip install -r requirements.txt
goto INSTALL_PLAYWRIGHT_VENV

:INSTALL_PLAYWRIGHT_UV
echo.
echo [2/3] 正在静默下载 Playwright 专属无痕浏览器内核 (约200MB，请耐心等待1~3分钟)...
call uv run playwright install
goto INSTALL_NPM

:INSTALL_PLAYWRIGHT_VENV
echo.
echo [2/3] 正在静默下载 Playwright 专属无痕浏览器内核 (约200MB，请耐心等待1~3分钟)...
call .venv\Scripts\playwright.exe install
goto INSTALL_NPM

:INSTALL_NPM
echo.
echo [3/3] 正在进入前端目录安装 Node.js 界面控制台依赖...
cd /d "%ROOT_DIR%src\modules\web-ui"
call npm install

echo.
echo =================================================
echo ✅ 所有环境与依赖均已成功彻底安装！
echo 👉 您现在可以随时无脑双击运行 start.bat 来闪电启动项目了！
echo =================================================
pause
