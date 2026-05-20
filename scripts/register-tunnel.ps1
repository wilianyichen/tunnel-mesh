# Tunnel Mesh - 注册隧道服务
param(
    [Parameter(Mandatory=$true)]
    [string]$TaskName,
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath
)

Write-Host "注册: $TaskName"
Write-Host "脚本: $ScriptPath"

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -File `"$ScriptPath`""
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
