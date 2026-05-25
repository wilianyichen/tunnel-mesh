# Tunnel Mesh Windows — 信任阶段模型
# 数据操作委托给 tunnel_mesh.py（Python 统一核心），Windows 特有功能保留在此
param(
    [string]$Cmd,
    [string[]]$CmdArgs
)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path (Get-Location) -Parent }
$TunnelDir = $ScriptDir
$ScriptsDir = "$TunnelDir\scripts"
$ConfigDir = "$env:USERPROFILE\.tunnel-mesh"
$SshDir = "$env:USERPROFILE\.ssh"
$Python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $Python) { $Python = Get-Command python -ErrorAction SilentlyContinue }
$TunnelMeshPy = "$TunnelDir\scripts\tunnel_mesh.py"
ni -Force -ItemType Directory $ScriptsDir, $TunnelDir, $ConfigDir, $SshDir | Out-Null

# ═══════════════════════════════════════════════════════════
# 内部函数：非交互式注册 Scheduled Task
# ═══════════════════════════════════════════════════════════
function Register-TunnelNonInteractive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SshCommand
    )

    if ($SshCommand -notmatch 'ssh.*-R\s+(\d+)') {
        Write-Host '{"status":"error","error":"无法解析端口号，命令必须包含 ssh -R <port>"}'
        return 1
    }
    $port = $matches[1]
    $taskName = "Tunnel-$port"
    $scriptPath = "$ScriptsDir\tunnel-$port.ps1"
    $wrapperPath = "$ScriptsDir\run-$port.bat"
    $logPath = "$ConfigDir\tunnel-$port.log"

    # 注入 keepalive 选项防止僵死连接
    $enhancedCmd = $SshCommand
    if ($SshCommand -match '^ssh\s') {
        $enhancedCmd = $SshCommand -replace '^ssh\s', 'ssh -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes '
    }

    # 生成 wrapper PS1（无限重试 + 日志）
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

    # 生成 .bat 启动器（隐藏窗口）
    "@powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" | Out-File -Encoding ascii $wrapperPath

    # 注册 Scheduled Task
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false -ErrorAction SilentlyContinue
        $action = New-ScheduledTaskAction -Execute $wrapperPath
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        $SshCommand | Out-File "$ConfigDir\tunnel-$port.cmd" -Encoding utf8
        Write-Host "{\"status\":\"ok\",\"task_name\":\"$taskName\",\"port\":$port}"
    } catch {
        Write-Host "{\"status\":\"error\",\"task_name\":\"$taskName\",\"error\":\"$_\"}"
        return 1
    }
}

