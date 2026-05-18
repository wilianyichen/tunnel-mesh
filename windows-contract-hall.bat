@echo off
chcp 65001 >nul
REM ========================================
REM Tunnel Mesh 契约大厅 (Windows)
REM 管理所有主仆契约
REM ========================================

:menu
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║         Tunnel Mesh  契约大厅          ║
echo ╠════════════════════════════════════════╣
echo ║                                        ║
echo ║  [1] 缔结契约    (建立新的主仆关系)    ║
echo ║  [2] 审视契约    (查看所有契约状态)    ║
echo ║  [3] 契约之仪    (启动所有隧道)        ║
echo ║  [4] 解除契约    (停止所有隧道)        ║
echo ║  [5] 废契        (删除某条契约)        ║
echo ║  [6] 密钥保管    (管理SSH密钥)         ║
echo ║  [7] 测试连通    (测试契约连通性)      ║
echo ║  [8] 生成配文    (导出SSH config给别人)║
echo ║  [9] 安装自启    (配置开机自启动)      ║
echo ║  [H] 契约法典    (帮助)                ║
echo ║  [Q] 退却                              ║
echo ║                                        ║
echo ╚════════════════════════════════════════╝
echo.

set /p choice="请选择: "

if /i "%choice%"=="1" goto contract_new
if /i "%choice%"=="2" goto contract_status
if /i "%choice%"=="3" goto contract_start
if /i "%choice%"=="4" goto contract_stop
if /i "%choice%"=="5" goto contract_remove
if /i "%choice%"=="6" goto keys_menu
if /i "%choice%"=="7" goto test_menu
if /i "%choice%"=="8" goto export_config
if /i "%choice%"=="9" goto install_autostart
if /i "%choice%"=="H" goto help
if /i "%choice%"=="Q" goto end

echo 无效选择
timeout /t 2 >nul
goto menu

REM ========================================
REM [1] 缔结新契约
REM ========================================
:contract_new
cls
echo.
echo ════════════════════════════════════════
echo   缔结新契约
echo ════════════════════════════════════════
echo.
echo 触达方式：
echo   [1] 正向 - 你能直接连到仆
echo   [2] 反向 - 仆不能直连你，需建立反向隧道
echo.
set /p reach="选择: "

if "%reach%"=="2" goto contract_reverse
if "%reach%"=="1" goto contract_forward

echo 无效选择
pause
goto menu

:contract_forward
cls
echo.
echo ════════════════════════════════════════
echo   正向契约 - 直接SSH连接
echo ════════════════════════════════════════
echo.
set /p srv_name="仆人名称: "
set /p srv_ip="IP:端口 [如 192.168.1.100:22]: "
set /p srv_user="用户 [root]: "
if "%srv_user%"=="" set srv_user=root

echo.
echo 密钥：
echo   [1] 生成新密钥
echo   [2] 使用已有密钥
set /p key_choice="选择: "

if "%key_choice%"=="1" (
    ssh-keygen -t ed25519 -f "%USERPROFILE%\.ssh\id_%srv_name%" -C "%srv_name%@tunnel" -N ""
)

REM 添加SSH config
for /f "tokens=1,2 delims=:" %%a in ("%srv_ip%") do set sip=%%a& set sport=%%b
if "%sport%"=="" set sport=22
echo. >> "%USERPROFILE%\.ssh\config"
echo # Tunnel Mesh - %srv_name% >> "%USERPROFILE%\.ssh\config"
echo Host %srv_name% >> "%USERPROFILE%\.ssh\config"
echo     HostName %sip% >> "%USERPROFILE%\.ssh\config"
echo     Port %sport% >> "%USERPROFILE%\.ssh\config"
echo     User %srv_user% >> "%USERPROFILE%\.ssh\config"
echo     StrictHostKeyChecking no >> "%USERPROFILE%\.ssh\config"

echo.
echo ✓ 契约已缔结！
echo   ssh %srv_name%
pause
goto menu

:contract_reverse
cls
echo.
echo ════════════════════════════════════════
echo   反向契约 - 通过反向隧道连接
echo ════════════════════════════════════════
echo.
echo 反向隧道需要 Windows 维持常驻进程。
echo 对方不能直连你，但你能连对方 + 中间服务器。
echo.

