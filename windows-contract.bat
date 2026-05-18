@echo off
chcp 65001 >nul
REM ========================================
REM Tunnel Mesh - Windows 通用契约脚本
REM 支持导入契约文书、管理隧道
REM ========================================

:menu
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║     Tunnel Mesh  Windows 契约大厅      ║
echo ╠════════════════════════════════════════╣
echo ║                                        ║
echo ║  [1] 导入契约 (粘贴对方的契约文书)     ║
echo ║  [2] 查看契约 (列出所有连接)           ║
echo ║  [3] 启动隧道 (启动所有连接)           ║
echo ║  [4] 停止隧道 (停止所有连接)           ║
echo ║  [5] 删除契约 (删除某个连接)           ║
echo ║  [6] 测试连接 (测试某个连接)           ║
echo ║  [H] 帮助                              ║
echo ║  [Q] 退出                              ║
echo ║                                        ║
echo ╚════════════════════════════════════════╝
echo.

set /p choice="选择: "

if /i "%choice%"=="1" goto import
if /i "%choice%"=="2" goto status
if /i "%choice%"=="3" goto start
if /i "%choice%"=="4" goto stop
if /i "%choice%"=="5" goto remove
if /i "%choice%"=="6" goto test
if /i "%choice%"=="H" goto help
if /i "%choice%"=="Q" goto end

echo 无效选择
timeout /t 2 >nul
goto menu

REM ========================================
REM [1] 导入契约
REM ========================================
:import
cls
echo.
echo ════════════════════════════════════════
echo   导入契约文书
echo ════════════════════════════════════════
echo.
echo 请粘贴对方的契约文书（包含 === 行）
echo 粘贴后按 Ctrl+Z 然后按 Enter
echo.
echo ──────────────────────────────────────
set /p contract_text=
echo ──────────────────────────────────────
echo.

REM 解析契约文书
echo %contract_text% | findstr "TYPE=" >nul
if %errorlevel% neq 0 (
    echo 错误：无效的契约文书
    pause
    goto menu
)

REM 提取字段
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "TYPE="') do set CTYPE=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "SERVANT_NAME="') do set SNAME=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "SERVANT_IP="') do set SIP=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "SERVANT_PORT="') do set SPORT=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "SERVANT_USER="') do set SUSER=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "TUNNEL_PORT="') do set TPORT=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "RELAY_IP="') do set RIP=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "RELAY_USER="') do set RUSER=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "PUBKEY="') do set PKEY=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "TUNNEL_CMD="') do set TCMD=%%a
for /f "tokens=2 delims==" %%a in ('echo %contract_text% ^| findstr "MAINTAINER="') do set MAINTAINER=%%a

echo 契约类型: %CTYPE%
echo 对方名称: %SNAME%

if "%SNAME%"=="" (
    echo 错误：无法解析契约
    pause
    goto menu
)

REM 添加公钥
if not "%PKEY%"=="" (
    if not exist "%USERPROFILE%\.ssh" mkdir "%USERPROFILE%\.ssh"
    echo %PKEY% >> "%USERPROFILE%\.ssh\authorized_keys"
    echo ✓ 公钥已添加
)

REM 添加SSH config
echo. >> "%USERPROFILE%\.ssh\config"

if "%CTYPE%"=="direct" (
    echo # Tunnel Mesh - %SNAME% >> "%USERPROFILE%\.ssh\config"
    echo Host %SNAME% >> "%USERPROFILE%\.ssh\config"
    echo     HostName %SIP% >> "%USERPROFILE%\.ssh\config"
    echo     Port %SPORT% >> "%USERPROFILE%\.ssh\config"
    echo     User %SUSER% >> "%USERPROFILE%\.ssh\config"
    echo     StrictHostKeyChecking no >> "%USERPROFILE%\.ssh\config"
    echo ✓ SSH config 已添加（直连）
)

