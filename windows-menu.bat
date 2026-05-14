@echo off
chcp 65001 >nul
REM ========================================
REM Tunnel Mesh 管理菜单 (Windows)
REM 双击运行
REM ========================================

:menu
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║       Tunnel Mesh 管理菜单              ║
echo ╠════════════════════════════════════════╣
echo ║                                        ║
echo ║  [1] 查看隧道状态                       ║
echo ║  [2] 添加新隧道                         ║
echo ║  [3] 启动所有隧道                       ║
echo ║  [4] 停止所有隧道                       ║
echo ║  [5] 导入配置（粘贴配置文本）            ║
echo ║  [6] 导出配置（生成配置文本）            ║
echo ║  [7] 查看帮助                           ║
echo ║  [Q] 退出                               ║
echo ║                                        ║
echo ╚════════════════════════════════════════╝
echo.

set /p choice="请选择: "

if /i "%choice%"=="1" goto status
if /i "%choice%"=="2" goto add
if /i "%choice%"=="3" goto start
if /i "%choice%"=="4" goto stop
if /i "%choice%"=="5" goto import
if /i "%choice%"=="6" goto export
if /i "%choice%"=="7" goto help
if /i "%choice%"=="Q" goto end

echo.
echo [错误] 无效选择
timeout /t 2 >nul
goto menu

:status
cls
echo.
echo ════════════════════════════════════════
echo  隧道状态
echo ════════════════════════════════════════
echo.
python "C:\tunnel-mesh\tunnel-batch.py" status
echo.
pause
goto menu

:add
cls
echo.
echo ════════════════════════════════════════
echo  添加新隧道
echo ════════════════════════════════════════
echo.
echo 提示：如果已有配置文本，请选择 [5] 导入配置
echo.
set /p name="隧道名称（如 node3）: "
set /p target="目标地址（如 192.168.1.100:22）: "
echo.
python "C:\tunnel-mesh\tunnel-batch.py" add --name %name% --target %target%
echo.
pause
goto menu

:start
cls
echo.
echo ════════════════════════════════════════
echo  启动所有隧道
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
echo  停止所有隧道
echo ════════════════════════════════════════
echo.
python "C:\tunnel-mesh\tunnel-batch.py" stop-all
echo.
pause
goto menu

:import
cls
echo.
echo ════════════════════════════════════════
echo  导入配置
echo ════════════════════════════════════════
echo.
echo 请粘贴配置文本（从被连接服务器导出）
echo 输入完成后按 Ctrl+Z 然后按 Enter
echo.
echo ────────────────────────────────────────
set /p config_text=
echo ────────────────────────────────────────
echo.
REM 解析配置并添加
python "C:\tunnel-mesh\parse-config.py" "%config_text%"
echo.
pause
goto menu

:export
cls
echo.
echo ════════════════════════════════════════
echo  导出配置
echo ════════════════════════════════════════
echo.
echo 将以下配置文本复制到 Windows 电脑
echo 在 Windows 上选择 [5] 导入配置
echo.
echo ────────────────────────────────────────
python "C:\tunnel-mesh\export-config.py"
echo ────────────────────────────────────────
echo.
pause
goto menu

:help
cls
echo.
echo ════════════════════════════════════════
echo  使用帮助
echo ════════════════════════════════════════
echo.
echo 1. 在被连接服务器上运行导出脚本
echo 2. 复制生成的配置文本
echo 3. 在 Windows 上选择 [5] 导入配置
echo 4. 粘贴配置文本
echo 5. 选择 [3] 启动所有隧道
echo.
echo 配置文件位置: C:\tunnel-mesh\config\
echo 日志文件位置: C:\tunnel-mesh\logs\
echo.
pause
goto menu

:end
exit /b 0
