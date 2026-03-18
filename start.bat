@echo off
chcp 65001 >nul
setlocal

:: 获取脚本所在的根目录
set "ROOT_DIR=%~dp0"
set "LOG_DIR=%ROOT_DIR%logs"
set "API_LOG=%LOG_DIR%\web-api.log"
set "UI_LOG=%LOG_DIR%\web-ui.log"

set API_PORT=8081
set UI_PORT=8080

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo 正在检查和清理被占用的 API 端口 %API_PORT%...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%API_PORT% ^| findstr LISTENING') do (
    taskkill /F /PID %%a >nul 2>&1
)

echo 正在检查和清理被占用的 UI 端口 %UI_PORT%...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%UI_PORT% ^| findstr LISTENING') do (
    taskkill /F /PID %%a >nul 2>&1
)

echo 正在启动后台 API 服务 (Port %API_PORT%)...
cd /d "%ROOT_DIR%src\modules\media-crawler"
:: 确保依赖已正确通过 uv 安装并在后台隐藏启动
where uv >nul 2>nul
if %ERRORLEVEL% equ 0 goto USE_UV
goto USE_VENV

:USE_UV
echo 正在检查和安装后端环境与浏览器内核...
echo 👉 (如果这是首次运行，后台需要静默下载数百MB的浏览器依赖，请耐心等待 1~3 分钟，切勿关闭...)
call uv sync >nul 2>&1
call uv run playwright install >nul 2>&1
start "SHORT-V-DL Backend API" /B cmd /c uv run python ../web-api/main.py --port %API_PORT% ^> "%API_LOG%" 2^>^&1
goto START_UI

:USE_VENV
echo 正在检查和安装后端环境与浏览器内核 (内置虚拟环境)...
echo 👉 (如果这是首次运行，后台需要静默下载数百MB的浏览器依赖，请耐心等待 1~3 分钟，切勿关闭...)
call .venv\Scripts\python.exe -m pip install -r requirements.txt >nul 2>&1
call .venv\Scripts\playwright.exe install >nul 2>&1
start "SHORT-V-DL Backend API" /B cmd /c .venv\Scripts\python.exe ../web-api/main.py --port %API_PORT% ^> "%API_LOG%" 2^>^&1
goto START_UI

:START_UI
echo 正在启动前端 UI 服务 (Port %UI_PORT%)...
cd /d "%ROOT_DIR%src\modules\web-ui"
:: 检查并自动安装 Node.js 模块
if exist "node_modules\" goto SKIP_NPM
echo 初次运行，正在安装前端依赖 npm install ...
call npm install >nul 2>&1

:SKIP_NPM
start "SHORT-V-DL Frontend UI" /B cmd /c npm run dev -- --port %UI_PORT% --host ^> "%UI_LOG%" 2^>^&1

echo.
echo =========================================
echo 🚀 启动成功！所有的本地服务已挂载在后台。
echo 👉 后端 API 地址: http://localhost:%API_PORT%
echo 👉 前端 UI 控制台:  http://localhost:%UI_PORT%  (请在此页面操作)
echo 日志已保存至 %LOG_DIR% 目录。
echo 若要关闭程序释放端口，请双击运行 stop.bat
echo =========================================
echo.

pause
