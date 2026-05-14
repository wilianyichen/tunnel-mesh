@echo off
chcp 65001 >nul
REM ========================================
REM Tunnel Mesh 一键安装脚本 (Windows)
REM 双击运行即可
REM ========================================

echo.
echo ========================================
echo    Tunnel Mesh 一键安装
echo ========================================
echo.

REM 检查管理员权限
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 请右键选择"以管理员身份运行"
    pause
    exit /b 1
)

echo [1/4] 检查 SSH...
where ssh >nul 2>&1
if %errorlevel% neq 0 (
    echo [提示] 正在安装 OpenSSH...
    powershell -Command "Add-WindowsCapability -Online -Name OpenSSH.Client"
)
echo       √ SSH 已就绪

echo.
echo [2/4] 创建目录...
if not exist "C:\tunnel-mesh" mkdir "C:\tunnel-mesh"
if not exist "C:\tunnel-mesh\config" mkdir "C:\tunnel-mesh\config"
if not exist "C:\tunnel-mesh\logs" mkdir "C:\tunnel-mesh\logs"
echo       √ 目录已创建

echo.
echo [3/4] 下载脚本...
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wilianyichen/tunnel-mesh/main/scripts/windows-tunnel-batch.py' -OutFile 'C:\tunnel-mesh\tunnel-batch.py'"
echo       √ 脚本已下载

echo.
echo [4/4] 创建快捷方式...
powershell -Command "$WshShell = New-Object -ComObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('C:\Users\Public\Desktop\Tunnel Mesh.lnk'); $Shortcut.TargetPath = 'powershell.exe'; $Shortcut.Arguments = '-ExecutionPolicy Bypass -File \"C:\tunnel-mesh\start-menu.ps1\"'; $Shortcut.Save()"
echo       √ 快捷方式已创建

echo.
echo ========================================
echo    安装完成！
echo ========================================
echo.
echo 桌面上已创建 "Tunnel Mesh" 快捷方式
echo 双击即可打开管理界面
echo.
pause
