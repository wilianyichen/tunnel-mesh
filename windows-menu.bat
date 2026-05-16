@echo off
chcp 65001 >nul
REM ========================================
REM Tunnel Mesh 契约大厅 (Windows 管理界面)
REM ========================================

:menu
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║         Tunnel Mesh  契约大厅          ║
echo ╠════════════════════════════════════════╣
echo ║                                        ║
echo ║  [1] 缔结新契约 (导入对方文书)         ║
echo ║  [2] 撰写契约文书 (导出我的信息)        ║
echo ║  [3] 契约之仪 (启动所有连接)            ║
echo ║  [4] 解除契约 (停止所有连接)            ║
echo ║  [5] 审视契约 (查看当前状态)            ║
echo ║  [6] 废弃契约 (删除某个连接)            ║
echo ║  [H] 契约法典 (帮助)                    ║
echo ║  [Q] 退却                                ║
echo ║                                        ║
echo ╚════════════════════════════════════════╝
echo.

set /p choice="请选择: "

if /i "%choice%"=="1" goto import
if /i "%choice%"=="2" goto export
if /i "%choice%"=="3" goto start
if /i "%choice%"=="4" goto stop
if /i "%choice%"=="5" goto status
if /i "%choice%"=="6" goto remove
if /i "%choice%"=="H" goto help
if /i "%choice%"=="Q" goto end

echo [错误] 无效选择
timeout /t 2 >nul
goto menu

:import
cls
echo.
echo ════════════════════════════════════════
echo   缔结新契约
echo ════════════════════════════════════════
echo.
echo 请粘贴对方给你的「契约文书」
echo 输入完成后按 Ctrl+Z 然后按 Enter
echo.
echo ────────────────────────────────────────
set /p contract_text=
echo ────────────────────────────────────────
echo.
python "C:\tunnel-mesh\parse-contract.py" "%contract_text%"
echo.
pause
goto menu

:export
cls
call "C:\tunnel-mesh\windows-export-config.bat"
goto menu

:start
cls
echo.
echo ════════════════════════════════════════
echo   契约之仪 - 启动所有连接
echo ════════════════════════════════════════
echo.
python "C:\tunnel-mesh\tunnel-batch.py" start-all
echo.
pause
goto menu

:stop
cls
echo.
echo ════════════════════════════════════════
echo   解除契约 - 停止所有连接
echo ════════════════════════════════════════
echo.
python "C:\tunnel-mesh\tunnel-batch.py" stop-all
echo.
pause
goto menu

:status
cls
echo.
echo ════════════════════════════════════════
echo   审视契约 - 当前状态
echo ════════════════════════════════════════
echo.
python "C:\tunnel-mesh\tunnel-batch.py" status
echo.
pause
goto menu

:remove
cls
echo.
echo ════════════════════════════════════════
echo   废弃契约
echo ════════════════════════════════════════
echo.
set /p remove_name="请输入要删除的契约名称: "
if not "%remove_name%"=="" (
    python "C:\tunnel-mesh\tunnel-batch.py" remove --name %remove_name%
)
echo.
pause
goto menu

:help
cls
echo.
echo ════════════════════════════════════════
echo   契约法典
echo ════════════════════════════════════════
echo.
echo 【契约类型】
echo.
echo   平等契约（双向连接）
echo   - 两台机器网络互通时使用
echo   - 双方都要运行「撰写契约文书」
echo   - 交换文书后，双方都能互相访问
echo.
echo   主仆契约（单向连接）
echo   - 只有一方能访问另一方时使用
echo   - 被访问方（仆）运行「撰写契约文书」
echo   - 访问方（主）运行「缔结新契约」
echo   - 需要一台公网服务器作为「契约之塔」
echo.
echo 【契约之塔】（中转服务器）
echo   - 是一台有公网IP的服务器
echo   - 通常是你租的云服务器
echo   - 双方都要能SSH连上它
echo.
echo 【使用流程】
echo   1. 被访问方运行「撰写契约文书」
echo   2. 复制输出的「契约文书」
echo   3. 访问方运行「缔结新契约」
echo   4. 粘贴契约文书
echo   5. 运行「契约之仪」启动连接
echo.
pause
goto menu

:end
exit /b 0
