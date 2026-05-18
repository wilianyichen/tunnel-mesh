# 三服务器双向连接完整操作流程

## 网络拓扑

```
阿里云 (8.131.61.234:22)     ←→    Windows (10.16.73.249)     ←→    node3 (10.16.82.202:5122)
      公网 VPS                      校园网·你的电脑                    校园内网·实验室服务器
      
      出站: 不受限                   出站: 不受限                      出站: 仅80端口
      能连: Windows                 能连: 阿里云 + node3              能连: Windows + 校园网
      不能连: node3                 不能连: (无)                      不能连: 阿里云(22被封)
```

**核心问题**：阿里云和 node3 不能互连，但都能连 Windows。Windows 做桥梁。

---

## 目标

建立两条通路：
```
通路 1：阿里云 → node3（反向隧道）
通路 2：node3 → 阿里云（通过 Windows 跳转）
```

---

## 第一步：Windows 前置条件

### 1.1 检查 OpenSSH 客户端

```powershell
ssh -V
# 应该有版本号输出，Win10自带
```

### 1.2 安装 OpenSSH 服务端（node3 需要 ProxyJump 到 Windows）

```powershell
# 管理员 PowerShell
Add-WindowsCapability -Online -Name OpenSSH.Server

# 启动并设为自动
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# 防火墙放行
New-NetFirewallRule -DisplayName "SSH" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow
```

**为什么需要这一步**：node3 要 `ssh -J windows root@aliyun`，中间跳 Windows，Windows 必须开着 SSH 服务端。

### 1.3 生成两把 SSH 密钥

```powershell
# 连接阿里云用的
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_aliyun -C "windows-to-aliyun"

# 连接 node3 用的
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_node3 -C "windows-to-node3"
```

### 1.4 部署公钥

```powershell
# 部署到阿里云
type $env:USERPROFILE\.ssh\id_aliyun.pub | ssh root@8.131.61.234 "cat >> ~/.ssh/authorized_keys"

# 部署到 node3
type $env:USERPROFILE\.ssh\id_node3.pub | ssh -p 5122 wuxiaoran@10.16.82.202 "cat >> ~/.ssh/authorized_keys"
```

### 1.5 测试连接

```powershell
ssh root@8.131.61.234 "hostname"                    # 应输出阿里云主机名
ssh -p 5122 wuxiaoran@10.16.82.202 "hostname"       # 应输出 node3 主机名
```

---

## 第二步：Windows 隧道配置

### 2.1 创建隧道目录

```powershell
mkdir C:\tunnel-mesh\scripts -Force
mkdir C:\tunnel-mesh\logs -Force
```

### 2.2 隧道 1：阿里云 → node3（反向隧道）

创建 `C:\tunnel-mesh\scripts\tunnel-aliyun-to-node3.ps1`：

```powershell
# 反向隧道：阿里云:2201 → node3:5122
# 阿里云上 ssh -p 2201 wuxiaoran@localhost 即可连到 node3

while ($true) {
    Write-Host "$(Get-Date) Starting reverse tunnel to aliyun..."
    
    $process = Start-Process -FilePath "ssh" -ArgumentList @(
        "-i", "$env:USERPROFILE\.ssh\id_aliyun",
        "-R", "2201:10.16.82.202:5122",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ServerAliveInterval=60",
        "-o", "ServerAliveCountMax=3",
        "-o", "ExitOnForwardFailure=yes",
        "-N",
        "root@8.131.61.234"
    ) -PassThru -NoNewWindow -Wait
    
    Write-Host "$(Get-Date) Tunnel disconnected. Reconnecting in 10s..."
    Start-Sleep -Seconds 10
}
```

### 2.3 创建 Windows 服务（开机自启）

```powershell
# 管理员 PowerShell

# 服务 1：阿里云→node3 反向隧道
sc.exe create "Tunnel-Aliyun-Node3" `
    binPath= "powershell.exe -ExecutionPolicy Bypass -File C:\tunnel-mesh\scripts\tunnel-aliyun-to-node3.ps1" `
    start= auto `
    DisplayName= "Tunnel Mesh - Aliyun to Node3"

sc.exe failure "Tunnel-Aliyun-Node3" reset= 86400 actions= restart/10000/restart/10000/restart/10000

sc.exe start "Tunnel-Aliyun-Node3"
```

### 2.4 验证隧道

```powershell
# 检查服务状态
sc.exe query "Tunnel-Aliyun-Node3"