if "%CTYPE%"=="reverse" (
    echo # Tunnel Mesh - %SNAME% >> "%USERPROFILE%\.ssh\config"
    echo Host %SNAME% >> "%USERPROFILE%\.ssh\config"
    echo     HostName %RIP% >> "%USERPROFILE%\.ssh\config"
    echo     Port %TPORT% >> "%USERPROFILE%\.ssh\config"
    echo     User %SUSER% >> "%USERPROFILE%\.ssh\config"
    echo     StrictHostKeyChecking no >> "%USERPROFILE%\.ssh\config"
    echo ✓ SSH config 已添加（反向隧道）

    REM 如果有隧道命令，创建Windows计划任务
    if not "%TCMD%"=="" if "%MAINTAINER%"=="bridge" (
        echo.
        echo 检测到需要维持隧道，创建开机自启任务...

        set script_path=C:\tunnel-mesh\scripts\tunnel-%SNAME%.ps1
        if not exist "C:\tunnel-mesh\scripts" mkdir "C:\tunnel-mesh\scripts"

        (
            echo # Tunnel Mesh - %SNAME%
            echo # %TCMD%
            echo while ($true^) {
            echo     Write-Host "$(Get-Date^) 隧道: %SNAME%"
            echo     %TCMD%
            echo     Write-Host "$(Get-Date^) 断开，10秒后重连..."
            echo     Start-Sleep 10
            echo }
        ) > "!script_path!"

        powershell -Command "Unregister-ScheduledTask -TaskName 'Tunnel-%SNAME%' -Confirm:$false -ErrorAction SilentlyContinue; $a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-WindowStyle Hidden -File \"!script_path!\"'; $t=New-ScheduledTaskTrigger -AtStartup; $s=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1); Register-ScheduledTask -TaskName 'Tunnel-%SNAME%' -Action $a -Trigger $t -Settings $s -RunLevel Highest -Force; Start-ScheduledTask -TaskName 'Tunnel-%SNAME%'"

        echo ✓ 隧道已创建并启动
        echo   任务名: Tunnel-%SNAME%
        echo   开机自启: 已配置
    )
)

echo.
echo ════════════════════════════════════════
echo   导入完成！
echo ════════════════════════════════════════
echo.
echo 验证: ssh %SNAME% hostname
echo.
pause
goto menu

REM ========================================
REM [2] 查看契约
REM ========================================
:status
cls
echo.
echo ════════════════════════════════════════
echo   当前契约
echo ════════════════════════════════════════
echo.
echo SSH config 中的连接:
findstr /R "^Host [a-z]" "%USERPROFILE%\.ssh\config" 2>nul
echo.
echo 隧道任务:
powershell -Command "Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'} | Select-Object TaskName,State | Format-Table -AutoSize"
echo.
pause
goto menu

REM ========================================
REM [3] 启动隧道
REM ========================================
:start
cls
powershell -Command "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'}; foreach($t in $tasks){Start-ScheduledTask -TaskName $t.TaskName; Write-Host \"  ✓ $($t.TaskName)\"}"
echo.
echo 全部已启动
pause
goto menu

REM ========================================
REM [4] 停止隧道
REM ========================================
:stop
cls
powershell -Command "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'}; foreach($t in $tasks){Stop-ScheduledTask -TaskName $t.TaskName; Write-Host \"  ✓ $($t.TaskName)\"}"
echo.
echo 全部已停止
pause
goto menu

REM ========================================
REM [5] 删除契约
REM ========================================
:remove
cls
echo.
echo ════════════════════════════════════════
echo   删除契约
echo ════════════════════════════════════════
echo.
echo 现有隧道:
powershell -Command "Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'} | Select-Object TaskName,State"
echo.
set /p del_name="输入要删除的名称（如 node3）: "
if "%del_name%"=="" goto menu

powershell -Command "Unregister-ScheduledTask -TaskName 'Tunnel-%del_name%' -Confirm:$false -ErrorAction SilentlyContinue"
del "C:\tunnel-mesh\scripts\tunnel-%del_name%.ps1" 2>nul
echo ✓ %del_name% 已删除
pause
goto menu

REM ========================================
REM [6] 测试连接
REM ========================================
:test
cls
echo.
set /p test_host="输入要测试的主机名: "
ssh -o ConnectTimeout=5 %test_host% "echo ✓ 连通" 2>nul && echo ✓ 连通 || echo ✗ 不可达
echo.
pause
goto menu

REM ========================================
REM [H] 帮助
REM ========================================
:help
cls
echo.
echo ════════════════════════════════════════
echo   契约法典
echo ════════════════════════════════════════
echo.
echo 【使用流程】
echo.
echo   1. 在要连的服务器上导出契约:
echo      bash linux-contract.sh export
echo.
echo   2. 把导出的「契约文书」复制过来
echo.
echo   3. 在这里选 [1] 导入契约，粘贴文书
echo.
echo   4. 自动配置SSH + 如需隧道则创建自启任务
echo.
echo 【文件位置】
echo   隧道脚本: C:\tunnel-mesh\scripts\
echo   SSH配置:  %USERPROFILE%\.ssh\config
echo.
pause
goto menu

:end
exit /b 0