# ═══════════════════════════════════════════════════════════
# --cmd 子命令路由
# ═══════════════════════════════════════════════════════════
if ($Cmd -eq "--cmd") {
    $subCmd = if ($CmdArgs.Count -gt 0) { $CmdArgs[0] } else { "" }
    $subArgs = if ($CmdArgs.Count -gt 1) { $CmdArgs[1..($CmdArgs.Count - 1)] } else { @() }

    switch ($subCmd) {
        "python" {
            # 透传 Python（现有行为）
            if (-not $Python) { Write-Host "❌ 需要 python3" -ForegroundColor Red; exit 1 }
            if ($subArgs.Count -eq 0) { & $Python $TunnelMeshPy "--help"; exit 0 }
            & $Python $TunnelMeshPy @subArgs
            exit $LASTEXITCODE
        }
        "register-tunnel" {
            $sshCmd = $subArgs -join ' '
            if (-not $sshCmd) { $sshCmd = Read-Host "粘贴 ssh -R 命令" }
            Register-TunnelNonInteractive -SshCommand $sshCmd
            exit $LASTEXITCODE
        }
        "unregister-tunnel" {
            $port = if ($subArgs.Count -gt 0) { $subArgs[0] } else { Read-Host "端口号" }
            $taskName = "Tunnel-$port"
            try {
                Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false -ErrorAction SilentlyContinue
                Remove-Item "$ScriptsDir\tunnel-$port.ps1", "$ScriptsDir\run-$port.bat", "$ConfigDir\tunnel-$port.cmd" -ErrorAction SilentlyContinue
                Write-Host "{\"status\":\"ok\",\"task_name\":\"$taskName\"}"
            } catch {
                Write-Host "{\"status\":\"error\",\"task_name\":\"$taskName\",\"error\":\"$_\"}"
                exit 1
            }
        }
        "list-tunnels" {
            $jsonFormat = $subArgs -contains "--json"
            try {
                $tasks = Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'Tunnel-*' }
                if ($jsonFormat) {
                    $result = @()
                    foreach ($t in $tasks) {
                        $port = $t.TaskName -replace 'Tunnel-', ''
                        $cmdFile = "$ConfigDir\tunnel-$port.cmd"
                        $cmd = if (Test-Path $cmdFile) { (Get-Content $cmdFile -Raw).Trim() } else { "" }
                        $result += @{ task_name = $t.TaskName; port = $port; state = $t.State; cmd = $cmd }
                    }
                    Write-Host ($result | ConvertTo-Json -Compress)
                } else {
                    if (-not $tasks) { Write-Host "  暂无隧道"; exit 0 }
                    $tasks | Select-Object TaskName, State | Format-Table -AutoSize
                }
            } catch {
                Write-Host '{"status":"error","error":"无法查询 Scheduled Tasks"}'
                exit 1
            }
        }
        "check-tunnel" {
            $port = if ($subArgs.Count -gt 0) { $subArgs[0] } else { "" }
            if (-not $port) { Write-Host '{"status":"error","error":"需要端口号"}' ; exit 1 }
            $r = & nc -z localhost $port 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "{\"status\":\"ok\",\"port\":$port,\"listening\":true}"
            } else {
                Write-Host "{\"status\":\"ok\",\"port\":$port,\"listening\":false}"
            }
        }
        "ensure-scripts" {
            ni -Force -ItemType Directory $ScriptsDir, $ConfigDir, $SshDir | Out-Null
            $KeyFile = "$SshDir\id_ed25519"
            if (-not (Test-Path $KeyFile)) {
                $empty = ""
                ssh-keygen -t ed25519 -f $KeyFile -N $empty -C "windows@tunnel" 2>$null
                Write-Host "{\"status\":\"ok\",\"action\":\"keygen\",\"key\":\"$KeyFile\"}"
            } else {
                Write-Host "{\"status\":\"ok\",\"action\":\"skip\",\"key\":\"$KeyFile\"}"
            }
        }
        default {
            # 向后兼容: 裸 --cmd <args> → 透传 Python
            if (-not $Python) { Write-Host "❌ 需要 python3" -ForegroundColor Red; exit 1 }
            if ($CmdArgs.Count -eq 0) { & $Python $TunnelMeshPy "--help"; exit 0 }
            & $Python $TunnelMeshPy @CmdArgs
            exit $LASTEXITCODE
        }
    }
    exit 0
}

# 非交互模式：裸命令自动转为 --cmd python
if (-not [Environment]::UserInteractive -or -not $Host.UI.RawUI) {
    if ($Cmd) {
        if (-not $Python) { Write-Host "❌ 需要 python3"; exit 1 }
        & $Python $TunnelMeshPy $Cmd @CmdArgs
        exit $LASTEXITCODE
    }
    Write-Host "Tunnel Mesh v3.0.0"
    Write-Host "用法: .\tunnel-mesh.ps1 --cmd <子命令> [参数...]"
    Write-Host "子命令: python | register-tunnel | unregister-tunnel | list-tunnels | check-tunnel | ensure-scripts"
    Write-Host "详情: .\tunnel-mesh.ps1 --cmd python help"
    exit 0
}

# ═══════════════════════════════════════════════════════════
# 交互式菜单（保持原有体验不变）
# ═══════════════════════════════════════════════════════════
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
    Write-Host "║  [4] 审视信任     — 查看服务器 + 测试连接        ║"
    Write-Host "║  [5] 撤销信任     — 删除隧道                     ║"
    Write-Host "║  [Q] 退出                                        ║"
    Write-Host "╚══════════════════════════════════════════════════╝"
}

function Import-Tunnel {
    Clear-Host; Write-Host "`n粘贴 ssh -R 命令:"; Write-Host "──────────────────"
    $sshCmd = Read-Host
    if ($sshCmd -notmatch 'ssh.*-R') { Write-Host "格式错误"; Pause; return }
    Register-TunnelNonInteractive -SshCommand $sshCmd | Out-Null
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
    if ($Python -and (Test-Path $TunnelMeshPy)) {
        & $Python $TunnelMeshPy status
    }
    Write-Host ""
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
        '4' { Show-Status; $h = Read-Host "主机名"; ssh -o ConnectTimeout=5 $h "echo OK" 2>$null; if ($LASTEXITCODE -eq 0) { Write-Host "√ 连通" } else { Write-Host "×" }; Pause }
        '5' { Remove-Tunnel }
        'q' { exit }
        'Q' { exit }
    }
}
