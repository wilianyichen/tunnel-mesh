# Tunnel Mesh Windows
param()

$ScriptDir = Split-Path $0
$TunnelDir = "C:\tunnel-mesh"
$ScriptsDir = "$TunnelDir\scripts"
$ConfigDir = "$env:USERPROFILE\.tunnel-mesh"
$SshDir = "$env:USERPROFILE\.ssh"

# 初始化
ni -Force -ItemType Directory $ScriptsDir, $TunnelDir, $ConfigDir, $SshDir | Out-Null

# 密钥
$KeyFile = "$SshDir\id_ed25519"
if (-not (Test-Path $KeyFile)) {
    ssh-keygen -t ed25519 -f $KeyFile -N '""' -C "windows@tunnel" 2>$null
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "╔════════════════════════════════════════╗"
    Write-Host "║     Tunnel Mesh  契约大厅 (Windows)    ║"
    Write-Host "╠════════════════════════════════════════╣"
    Write-Host "║                                        ║"
    Write-Host "║  [1] 导入隧道命令 (粘贴 ssh -R ... )   ║"
    Write-Host "║  [2] 导出身份卡（给 Linux 用）          ║"
    Write-Host "║  [3] 查看隧道状态                      ║"
    Write-Host "║  [4] 启动所有隧道                      ║"
    Write-Host "║  [5] 停止所有隧道                      ║"
    Write-Host "║  [6] 删除隧道                          ║"
    Write-Host "║  [7] 测试连接                          ║"
    Write-Host "║  [Q] 退出                              ║"
    Write-Host "║                                        ║"
    Write-Host "╚════════════════════════════════════════╝"
    Write-Host ""
}

function Import-Tunnel {
    Clear-Host
    Write-Host ""
    Write-Host "════════════════════════════════════════"
    Write-Host "  导入隧道命令"
    Write-Host "════════════════════════════════════════"
    Write-Host ""
    Write-Host "粘贴 Linux 生成的 ssh -R 命令:"
    Write-Host "──────────────────────────────────────"
    $cmd = Read-Host
    Write-Host "──────────────────────────────────────"

    if ($cmd -notmatch 'ssh.*-R') {
        Write-Host "错误：请输入完整的 ssh -R 命令"
        Pause; return
    }

    # 提取端口作为隧道名
    if ($cmd -match '-R\s+(\d+)') { $tunnelPort = $matches[1] } else { $tunnelPort = "tunnel" }
    $taskName = "Tunnel-$tunnelPort"
    $scriptPath = "$ScriptsDir\tunnel-$tunnelPort.ps1"
    $wrapperPath = "$ScriptsDir\run-$tunnelPort.bat"

    Write-Host ""
    Write-Host "密钥: $KeyFile"
    Write-Host ""

    # 生成隧道脚本
    @"
# Tunnel Mesh - $tunnelPort
while (`$true) {
    `$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "`$ts [隧道:$tunnelPort] 启动..."
    $cmd
    Write-Output "`$ts [隧道:$tunnelPort] 断开，10秒后重连..."
    Start-Sleep 10
}
"@ | Out-File -Encoding utf8 $scriptPath

    # 生成 wrapper bat
    "@powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" | Out-File -Encoding ascii $wrapperPath

    # 注册计划任务
    Write-Host "配置开机自启..."
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        $action = New-ScheduledTaskAction -Execute $wrapperPath
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force
        Start-ScheduledTask -TaskName $taskName
        
        $status = (Get-ScheduledTask -TaskName $taskName).State
        Write-Host "√ 隧道已创建: $taskName"
        Write-Host "  状态: $status"
        Write-Host "  开机自启: 已配置"
    } catch {
        Write-Host "× 失败: $_"
    }

    # 保存配置
    $cmd | Out-File "$ConfigDir\tunnel-$tunnelPort.cmd" -Encoding utf8
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $cmd" | Add-Content "$ConfigDir\contracts.log"

    Write-Host ""
    Write-Host "──────────────────────────────────────"
    Write-Host "  可以继续导入下一条隧道命令"
    Pause
}

