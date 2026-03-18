@echo off
chcp 65001 >nul
setlocal

set API_PORT=8081
set UI_PORT=8080

echo 正在准备强制停止所有属于 SHORT-V-DL 的后台服务...

echo 清理端口 %API_PORT% 驻留的后台 API 服务...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%API_PORT% ^| findstr LISTENING') do (
    taskkill /F /PID %%a >nul 2>&1
    echo ✅ 已清理进程 PID: %%a
)

echo 清理端口 %UI_PORT% 驻留的后台 UI 服务...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :%UI_PORT% ^| findstr LISTENING') do (
    taskkill /F /PID %%a >nul 2>&1
    echo ✅ 已清理进程 PID: %%a
)

echo.
echo ✅ 服务已全部彻底停止，端口释放完毕！
pause
