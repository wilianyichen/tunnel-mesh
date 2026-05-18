# ========================================
# Tunnel Mesh Windows 一键安装向导
# 
# 使用方法：右键 → 以管理员身份运行 PowerShell
#          → 粘贴这一行：
#          PowerShell -ExecutionPolicy Bypass -File windows-auto-setup.ps1
# ========================================

$ErrorActionPreference = "Stop"
$scriptDir = "C:\tunnel-mesh"

# ── 欢迎 ──
Clear-Host
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗"
Write-Host "║                                                      ║"
Write-Host "║       Tunnel Mesh  一键安装向导                       ║"
Write-Host "║                                                      ║"
Write-Host "║   这个脚本帮你建立阿里云 ↔ node3 的双向连接            ║"
Write-Host "║   跟着提示输入信息就行。                               ║"
Write-Host "║                                                      ║"
Write-Host "╚══════════════════════════════════════════════════════╝"
Write-Host ""

# ── 管理员检查 ──
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ 请以管理员身份运行 PowerShell" -ForegroundColor Red
    Write-Host "   右键 PowerShell → 以管理员身份运行"
    Read-Host "按回车退出"
    exit 1
}

# ── 检查 SSH ──
Write-Host ">>> 检查环境..." -ForegroundColor Cyan
$sshCheck = ssh -V 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 未找到 SSH，请先安装 OpenSSH 客户端" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}
Write-Host "✅ SSH 就绪"
Write-Host ""

# ── 收集信息 ──
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host "  请输入服务器信息" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host ""
Write-Host "【阿里云】（你的云服务器）"
Write-Host "  就是那台有公网IP的服务器，如 8.131.61.234"
$aliyunIP = Read-Host "  IP地址"
$aliyunUser = Read-Host "  SSH用户名 [root]"
if ($aliyunUser -eq "") { $aliyunUser = "root" }

Write-Host ""
Write-Host "【node3】（实验室内网服务器）"
Write-Host "  校园网内的服务器，如 10.16.82.202:5122"
$node3IP = Read-Host "  IP地址"
$node3Port = Read-Host "  SSH端口 [5122]"
if ($node3Port -eq "") { $node3Port = "5122" }
$node3User = Read-Host "  SSH用户名 [wuxiaoran]"
if ($node3User -eq "") { $node3User = "wuxiaoran" }

# ── 分配端口 ──
Write-Host ""
Write-Host "【隧道端口】（自动分配，一般不用改）"
$tunnel1Port = Read-Host "  阿里云上的隧道端口 [2201]"
if ($tunnel1Port -eq "") { $tunnel1Port = "2201" }
$tunnel2Port = Read-Host "  node3上的隧道端口 [2223]"
if ($tunnel2Port -eq "") { $tunnel2Port = "2223" }

# ── 确认 ──
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host "  确认信息" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host ""
Write-Host "  隧道1: 阿里云($aliyunIP) 监听端口 $tunnel1Port → node3($node3IP`:$node3Port)"
Write-Host "  隧道2: node3($node3IP) 监听端口 $tunnel2Port → 阿里云($aliyunIP`:22)"
Write-Host ""
$confirm = Read-Host "  确认开始安装? [Y/n]"
if ($confirm -eq "n" -or $confirm -eq "N") {
    Write-Host "已取消"
    exit 0
}

# ── 创建目录 ──
Write-Host ""
Write-Host ">>> 创建目录..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "$scriptDir\scripts" | Out-Null
New-Item -ItemType Directory -Force -Path "$scriptDir\logs" | Out-Null
Write-Host "✅ 目录已创建"

# ── 生成隧道1脚本 ──
Write-Host ""
Write-Host ">>> 生成隧道脚本..." -ForegroundColor Cyan
$tunnel1 = @"
# Tunnel 1: 阿里云:`$${tunnel1Port} → node3:${node3Port}
while (`$true) {
    `$ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "`$ts [隧道1] 阿里云:`$${tunnel1Port} → node3:`$${node3Port}"
    ssh -R ${tunnel1Port}:${node3IP}:${node3Port} -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes -N ${aliyunUser}@${aliyunIP} 2>&1
    Write-Host "`$ts [隧道1] 断开，10秒后重连..."
    Start-Sleep 10
}
"@
$tunnel1 | Out-File "$scriptDir\scripts\tunnel-1.ps1" -Encoding UTF8