set /p srv_name="仆人名称: "
set /p srv_ip="仆人 IP [如 10.16.82.202]: "
set /p srv_port="仆人 SSH端口 [22]: "
if "%srv_port%"=="" set srv_port=22
set /p srv_user="仆人用户名 [root]: "
if "%srv_user%"=="" set srv_user=root

echo.
echo 中间服务器（你和仆都能连的服务器）：
set /p relay_ip="  中间服务器 IP: "
set /p relay_user="  中间服务器用户 [root]: "
if "%relay_user%"=="" set relay_user=root

echo.
echo 分配给此隧道的端口：
echo   当前已用端口请查看 [2]审视契约
set /p tunnel_port="  端口 [2201]: "
if "%tunnel_port%"=="" set tunnel_port=2201

REM 生成隧道脚本
set script_path=C:\tunnel-mesh\scripts\tunnel-%srv_name%.ps1

(
echo # Tunnel Mesh - %srv_name%
echo # 反向隧道: %relay_ip%:%tunnel_port% → %srv_ip%:%srv_port%
echo while ($true^) {
echo     $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
echo     Write-Host "$ts [隧道] %relay_ip%:%tunnel_port% → %srv_ip%:%srv_port%"
echo     ssh -R %tunnel_port%:%srv_ip%:%srv_port% -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes -N %relay_user%@%relay_ip%
echo     Start-Sleep 10
echo }
) > "%script_path%"

REM 创建自启动任务
powershell -Command "Unregister-ScheduledTask -TaskName 'Tunnel-%srv_name%' -Confirm:$false -ErrorAction SilentlyContinue; $a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-File \"%script_path%\"'; $t=New-ScheduledTaskTrigger -AtStartup; $s=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1); Register-ScheduledTask -TaskName 'Tunnel-%srv_name%' -Action $a -Trigger $t -Settings $s -RunLevel Highest -Force"

REM 启动
powershell -Command "Start-ScheduledTask -TaskName 'Tunnel-%srv_name%'"

echo.
echo ✓ 反向契约已缔结！
echo   隧道端口: %tunnel_port%
echo   自启动: 已配置
echo.
echo ──────────────────────────────────────
echo  将此配置添加到 %relay_ip% 的 ~/.ssh/config:
echo ──────────────────────────────────────
echo.
echo Host %srv_name%
echo     HostName localhost
echo     Port %tunnel_port%
echo     User %srv_user%
echo     StrictHostKeyChecking no
echo.
pause
goto menu

REM ========================================
REM [2] 审视契约
REM ========================================
:contract_status
cls
echo.
echo ════════════════════════════════════════
echo   审视契约
echo ════════════════════════════════════════
echo.
echo 自启动任务:
powershell -Command "Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'} | Select-Object TaskName,State | Format-Table -AutoSize"
echo.
echo SSH config 中的契约:
findstr /R "^Host [a-z]" "%USERPROFILE%\.ssh\config" 2>nul
echo.
pause
goto menu

REM ========================================
REM [3] 契约之仪 - 启动所有隧道
REM ========================================
:contract_start
cls
echo.
echo ════════════════════════════════════════
echo   契约之仪 - 启动所有隧道
echo ════════════════════════════════════════
echo.
powershell -Command "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'}; foreach($t in $tasks){Start-ScheduledTask -TaskName $t.TaskName; Write-Host \"  ✓ $($t.TaskName)\"}"
echo.
echo 全部已启动
pause
goto menu

REM ========================================
REM [4] 解除契约 - 停止所有隧道
REM ========================================
:contract_stop
cls
echo.
echo ════════════════════════════════════════
echo   解除契约 - 停止所有隧道
echo ════════════════════════════════════════
echo.
powershell -Command "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'}; foreach($t in $tasks){Stop-ScheduledTask -TaskName $t.TaskName; Write-Host \"  ✓ $($t.TaskName)\"}"
echo.
echo 全部已停止
pause
goto menu

