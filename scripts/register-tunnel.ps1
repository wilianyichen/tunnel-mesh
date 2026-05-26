# Tunnel Mesh - 注册隧道服务（支持命令行直接传入 SSH 命令）
# 重启策略由 Scheduled Task RestartInterval 负责，wrapper 只做单次执行
param(
    [string]$TaskName,
    [string]$ScriptPath,
    [string]$SshCommand
)

# 模式 A: 直接传入 SSH 命令（自动解析端口、生成 wrapper）
if ($SshCommand) {
    if ($SshCommand -match '-R\s+(\d+)') { $port = $matches[1] } else { $port = "tunnel" }
    if (-not $TaskName) { $TaskName = "Tunnel-$port" }
    $ScriptsDir = if ($PSScriptRoot) { $PSScriptRoot } else { "$env:USERPROFILE\.tunnel-mesh\scripts" }
    $ConfigDir = "$env:USERPROFILE\.tunnel-mesh"
    ni -Force -ItemType Directory $ScriptsDir, $ConfigDir | Out-Null

    $scriptPath = "$ScriptsDir\tunnel-$port.ps1"
    $wrapperPath = "$ScriptsDir\run-$port.bat"
    $logPath = "$ConfigDir\tunnel-$port.log"

    # 注入 keepalive + 失败检测（与 Linux _generate_systemd_service 对齐）
    $enhancedCmd = $SshCommand -replace '^ssh\s', 'ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o TCPKeepAlive=yes '

    # wrapper 只做单次执行，重启由 Scheduled Task RestartInterval=10s 负责
    @"
`$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[`$ts] 隧道启动 [端口:$port]" | Out-File -Append -Encoding utf8 "$logPath"
try {
    $enhancedCmd 2>&1 | Out-File -Append -Encoding utf8 "$logPath"
} catch {
    "[`$ts] 错误: `$_" | Out-File -Append -Encoding utf8 "$logPath"
}
"@ | Out-File -Encoding utf8 $scriptPath

    "@powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" | Out-File -Encoding ascii $wrapperPath
}
else {
    # 模式 B: 已有脚本路径（兼容旧用法）
    if (-not $TaskName -or -not $ScriptPath) {
        Write-Error "用法: register-tunnel.ps1 -TaskName <name> -ScriptPath <path> [-SshCommand <cmd>]"
        exit 1
    }
}

Write-Host "注册: $TaskName"
Write-Host "脚本: $scriptPath"

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    # RestartInterval=10s 对齐 Linux RestartSec=10（单层重启，不做内层 while 循环）
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Seconds 10)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force
    Start-ScheduledTask -TaskName $TaskName

    $status = Get-ScheduledTask -TaskName $TaskName
    Write-Host "状态: $($status.State)"
    Write-Host "OK"
} catch {
    Write-Error "失败: $_"
    exit 1
}
