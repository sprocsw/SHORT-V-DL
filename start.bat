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

echo 🚀 正在闪电拉起后台 API 服务 (Port %API_PORT%)...
cd /d "%ROOT_DIR%src\modules\media-crawler"
where uv >nul 2>nul
if %ERRORLEVEL% equ 0 goto USE_UV
goto USE_VENV

:USE_UV
start "SHORT-V-DL Backend API" /B cmd /c uv run python ../web-api/main.py --port %API_PORT% ^> "%API_LOG%" 2^>^&1
goto START_UI

:USE_VENV
start "SHORT-V-DL Backend API" /B cmd /c .venv\Scripts\python.exe ../web-api/main.py --port %API_PORT% ^> "%API_LOG%" 2^>^&1
goto START_UI

:START_UI
echo 🚀 正在闪电拉起前端 UI 服务 (Port %UI_PORT%)...
cd /d "%ROOT_DIR%src\modules\web-ui"
start "SHORT-V-DL Frontend UI" /B cmd /c npm run dev -- --port %UI_PORT% --host ^> "%UI_LOG%" 2^>^&1

echo.
echo =========================================
echo ✅ 启动成功！程序已稳定挂载至后台。
echo 👉 请直接在浏览器打开: http://localhost:%UI_PORT
echo =========================================
echo.

pause
