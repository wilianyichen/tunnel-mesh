@echo off
REM Tunnel Mesh Windows Launcher
REM 自动提权 + 启动 PowerShell 主程序
net session >nul 2>&1 || (powershell -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)
powershell -ExecutionPolicy Bypass -File "%~dp0tunnel-mesh.ps1"