# 在阿里云上测试（或从 Windows 模拟）
ssh root@8.131.61.234 "ssh -p 2201 -o StrictHostKeyChecking=no wuxiaoran@localhost hostname"
# 应输出: node3
```

---

## 第三步：阿里云配置

### 3.1 添加 node3 的 SSH config

```bash
cat >> ~/.ssh/config << 'EOF'

# node3（通过 Windows 反向隧道）
Host node3
    HostName localhost
    Port 2201
    User wuxiaoran
    IdentityFile ~/.ssh/id_node3
    IdentitiesOnly yes
    StrictHostKeyChecking no
EOF
```

### 3.2 确保能连 Windows（noode3 的 ProxyJump 会用到）

```bash
cat >> ~/.ssh/config << 'EOF'

# Windows（跳板）
Host windows
    HostName 10.16.73.249
    User wilia
    StrictHostKeyChecking no
EOF
```

### 3.3 测试

```bash
ssh node3 hostname     # 应输出 node3
```

---

## 第四步：node3 配置

### 4.1 添加阿里云的 SSH config（ProxyJump 通过 Windows）

```bash
cat >> ~/.ssh/config << 'EOF'

# 阿里云（通过 Windows 跳转，因为校园网封了22端口出站）
Host aliyun
    HostName 8.131.61.234
    User root
    ProxyJump windows
    IdentityFile ~/.ssh/id_aliyun
    StrictHostKeyChecking no

# Windows（跳板机，同校园网）
Host windows
    HostName 10.16.73.249
    User wilia
    StrictHostKeyChecking no
EOF
```

### 4.2 确保 node3 能连 Windows

```bash
# 把 node3 的公钥添加到 Windows
ssh-copy-id wilia@10.16.73.249

# 测试
ssh windows hostname
```

### 4.3 测试连阿里云

```bash
ssh aliyun hostname
# 应输出阿里云主机名
# 实际执行: ssh -J windows root@8.131.61.234
```

---

## 第五步：完整验证

### 从阿里云连 node3

```bash
ssh node3 hostname
# 路径: 阿里云 → localhost:2201 → 反向隧道 → node3:5122
```

### 从 node3 连阿里云

```bash
ssh aliyun hostname
# 路径: node3 → Windows(跳板) → 阿里云:22
```

### 从 Windows 连任意

```powershell
ssh node3 hostname      # 直连
ssh aliyun hostname     # 直连
```

---

## 第六步：开机自启总结

| 服务器 | 需要自启的服务 | 配置方式 |
|--------|---------------|----------|
| **Windows** | `Tunnel-Aliyun-Node3` | Windows Service（已完成） |
| **Windows** | OpenSSH Server | 已设为 Automatic |
| **阿里云** | 无 | 被动接收隧道 |
| **node3** | 无 | 被动被连，主动通过 ProxyJump |

---

## 完整连接关系图

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  阿里云 (8.131.61.234:22)                                   │
│  ├─ ssh node3 → localhost:2201 → 隧道 → node3             │
│  └─ ~/.ssh/config: Host node3 (localhost:2201)              │
│                                                             │
│        ↑ 反向隧道 :2201                                     │
│        │ (Windows服务 Tunnel-Aliyun-Node3)                  │
│        │                                                    │
│  Windows (10.16.73.249)                                     │
│  ├─ OpenSSH Server (端口22, node3跳板用)                    │
│  ├─ Windows服务: Tunnel-Aliyun-Node3 (自动启动)              │
│  └─ 开机自启: ✓                                            │
│        │                                                    │
│        ↓ ProxyJump                                          │
│                                                             │
│  node3 (10.16.82.202:5122)                                  │
│  ├─ ssh aliyun → -J windows → 阿里云                       │
│  └─ ~/.ssh/config: Host aliyun (ProxyJump windows)          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 常见问题

### Q: 重启 Windows 后隧道还在吗？

A: 在。`Tunnel-Aliyun-Node3` 是 Windows 服务，设为自动启动。重启后自动运行。

### Q: 隧道断了会怎样？

A: 脚本里有 `while` 循环，断开后等10秒自动重连。服务恢复策略配置了失败后自动重启。

### Q: 阿里云上 ssh node3 超时？

A: 检查 Windows 上 `sc query Tunnel-Aliyun-Node3` 是否运行。检查 Windows 能否连 node3。

### Q: node3 上 ssh aliyun 超时？

A: 检查 Windows SSH 服务端是否运行：`Get-Service sshd`。检查 node3 能否连 Windows：`ssh windows hostname`。

### Q: 校园网封了 node3 出站 22，为啥 ProxyJump 能通？

A: ProxyJump 是 node3 连 Windows(同校园网)，然后 Windows 连阿里云。node3 只跟 Windows 通信，不直接跟外网通信。
