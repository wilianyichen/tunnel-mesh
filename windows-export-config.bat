@echo off
chcp 65001 >nul
REM ========================================
REM Tunnel Mesh 配置导出 (Windows 端)
REM 在 Windows 上运行，生成契约文书
REM ========================================

echo.
echo ╔════════════════════════════════════════╗
echo ║   Tunnel Mesh - Windows 端导出         ║
echo ╠════════════════════════════════════════╣
echo ║  生成你的契约文书，                     ║
echo ║  复制给对方服务器即可建立连接。         ║
echo ╚════════════════════════════════════════╝
echo.

REM 获取本机信息
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr "IPv4"') do set SERVER_IP=%%a
set SERVER_IP=%SERVER_IP: =%

echo 【本机信息】
echo   主机名: %COMPUTERNAME%
echo   IP地址: %SERVER_IP%
echo.

REM 获取公钥
set PUB_KEY=
if exist "%USERPROFILE%\.ssh\id_ed25519.pub" (
    set /p PUB_KEY=<"%USERPROFILE%\.ssh\id_ed25519.pub"
) else if exist "%USERPROFILE%\.ssh\id_rsa.pub" (
    set /p PUB_KEY=<"%USERPROFILE%\.ssh\id_rsa.pub"
)

echo 【选择契约类型】
echo.
echo   [1] 平等契约 - 双向连接，互相可以访问
echo       条件：两台电脑网络互通
echo.
echo   [2] 主仆契约 - 单向连接，对方访问你
echo       条件：需要一台公网服务器中转
echo.

set /p CONTRACT_TYPE="请选择 [1/2]: "
if "%CONTRACT_TYPE%"=="" set CONTRACT_TYPE=2

if "%CONTRACT_TYPE%"=="2" (
    echo.
    echo ════════════════════════════════════════
    echo   缔结主仆契约
    echo ════════════════════════════════════════
    echo.
    echo 需要一台「契约之塔」（中转服务器）。
    echo 它必须有一串公网IP。
    echo.
    set /p RELAY_NAME="  名称 [aliyun]（给中转服务器起个名）: "
    if "%RELAY_NAME%"=="" set RELAY_NAME=aliyun
    set /p RELAY_IP="  公网IP（中转服务器的公网地址）: "
    set /p RELAY_PORT="  SSH端口 [22]（中转服务器的SSH端口）: "
    if "%RELAY_PORT%"=="" set RELAY_PORT=22
    set /p RELAY_USER="  SSH用户 [root]（用哪个账号登录中转服务器）: "
    if "%RELAY_USER%"=="" set RELAY_USER=root
)

echo.
echo ────────────────────────────────────────
echo   契约文书（复制以下全部内容）
echo ────────────────────────────────────────
echo.
echo ===CONTRACT_START===
echo CONTRACT_TYPE=%CONTRACT_TYPE%
echo CONTRACT_NAME=%COMPUTERNAME%
echo SERVER_NAME=%COMPUTERNAME%
echo SERVER_IP=%SERVER_IP%
echo SERVER_PORT=22
echo PUB_KEY=%PUB_KEY%

if "%CONTRACT_TYPE%"=="2" (
    echo RELAY_NAME=%RELAY_NAME%
    echo RELAY_IP=%RELAY_IP%
    echo RELAY_PORT=%RELAY_PORT%
    echo RELAY_USER=%RELAY_USER%
)

echo ===CONTRACT_END===
echo.
echo ────────────────────────────────────────
echo.
echo 【下一步】
echo   把上面的「契约文书」复制到对方电脑，
echo   在 Tunnel Mesh 中选择「缔结契约」即可。
echo.
pause
