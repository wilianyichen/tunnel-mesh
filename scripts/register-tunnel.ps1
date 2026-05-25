# Tunnel Mesh - 注册隧道服务（支持命令行直接传入 SSH 命令）
param(
    [string]$TaskName,
    [string]$ScriptPath,
    [string]$SshCommand
)

# 模式 A: 直接传入 SSH 命令（自动解析端口、生成 wrapper）
if ($SshCommand) {
    if ($SshCommand -match '-R\s+(\d+)') { $port = $matches[1] } else { $port = "tunnel" }
    if (-not $TaskName) { $TaskName = "Tunnel-$port" }
    # 使用 PSScriptRoot（PS 3+自动变量）或回退到用户 .tunnel-mesh 目录
    $ScriptsDir = if ($PSScriptRoot) { $PSScriptRoot } else { "$env:USERPROFILE\.tunnel-mesh\scripts" }
    $ConfigDir = "$env:USERPROFILE\.tunnel-mesh"
    ni -Force -ItemType Directory $ScriptsDir, $ConfigDir | Out-Null

    $scriptPath = "$ScriptsDir\tunnel-$port.ps1"
    $wrapperPath = "$ScriptsDir\run-$port.bat"
    $logPath = "$ConfigDir\tunnel-$port.log"

    # 注入 keepalive
    $enhancedCmd = $SshCommand -replace '^ssh\s', 'ssh -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes '

    @"
while (`$true) {
    `$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[`$ts] 隧道启动 [端口:$port]" | Out-File -Append -Encoding utf8 "$logPath"
    try {
        $enhancedCmd 2>&1 | Out-File -Append -Encoding utf8 "$logPath"
    } catch {
        "[`$ts] 错误: `$_" | Out-File -Append -Encoding utf8 "$logPath"
    }
    "[`$ts] 隧道断开，10秒后重连..." | Out-File -Append -Encoding utf8 "$logPath"
    Start-Sleep 10
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
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force
    Start-ScheduledTask -TaskName $TaskName

    $status = Get-ScheduledTask -TaskName $TaskName
    Write-Host "状态: $($status.State)"
    Write-Host "OK"
} catch {
    Write-Error "失败: $_"
    exit 1
}