# ── 生成隧道2脚本 ──
$tunnel2 = @"
# Tunnel 2: node3:`$${tunnel2Port} → 阿里云:22
while (`$true) {
    `$ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "`$ts [隧道2] node3:`$${tunnel2Port} → 阿里云:22"
    ssh -R ${tunnel2Port}:${aliyunIP}:22 -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes -N ${node3User}@${node3IP} -p ${node3Port} 2>&1
    Write-Host "`$ts [隧道2] 断开，10秒后重连..."
    Start-Sleep 10
}
"@
$tunnel2 | Out-File "$scriptDir\scripts\tunnel-2.ps1" -Encoding UTF8
Write-Host "✅ 脚本已生成"

# ── 创建计划任务 ──
Write-Host ""
Write-Host ">>> 配置开机自启..." -ForegroundColor Cyan
$null = Unregister-ScheduledTask -TaskName "Tunnel-1-Aliyun-Node3" -Confirm:`$false -ErrorAction SilentlyContinue
$null = Unregister-ScheduledTask -TaskName "Tunnel-2-Node3-Aliyun" -Confirm:`$false -ErrorAction SilentlyContinue

$action1 = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -File `"$scriptDir\scripts\tunnel-1.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "Tunnel-1-Aliyun-Node3" -Action $action1 -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null

$action2 = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -File `"$scriptDir\scripts\tunnel-2.ps1`""
Register-ScheduledTask -TaskName "Tunnel-2-Node3-Aliyun" -Action $action2 -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
Write-Host "✅ 开机自启已配置"

# ── 启动隧道 ──
Write-Host ""
Write-Host ">>> 启动隧道..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName "Tunnel-1-Aliyun-Node3"
Start-ScheduledTask -TaskName "Tunnel-2-Node3-Aliyun"
Start-Sleep -Seconds 2
Write-Host "✅ 隧道已启动"

# ── 生成配置文本 ──
$aliyunConfig = @"
cat >> ~/.ssh/config << 'EOF'

# Tunnel Mesh - node3（通过Windows反向隧道）
Host node3
    HostName localhost
    Port ${tunnel1Port}
    User ${node3User}
    IdentityFile ~/.ssh/id_node3
    IdentitiesOnly yes
    StrictHostKeyChecking no
    HostKeyAlias node3
EOF
chmod 600 ~/.ssh/config
"@

$node3Config = @"
cat >> ~/.ssh/config << 'EOF'

# Tunnel Mesh - 阿里云（通过Windows反向隧道）
Host aliyun
    HostName localhost
    Port ${tunnel2Port}
    User ${aliyunUser}
    IdentityFile ~/.ssh/id_aliyun
    IdentitiesOnly yes
    StrictHostKeyChecking no
    HostKeyAlias aliyun
EOF
chmod 600 ~/.ssh/config
"@

# ── 输出操作指南 ──
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗"
Write-Host "║                                                      ║"
Write-Host "║   ✅ 安装完成！                                       ║"
Write-Host "║                                                      ║"
Write-Host "║   接下来需要在另外两台服务器上配置。                   ║"
Write-Host "║   往下翻，复制对应的代码块，粘贴到对应服务器即可。     ║"
Write-Host "║                                                      ║"
Write-Host "╚══════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host ""
Write-Host "┌─────────────────────────────────────────────────────┐"
Write-Host "│                                                     │"
Write-Host "│  第2步：登录阿里云，粘贴下面这段                      │"
Write-Host "│                                                     │"
Write-Host "│  ssh ${aliyunUser}@${aliyunIP}                                │"
Write-Host "│  然后粘贴下面的代码                                  │"
Write-Host "│                                                     │"
Write-Host "└─────────────────────────────────────────────────────┘"
Write-Host ""
Write-Host $aliyunConfig
Write-Host ""
Write-Host ""
Write-Host "┌─────────────────────────────────────────────────────┐"
Write-Host "│                                                     │"
Write-Host "│  第3步：登录node3，粘贴下面这段                       │"
Write-Host "│                                                     │"
Write-Host "│  ssh -p ${node3Port} ${node3User}@${node3IP}                  │"
Write-Host "│  然后粘贴下面的代码                                  │"
Write-Host "│                                                     │"
Write-Host "└─────────────────────────────────────────────────────┘"
Write-Host ""
Write-Host $node3Config
Write-Host ""
Write-Host ""
Write-Host "════════════════════════════════════════════════════════"
Write-Host ""
Write-Host "全部完成后验证："
Write-Host ""
Write-Host "  阿里云上: ssh node3 hostname"
Write-Host "  node3上:  ssh aliyun hostname"
Write-Host ""
Write-Host "════════════════════════════════════════════════════════"
Write-Host ""
Read-Host "按回车关闭"
