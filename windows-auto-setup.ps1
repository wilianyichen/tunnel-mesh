# ========================================
# Tunnel Mesh Windows 自启动安装脚本
# 管理员 PowerShell 运行
# ========================================

param(
    [string]$AliyunIP = "8.131.61.234",
    [string]$Node3IP = "10.16.82.202",
    [int]$Node3Port = 5122,
    [string]$Node3User = "wuxiaoran",
    [int]$Tunnel1Port = 2201,
    [int]$Tunnel2Port = 2223
)

$ErrorActionPreference = "Stop"
$scriptDir = "C:\tunnel-mesh"
$scriptsDir = "$scriptDir\scripts"
$logsDir = "$scriptDir\logs"

# 管理员检查
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[错误] 请以管理员身份运行" -ForegroundColor Red
    pause
    exit 1
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗"
Write-Host "║     Tunnel Mesh Windows 自启动安装               ║"
Write-Host "╠══════════════════════════════════════════════════╣"
Write-Host "║  将在 Windows 上创建两个自启动隧道服务            ║"
Write-Host "║                                                  ║"
Write-Host "║  隧道1: 阿里云 ←→ node3                          ║"
Write-Host "║  隧道2: node3  ←→ 阿里云                         ║"
Write-Host "╚══════════════════════════════════════════════════╝"
Write-Host ""

# ========================================
# 1. 检查依赖
# ========================================
Write-Host "[1/5] 检查依赖..." -ForegroundColor Cyan

$sshVer = ssh -V 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ SSH 客户端: $sshVer"
} else {
    Write-Host "  ✗ SSH 未安装" -ForegroundColor Red
    exit 1
}

# ========================================
# 2. 创建目录结构
# ========================================
Write-Host ""
Write-Host "[2/5] 创建目录..." -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
Write-Host "  ✓ $scriptsDir"
Write-Host "  ✓ $logsDir"

# ========================================
# 3. 生成隧道脚本
# ========================================
Write-Host ""
Write-Host "[3/5] 生成隧道脚本..." -ForegroundColor Cyan

# 隧道1：阿里云→node3
$tunnel1Script = @"
# Tunnel Mesh - 隧道1: 阿里云→node3
# $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
\$hostname = hostname
while (\$true) {
    \$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "\$ts [隧道1] 阿里云:${Tunnel1Port} → node3:${Node3Port}"

    ssh `
        -i "\$env:USERPROFILE\.ssh\id_aliyun" `
        -R ${Tunnel1Port}:${Node3IP}:${Node3Port} `
        -o StrictHostKeyChecking=no `
        -o ServerAliveInterval=60 `
        -o ServerAliveCountMax=3 `
        -o ExitOnForwardFailure=yes `
        -N root@${AliyunIP}

    \$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "\$ts [隧道1] 断开，10秒后重连..."
    Start-Sleep 10
}
"@

# 隧道2：node3→阿里云
$tunnel2Script = @"
# Tunnel Mesh - 隧道2: node3→阿里云
# $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
\$hostname = hostname
while (\$true) {
    \$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "\$ts [隧道2] node3:${Tunnel2Port} → 阿里云:22"

    ssh `
        -i "\$env:USERPROFILE\.ssh\id_node3" `
        -R ${Tunnel2Port}:${AliyunIP}:22 `
        -o StrictHostKeyChecking=no `
        -o ServerAliveInterval=60 `
        -o ServerAliveCountMax=3 `
        -o ExitOnForwardFailure=yes `
        -N ${Node3User}@${Node3IP} -p ${Node3Port}

    \$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "\$ts [隧道2] 断开，10秒后重连..."
    Start-Sleep 10
}
"@

$tunnel1Script | Out-File -FilePath "$scriptsDir\tunnel-1.ps1" -Encoding UTF8
$tunnel2Script | Out-File -FilePath "$scriptsDir\tunnel-2.ps1" -Encoding UTF8
Write-Host "  ✓ tunnel-1.ps1 (阿里云→node3)"
Write-Host "  ✓ tunnel-2.ps1 (node3→阿里云)"

