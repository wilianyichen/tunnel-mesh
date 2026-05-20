# Tunnel Mesh Windows
param()
$ScriptDir = Split-Path $0
$TunnelDir = "C:\tunnel-mesh"
$ScriptsDir = "$TunnelDir\scripts"
$ConfigDir = "$env:USERPROFILE\.tunnel-mesh"
$SshDir = "$env:USERPROFILE\.ssh"
ni -Force -ItemType Directory $ScriptsDir, $TunnelDir, $ConfigDir, $SshDir | Out-Null

$KeyFile = "$SshDir\id_ed25519"
if (-not (Test-Path $KeyFile)) { ssh-keygen -t ed25519 -f $KeyFile -N '""' -C "windows@tunnel" 2>$null }

function Show-Menu {
    Clear-Host; Write-Host ""
    Write-Host "╔════════════════════════════════════════╗"
    Write-Host "║   Tunnel Mesh (Windows)                ║"
    Write-Host "╠════════════════════════════════════════╣"
    Write-Host "║  [1] 导入隧道命令 (粘贴 ssh -R ...)    ║"
    Write-Host "║  [2] 导出身份卡 (给 Linux 部署公钥)    ║"
    Write-Host "║  [3] 查看隧道状态                     ║"
    Write-Host "║  [4] 启动/停止/删除                   ║"
    Write-Host "║  [5] 测试连接                         ║"
    Write-Host "║  [Q] 退出                             ║"
    Write-Host "╚════════════════════════════════════════╝"
}

function Import-Tunnel {
    Clear-Host; Write-Host "`n粘贴 ssh -R 命令:"; Write-Host "──────────────────"
    $cmd = Read-Host
    if ($cmd -notmatch 'ssh.*-R') { Write-Host "格式错误"; Pause; return }
    if ($cmd -match '-R\s+(\d+)') { $port = $matches[1] } else { $port = "tunnel" }
    $taskName = "Tunnel-$port"
    $scriptPath = "$ScriptsDir\tunnel-$port.ps1"
    $wrapperPath = "$ScriptsDir\run-$port.bat"

    @"
while (`$true) {
    `$ts = Get-Date -Format "HH:mm:ss"
    Write-Output "`$ts [隧道:$port]"
    $cmd
    Start-Sleep 10
}
"@ | Out-File -Encoding utf8 $scriptPath

    "@powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" | Out-File -Encoding ascii $wrapperPath

    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $taskName -Action (New-ScheduledTaskAction -Execute $wrapperPath) -Trigger (New-ScheduledTaskTrigger -AtStartup) -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)) -RunLevel Highest -Force
        Start-ScheduledTask -TaskName $taskName
        Write-Host "√ $taskName 已创建并启动"
    } catch { Write-Host "× 失败: $_" }
    $cmd | Out-File "$ConfigDir\tunnel-$port.cmd"
    Pause
}

function Export-Identity {
    Clear-Host; Write-Host "`n===IDENTITY==="
    Write-Host "NAME=$env:COMPUTERNAME"
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -notmatch 'Loopback|vEthernet' | Select-Object -First 1).IPAddress
    Write-Host "IP=$ip"; Write-Host "PORT=22"; Write-Host "USER=$env:USERNAME"
    Write-Host "PUBKEY="; Get-Content "$KeyFile.pub"; Write-Host "===END==="
    Write-Host "`n复制到 Linux: bash tunnel-mesh.sh → [1]密钥 → [2]部署"
    Pause
}

function Show-Status {
    Clear-Host; Write-Host "`n════════════════════════════════════════"; Write-Host "  隧道状态"; Write-Host "════════════════════════════════════════`n"
    try { Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | Select-Object TaskName, State | Format-Table -AutoSize } catch { Write-Host "  暂无" }
    $saved = Get-ChildItem "$ConfigDir\tunnel-*.cmd" -ErrorAction SilentlyContinue
    if ($saved) { Write-Host "`n已保存命令:"; $saved | ForEach-Object { Write-Host "  $($_.BaseName)" } }
    Pause
}

function Manage-Tunnel {
    Clear-Host; Write-Host "`n[1]启动全部 [2]停止全部 [3]删除某个"
    $c = Read-Host
    switch ($c) {
        '1' { Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | ForEach-Object { Start-ScheduledTask -TaskName $_.TaskName; Write-Host "√ $($_.TaskName)" } }
        '2' { Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | ForEach-Object { Stop-ScheduledTask -TaskName $_.TaskName; Write-Host "√ $($_.TaskName)" } }
        '3' { Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | Select-Object TaskName, State | Format-Table -AutoSize; $n = Read-Host "删除哪个"; if ($n) { Stop-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue; Remove-Item "$ScriptsDir\tunnel-*","$ScriptsDir\run-*" -ErrorAction SilentlyContinue; Write-Host "√ 已删除" } }
    }
    Pause
}

function Pause { Read-Host "`n按回车继续" | Out-Null }

while ($true) {
    Show-Menu; $c = Read-Host "选择"
    switch ($c) { '1' { Import-Tunnel } '2' { Export-Identity } '3' { Show-Status } '4' { Manage-Tunnel } '5' { $h = Read-Host "主机名"; ssh -o ConnectTimeout=5 $h "echo OK" 2>$null; if ($LASTEXITCODE -eq 0) { Write-Host "√ 连通" } else { Write-Host "×" }; Pause } 'q' { exit } 'Q' { exit } }
}
