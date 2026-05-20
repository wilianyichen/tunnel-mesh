# Tunnel Mesh - 注册隧道服务
# 由 tunnel-mesh.bat 调用，从临时文件读取配置
param(
    [string]$ConfigFile = "C:\tunnel-mesh\scripts\.task-config.json"
)

$cfg = Get-Content $ConfigFile | ConvertFrom-Json
$taskName = $cfg.TaskName
$scriptPath = $cfg.ScriptPath

Write-Host "注册计划任务: $taskName"
Write-Host "隧道脚本: $scriptPath"

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force
Start-ScheduledTask -TaskName $taskName

$status = Get-ScheduledTask -TaskName $taskName
Write-Host "状态: $($status.State)"
Write-Host "OK"