# ========================================
# 4. 创建自启动任务
# ========================================
Write-Host ""
Write-Host "[4/5] 创建开机自启动..." -ForegroundColor Cyan

# 删除旧任务（如果存在）
$null = Unregister-ScheduledTask -TaskName "Tunnel-1-Aliyun-Node3" -Confirm:$false -ErrorAction SilentlyContinue
$null = Unregister-ScheduledTask -TaskName "Tunnel-2-Node3-Aliyun" -Confirm:$false -ErrorAction SilentlyContinue

# 任务1
$action1 = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptsDir\tunnel-1.ps1`""
$trigger1 = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "Tunnel-1-Aliyun-Node3" -Action $action1 -Trigger $trigger1 -Settings $settings -RunLevel Highest -Force | Out-Null
Write-Host "  ✓ 任务 Tunnel-1-Aliyun-Node3"

# 任务2
$action2 = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptsDir\tunnel-2.ps1`""
Register-ScheduledTask -TaskName "Tunnel-2-Node3-Aliyun" -Action $action2 -Trigger $trigger1 -Settings $settings -RunLevel Highest -Force | Out-Null
Write-Host "  ✓ 任务 Tunnel-2-Node3-Aliyun"

# ========================================
# 5. 启动隧道
# ========================================
Write-Host ""
Write-Host "[5/5] 启动隧道..." -ForegroundColor Cyan

Start-ScheduledTask -TaskName "Tunnel-1-Aliyun-Node3"
Write-Host "  ✓ 隧道1 已启动"

Start-ScheduledTask -TaskName "Tunnel-2-Node3-Aliyun"
Write-Host "  ✓ 隧道2 已启动"

# ========================================
# 生成配置卡片（复制到阿里云和node3）
# ========================================
Write-Host ""
Write-Host "════════════════════════════════════════════════════════"
Write-Host "  隧道安装完成！"
Write-Host "════════════════════════════════════════════════════════"
Write-Host ""
Write-Host "【开机自启】已配置 ✓"
Write-Host "  - 重启 Windows 后隧道自动恢复"
Write-Host "  - 隧道断开后自动重连"
Write-Host ""

# 阿里云配置
Write-Host "────────────────────────────────────────"
Write-Host "  将此配置添加到 阿里云 的 ~/.ssh/config"
Write-Host "────────────────────────────────────────"
Write-Host ""
Write-Host "Host node3"
Write-Host "    HostName localhost"
Write-Host "    Port ${Tunnel1Port}"
Write-Host "    User ${Node3User}"
Write-Host "    IdentityFile ~/.ssh/id_node3"
Write-Host "    IdentitiesOnly yes"
Write-Host "    StrictHostKeyChecking no"
Write-Host "    HostKeyAlias node3"
Write-Host ""

# node3 配置
Write-Host "────────────────────────────────────────"
Write-Host "  将此配置添加到 node3 的 ~/.ssh/config"
Write-Host "────────────────────────────────────────"
Write-Host ""
Write-Host "Host aliyun"
Write-Host "    HostName localhost"
Write-Host "    Port ${Tunnel2Port}"
Write-Host "    User root"
Write-Host "    IdentityFile ~/.ssh/id_aliyun"
Write-Host "    IdentitiesOnly yes"
Write-Host "    StrictHostKeyChecking no"
Write-Host "    HostKeyAlias aliyun"
Write-Host ""

# 验证命令
Write-Host "────────────────────────────────────────"
Write-Host "  验证命令"
Write-Host "────────────────────────────────────────"
Write-Host ""
Write-Host "  阿里云上: ssh node3 hostname"
Write-Host "  node3上:  ssh aliyun hostname"
Write-Host "  Windows上:"
Write-Host "    Get-ScheduledTask -TaskName 'Tunnel-1*','Tunnel-2*' | Select TaskName,State"
Write-Host ""

pause