function Export-Identity {
    Clear-Host
    Write-Host ""
    Write-Host "════════════════════════════════════════"
    Write-Host "  导出身份卡"
    Write-Host "════════════════════════════════════════"
    Write-Host ""
    Write-Host "──────────────────────────────────────"
    Write-Host "  身份卡（复制到 Linux 服务器）"
    Write-Host "  在 Linux 运行: bash tunnel-mesh.sh"
    Write-Host "  选择 [3]部署公钥，粘贴此卡"
    Write-Host "──────────────────────────────────────"
    Write-Host ""
    Write-Host "===IDENTITY==="
    Write-Host "NAME=$env:COMPUTERNAME"
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -notmatch 'Loopback|vEthernet|Hyper-V|docker' | Select-Object -First 1).IPAddress
    Write-Host "IP=$ip"
    Write-Host "PORT=22"
    Write-Host "USER=$env:USERNAME"
    Write-Host "PUBKEY="
    Get-Content "$KeyFile.pub"
    Write-Host "===END==="
    Write-Host ""
    Write-Host "在阿里云和 node3 上各导入一次，"
    Write-Host "Windows 就能免密连接它们。"
    Pause
}

function Show-Status {
    Clear-Host
    Write-Host ""
    Write-Host "════════════════════════════════════════"
    Write-Host "  隧道状态"
    Write-Host "════════════════════════════════════════"
    Write-Host ""
    try {
        $tasks = Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' }
        if ($tasks) {
            $tasks | Select-Object TaskName, State | Format-Table -AutoSize
        } else {
            Write-Host "  暂无隧道"
        }
    } catch {
        Write-Host "  暂无隧道"
    }
    Write-Host ""
    Write-Host "已保存的隧道命令:"
    $saved = Get-ChildItem "$ConfigDir\tunnel-*.cmd" -ErrorAction SilentlyContinue
    if ($saved) { $saved | ForEach-Object { Write-Host "  $($_.BaseName)" } } else { Write-Host "  暂无" }
    Pause
}

function Start-All {
    Clear-Host; Write-Host ""; Write-Host "启动所有隧道..."
    Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | ForEach-Object {
        Start-ScheduledTask -TaskName $_.TaskName; Write-Host "  √ $($_.TaskName)"
    }
    Pause
}

function Stop-All {
    Clear-Host; Write-Host ""; Write-Host "停止所有隧道..."
    Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName; Write-Host "  √ $($_.TaskName)"
    }
    Pause
}

function Remove-Tunnel {
    Clear-Host
    Write-Host ""; Write-Host "现有隧道:"
    Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -like 'Tunnel-*' } | Select-Object TaskName, State | Format-Table -AutoSize
    Write-Host ""
    $name = Read-Host "输入要删除的隧道名称"
    if ($name) {
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$ScriptsDir\tunnel-$($name -replace 'Tunnel-','').ps1", "$ScriptsDir\run-$($name -replace 'Tunnel-','').bat" -ErrorAction SilentlyContinue
        Remove-Item "$ConfigDir\tunnel-$($name -replace 'Tunnel-','').cmd" -ErrorAction SilentlyContinue
        Write-Host "√ $name 已删除"
    }
    Pause
}

function Test-Connection {
    Clear-Host
    Write-Host ""
    $hostname = Read-Host "输入 SSH 主机名测试"
    if ($hostname) {
        ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $hostname "echo OK" 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "√ 连通" } else { Write-Host "× 不可达" }
    }
    Pause
}

function Pause { Read-Host "`n按回车继续" | Out-Null }

# 主循环
while ($true) {
    Show-Menu
    $choice = Read-Host "选择"
    switch ($choice) {
        '1' { Import-Tunnel }
        '2' { Export-Identity }
        '3' { Show-Status }
        '4' { Start-All }
        '5' { Stop-All }
        '6' { Remove-Tunnel }
        '7' { Test-Connection }
        'q' { exit 0 }
        'Q' { exit 0 }
        default { Write-Host "无效选择"; Start-Sleep 1 }
    }
}