REM ========================================
REM [5] 废契
REM ========================================
:contract_remove
cls
echo.
echo ════════════════════════════════════════
echo   废契
echo ════════════════════════════════════════
echo.
echo 现有契约:
powershell -Command "Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'} | Select-Object TaskName,State"
echo.
set /p remove_name="输入要删除的契约名称（如 node3）: "
if "%remove_name%"=="" goto menu

powershell -Command "Unregister-ScheduledTask -TaskName 'Tunnel-%remove_name%' -Confirm:$false -ErrorAction SilentlyContinue"
del "C:\tunnel-mesh\scripts\tunnel-%remove_name%.ps1" 2>nul

echo.
echo ✓ 契约 %remove_name% 已废除
pause
goto menu

REM ========================================
REM [6] 密钥保管
REM ========================================
:keys_menu
cls
echo.
echo ════════════════════════════════════════
echo   密钥保管
echo ════════════════════════════════════════
echo.
echo   [1] 列出所有密钥
echo   [2] 生成新密钥
echo   [3] 显示公钥
echo   [B] 返回
echo.
set /p key_act="选择: "

if "%key_act%"=="1" (
    echo.
    dir "%USERPROFILE%\.ssh\id_*" 2>nul
    echo.
    pause
    goto keys_menu
)
if "%key_act%"=="2" (
    set /p key_name="密钥名称: "
    ssh-keygen -t ed25519 -f "%USERPROFILE%\.ssh\id_%key_name%" -N ""
    echo ✓ 已生成
    pause
    goto keys_menu
)
if "%key_act%"=="3" (
    set /p key_show="密钥名称: "
    type "%USERPROFILE%\.ssh\id_%key_show%.pub" 2>nul || echo 未找到
    pause
    goto keys_menu
)
goto menu

REM ========================================
REM [7] 测试连通
REM ========================================
:test_menu
cls
echo.
echo ════════════════════════════════════════
echo   测试连通
echo ════════════════════════════════════════
echo.
set /p test_host="输入主机名: "
ssh -o ConnectTimeout=5 %test_host% "echo ✓ 连通" 2>nul
if %errorlevel%==0 (
    echo ✓ %test_host% 连通
) else (
    echo ✗ %test_host% 不可达
)
echo.
pause
goto menu

REM ========================================
REM [8] 生成配文
REM ========================================
:export_config
cls
echo.
echo ════════════════════════════════════════
echo   生成配文（导出SSH config给对方）
echo ════════════════════════════════════════
echo.
echo 本机IP: 
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr "IPv4"') do set MY_IP=%%a
echo   %MY_IP: =%
echo.
echo ──────────────────────────────────────
echo  将以下内容复制给对方，让对方运行:
echo  bash linux-setup-ssh-config.sh
echo ──────────────────────────────────────
echo.
echo 或直接告诉对方在 ~/.ssh/config 添加对应配置。
echo.
pause
goto menu

REM ========================================
REM [9] 安装自启
REM ========================================
:install_autostart
cls
echo.
echo ════════════════════════════════════════
echo   安装自启
echo ════════════════════════════════════════
echo.
echo 启动完整安装向导...
echo.
powershell -ExecutionPolicy Bypass -File "C:\tunnel-mesh\windows-auto-setup.ps1"
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
echo 【契约类型】
echo.
echo   正向契约 - 你直接能连到对方
echo   → 只需SSH密钥，自动配置
echo.
echo   反向契约 - 你不能直连对方
echo   → 需反向隧道 + Windows常驻进程
echo   → 自动创建开机自启动任务
echo.
echo 【契约流程】
echo.
echo   1. [1]缔结契约
echo   2. 选择正/反向
echo   3. 输入对方信息
echo   4. 将生成的SSH config复制给对方
echo   5. [3]契约之仪 启动
echo.
echo 【开机自启】
echo   所有反向隧道自动配置为Windows计划任务
echo   重启后自动恢复，断开后自动重连
echo.
echo 【文件位置】
echo   隧道脚本: C:\tunnel-mesh\scripts\
echo   SSH配置:  %USERPROFILE%\.ssh\config
echo.
pause
goto menu

:end
exit /b 0
