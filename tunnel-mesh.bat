@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
REM ========================================
REM Tunnel Mesh Windows 契约大厅
REM ========================================

REM 管理员权限检查（自动申请提权）
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 正在申请管理员权限...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:menu
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║     Tunnel Mesh  契约大厅 (Windows)    ║
echo ╠════════════════════════════════════════╣
echo ║                                        ║
echo ║  [1] 导入隧道命令 (粘贴 ssh -R ... )   ║
echo ║  [2] 导出身份卡（给 Linux 用）          ║
echo ║  [3] 查看隧道状态                      ║
echo ║  [4] 启动所有隧道                      ║
echo ║  [5] 停止所有隧道                      ║
echo ║  [6] 删除隧道                          ║
echo ║  [7] 测试连接                          ║
echo ║  [Q] 退出                              ║
echo ║                                        ║
echo ╚════════════════════════════════════════╝
echo.

set /p choice="选择: "
if /i "%choice%"=="1" goto import
if /i "%choice%"=="2" goto export
if /i "%choice%"=="3" goto status
if /i "%choice%"=="4" goto start
if /i "%choice%"=="5" goto stop
if /i "%choice%"=="6" goto remove
if /i "%choice%"=="7" goto test
if /i "%choice%"=="Q" goto end
echo 无效选择 & timeout /t 2 >nul & goto menu

REM ========================================
REM [2] 导出身份卡
REM ========================================
:export
cls
echo.
echo ════════════════════════════════════════
echo   导出身份卡
echo ════════════════════════════════════════
echo.

REM 检查/生成密钥
set KEY_FILE=%USERPROFILE%\.ssh\id_ed25519
if not exist "%KEY_FILE%" (
    echo 生成 SSH 密钥...
    ssh-keygen -t ed25519 -f "%KEY_FILE%" -N "" -C "windows@tunnel"
    echo √ 已生成
)
echo.

REM 获取本机 IP
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr "IPv4"') do set MY_IP=%%a
set MY_IP=%MY_IP: =%

echo ──────────────────────────────────────
echo   身份卡（复制到 Linux 服务器上）
echo   在 Linux 上运行: bash tunnel-mesh.sh import
echo   粘贴此身份卡即可部署 Windows 的公钥
echo ──────────────────────────────────────
echo.
echo ===IDENTITY===
echo NAME=%COMPUTERNAME%
echo IP=%MY_IP%
echo PORT=22
echo USER=%USERNAME%
echo PUBKEY=
type "%KEY_FILE%.pub"
echo ===END===
echo.
echo ──────────────────────────────────────
echo.
echo 在阿里云和 node3 上各导入一次这个身份卡，
echo 就可以让 Windows 免密 SSH 连接它们。
echo.
pause
goto menu

REM ========================================
REM [1] 导入隧道命令
REM ========================================
:import
cls
echo.
echo ════════════════════════════════════════
echo   导入隧道命令
echo ════════════════════════════════════════
echo.
echo 粘贴 Linux 生成的 ssh -R 命令:
echo （从对方服务器复制的隧道命令）
echo.
echo ──────────────────────────────────────
set /p TCMD=
echo ──────────────────────────────────────

REM 验证是 ssh -R 命令
echo !TCMD! | findstr /C:"ssh" | findstr /C:"-R" >nul
if !errorlevel! neq 0 (
    echo 错误：请输入完整的 ssh -R 命令
    pause
    goto menu
)

REM ── 密钥检查 ──
echo.
echo 检查 SSH 密钥...
set KEY_FILE=%USERPROFILE%\.ssh\id_ed25519
if not exist "%KEY_FILE%" (
    echo 未找到密钥，正在生成...
    ssh-keygen -t ed25519 -f "%KEY_FILE%" -N "" -C "windows@tunnel"
    echo √ 密钥已生成
)

REM 提取隧道目标（用户名@服务器）用于提示部署公钥
for /f "tokens=5 delims= " %%a in ("!TCMD!") do set TUNNEL_DEST=%%a

echo.
echo ──────────────────────────────────────
echo   需要将此公钥部署到目标服务器上：
echo ──────────────────────────────────────
type "%USERPROFILE%\.ssh\id_ed25519.pub"
echo ──────────────────────────────────────
echo.
echo 部署命令（在目标服务器上运行）：
echo   echo '上面的公钥' ^>^> ~/.ssh/authorized_keys
echo.
echo 如果已部署过，按回车继续...
pause

REM 从命令中提取隧道名称
for /f "tokens=3 delims=: " %%a in ("!TCMD!") do set TARGET=%%a
if "%TARGET%"=="" set TARGET=tunnel

REM 创建脚本目录
if not exist "C:\tunnel-mesh\scripts" mkdir "C:\tunnel-mesh\scripts"
if not exist "C:\tunnel-mesh\logs" mkdir "C:\tunnel-mesh\logs"

set SCRIPT=C:\tunnel-mesh\scripts\tunnel-%TARGET%.ps1

