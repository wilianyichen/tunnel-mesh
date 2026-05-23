# Tunnel Mesh Windows — 信任阶段模型
param()
$ScriptDir = Split-Path $0
$TunnelDir = "C:\tunnel-mesh"
$ScriptsDir = "$TunnelDir\scripts"
$ConfigDir = "$env:USERPROFILE\.tunnel-mesh"
$SshDir = "$env:USERPROFILE\.ssh"
ni -Force -ItemType Directory $ScriptsDir, $TunnelDir, $ConfigDir, $SshDir | Out-Null

$KeyFile = "$SshDir\id_ed25519"
if (-not (Test-Path $KeyFile)) { $empty = ""; ssh-keygen -t ed25519 -f $KeyFile -N $empty -C "windows@tunnel" 2>$null }

function Show-Menu {
    Clear-Host; Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗"
    Write-Host "║   Tunnel Mesh (Windows)                          ║"
    Write-Host "╠══════════════════════════════════════════════════╣"
    Write-Host "║  [1] 建立加密信任 — 导出身份卡                   ║"
    Write-Host "║  [2] 建立网络信任 — 导入隧道命令                 ║"
    Write-Host "║  [3] 维持信任     — 查看/启动/停止隧道           ║"
    Write-Host "║  [4] 审视信任     — 测试连接                     ║"
    Write-Host "║  [5] 撤销信任     — 删除隧道                     ║"
    Write-Host "║  [Q] 退出                                        ║"
    Write-Host "╚══════════════════════════════════════════════════╝"
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
    Clear-Host
    $name = $env:COMPUTERNAME
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -notmatch 'Loopback|vEthernet' | Select-Object -First 1).IPAddress
    $pubkey = Get-Content "$KeyFile.pub"
    $raw = "NAME=$name`nIP=$ip`nPORT=22`nUSER=$env:USERNAME`nPUBKEY=$pubkey"
    $checksum = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($raw))).Replace("-","").ToLower()

    Write-Host "`n===IDENTITY v1==="
    Write-Host $raw
    Write-Host "CHECKSUM=sha256:$checksum"
    Write-Host "===END==="
    Write-Host "`n复制到 Linux: bash tunnel-mesh.sh → [1]建立加密信任 → [2]部署公钥"
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
    Clear-Host; Write-Host "`n[1]启动全部 [2]停止全部 [B]返回"
    $c = Read-Host
    switch ($c) {
        '1' { Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | ForEach-Object { Start-ScheduledTask -TaskName $_.TaskName; Write-Host "√ $($_.TaskName)" } }
        '2' { Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | ForEach-Object { Stop-ScheduledTask -TaskName $_.TaskName; Write-Host "√ $($_.TaskName)" } }
    }
    Pause
}

function Remove-Tunnel {
    Clear-Host
    try { Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | Select-Object TaskName, State | Format-Table -AutoSize } catch { Write-Host "  暂无隧道"; Pause; return }
    $n = Read-Host "`n输入要删除的隧道名 (如 Tunnel-2201)"
    if ($n) {
        Stop-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue
        $port = $n -replace 'Tunnel-',''
        Remove-Item "$ScriptsDir\tunnel-$port.ps1","$ScriptsDir\run-$port.bat","$ConfigDir\tunnel-$port.cmd" -ErrorAction SilentlyContinue
        Write-Host "√ $n 已删除"
    }
    Pause
}

function Pause { Read-Host "`n按回车继续" | Out-Null }

while ($true) {
    Show-Menu; $c = Read-Host "选择"
    switch ($c) {
        '1' { Export-Identity }
        '2' { Import-Tunnel }
        '3' { Show-Status; Manage-Tunnel }
        '4' { $h = Read-Host "主机名"; ssh -o ConnectTimeout=5 $h "echo OK" 2>$null; if ($LASTEXITCODE -eq 0) { Write-Host "√ 连通" } else { Write-Host "×" }; Pause }
        '5' { Remove-Tunnel }
        'q' { exit }
        'Q' { exit }
    }
}