REM 生成 PowerShell 隧道脚本
(
echo # Tunnel Mesh - %TARGET%
echo # 命令: !TCMD!
echo while ($true) {
echo     $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
echo     Write-Output "$ts [隧道] 启动..."
echo     !TCMD!
echo     $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
echo     Write-Output "$ts [隧道] 断开，10秒后重连..."
echo     Start-Sleep 10
echo }
) > "!SCRIPT!"

echo √ 脚本已生成: !SCRIPT!

REM 注册 Windows 计划任务（开机自启）
echo.
echo 配置开机自启...
powershell -Command ^
  "$taskName='Tunnel-%TARGET%';" ^
  "Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue;" ^
  "$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-WindowStyle Hidden -File \"!SCRIPT!\"';" ^
  "$trigger=New-ScheduledTaskTrigger -AtStartup;" ^
  "$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1);" ^
  "Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force;" ^
  "Start-ScheduledTask -TaskName $taskName"

if !errorlevel! neq 0 (
    echo 警告：计划任务创建可能失败，请以管理员身份运行
)

REM 保存命令到配置
if not exist "%USERPROFILE%\.tunnel-mesh" mkdir "%USERPROFILE%\.tunnel-mesh"
echo !TCMD! > "%USERPROFILE%\.tunnel-mesh\tunnel-%TARGET%.cmd"
echo %DATE% %TIME% !TCMD! >> "%USERPROFILE%\.tunnel-mesh\contracts.log"

echo.
echo ════════════════════════════════════════
echo   导入完成！
echo ════════════════════════════════════════
echo.
echo   隧道: %TARGET%
echo   开机自启: 已配置 (Tasks\Tunnel-%TARGET%)
echo.
echo   检查状态...
timeout /t 2 >nul
powershell -Command "Get-ScheduledTask -TaskName 'Tunnel-%TARGET%' | Select State"

echo.
echo ──────────────────────────────────────
echo   可以继续导入下一条隧道命令
echo   按任意键返回主菜单...
pause
goto menu

REM ========================================
REM [2] 查看状态
REM ========================================
:status
cls
echo.
echo ════════════════════════════════════════
echo   隧道状态
echo ════════════════════════════════════════
echo.
powershell -Command ^
  "Write-Host '';" ^
  "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'};" ^
  "if ($tasks) {$tasks | Select-Object TaskName,State | Format-Table -AutoSize} else {Write-Host '  暂无隧道'}"
echo.
echo 已保存的隧道命令:
if exist "%USERPROFILE%\.tunnel-mesh\*.cmd" (
    for %%f in ("%USERPROFILE%\.tunnel-mesh\*.cmd") do echo   %%~nf
) else (
    echo   暂无
)
echo.
pause
goto menu

REM ========================================
REM [3] 启动所有
REM ========================================
:start
cls
echo.
echo ════════════════════════════════════════
echo   启动所有隧道
echo ════════════════════════════════════════
echo.
powershell -Command ^
  "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'};" ^
  "foreach($t in $tasks){Start-ScheduledTask -TaskName $t.TaskName; Write-Host \"  √ $($t.TaskName)\"}"
echo.
pause
goto menu

REM ========================================
REM [4] 停止所有
REM ========================================
:stop
cls
echo.
echo ════════════════════════════════════════
echo   停止所有隧道
echo ════════════════════════════════════════
echo.
powershell -Command ^
  "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'};" ^
  "foreach($t in $tasks){Stop-ScheduledTask -TaskName $t.TaskName; Write-Host \"  √ $($t.TaskName)\"}"
echo.
pause
goto menu

REM ========================================
REM [5] 删除
REM ========================================
:remove
cls
echo.
echo ════════════════════════════════════════
echo   删除隧道
echo ════════════════════════════════════════
echo.
powershell -Command ^
  "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'} | Select-Object TaskName,State;" ^
  "if ($tasks) {$tasks | Format-Table -AutoSize} else {Write-Host '  暂无隧道'}"
echo.
set /p del_name="输入要删除的隧道名称: "
if "%del_name%"=="" goto menu

powershell -Command "Stop-ScheduledTask -TaskName 'Tunnel-%del_name%' -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName 'Tunnel-%del_name%' -Confirm:$false -ErrorAction SilentlyContinue"
del "C:\tunnel-mesh\scripts\tunnel-%del_name%.ps1" 2>nul
del "%USERPROFILE%\.tunnel-mesh\tunnel-%del_name%.cmd" 2>nul

echo √ %del_name% 已删除
pause
goto menu

REM ========================================
REM [6] 测试连接
REM ========================================
:test
cls
echo.
echo ════════════════════════════════════════
echo   测试连接
echo ════════════════════════════════════════
echo.
echo 现有隧道:
powershell -Command "$tasks=Get-ScheduledTask -TaskPath '\' | Where-Object {$_.TaskName -like 'Tunnel-*'} | Select-Object TaskName,State"
echo.
set /p test_host="输入 SSH 主机名测试: "
if "%test_host%"=="" goto menu
echo.
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no %test_host% "echo √ 连通" 2>nul && echo √ 连通 || echo × 不可达
echo.
pause
goto menu

:end
exit /b 0
