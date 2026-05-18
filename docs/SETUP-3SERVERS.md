# 三服务器双向连接完整操作流程

## 网络拓扑

```
阿里云 (8.131.61.234:22)         Windows (10.16.73.249)         node3 (10.16.82.202:5122)
      公网 VPS                      校园网·你的电脑                    校园内网·实验室服务器
      
      出站: 不受限                   出站: 不受限                      出站: 仅80端口
      能连: Windows                 能连: 阿里云 + node3              能连: Windows + 校园网
      不能连: node3                 不能连: (无)                      不能连: 阿里云(22端口被封)
```

**核心问题**：阿里云和 node3 不能互连，但都能连 Windows。Windows 做桥梁。

---

## 可达性矩阵

```
           Windows        阿里云         node3
           (10.16.73)    (8.131.61)    (10.16.82)

Windows      -            ✓              ✓
阿里云       ✓            -              ✗
node3       ✓            ✗              -
```

---

## 方案：Windows 维持两个反向隧道

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  阿里云 (8.131.61.234:22)                                        │
│  │                                                               │
│  │ 隧道1（反向）  :2201                                           │
│  │ Windows → ssh -R 2201:10.16.82.202:5122 root@8.131.61.234    │
│  │ 阿里云监听 :2201，流量转发到 node3:5122                         │
│  │                                                               │
│  │ ssh -p 2201 wuxiaoran@localhost  ──→  node3                  │
│  │                                                               │
│  Windows (10.16.73.249)                                          │
│  │ 不装 SSH 服务端，只当隧道维持者                                  │
│  │                                                               │
│  │ 隧道2（反向）  :2223                                           │
│  │ Windows → ssh -R 2223:8.131.61.234:22 wuxiaoran@10.16.82.202 │
│  │      -p 5122                                                  │
│  │ node3 监听 :2223，流量回到 Windows，Windows 转发到 阿里云:22    │
│  │                                                               │
│  node3 (10.16.82.202:5122)                                       │
│  │                                                               │
│  │ ssh -p 2223 root@localhost  ──→  阿里云                       │
│  │                                                               │
└──────────────────────────────────────────────────────────────────┘
```

**两个隧道都由 Windows 发起和维持。不需要在 Windows 上装 SSH 服务端。**

---

## 第一步：Windows 前置条件

### 1.1 检查 OpenSSH 客户端

```powershell
ssh -V
# Win10 自带，有版本号输出即可
```

### 1.2 生成两把 SSH 密钥

```powershell
# 连接阿里云用的
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_aliyun -C "windows-to-aliyun"

# 连接 node3 用的
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_node3 -C "windows-to-node3"
```

### 1.3 部署公钥

```powershell
# 部署到阿里云
type $env:USERPROFILE\.ssh\id_aliyun.pub | ssh root@8.131.61.234 "cat >> ~/.ssh/authorized_keys"

# 部署到 node3
type $env:USERPROFILE\.ssh\id_node3.pub | ssh -p 5122 wuxiaoran@10.16.82.202 "cat >> ~/.ssh/authorized_keys"
```

### 1.4 测试直连

```powershell
ssh -i $env:USERPROFILE\.ssh\id_aliyun root@8.131.61.234 hostname
# 应输出阿里云主机名

ssh -i $env:USERPROFILE\.ssh\id_node3 -p 5122 wuxiaoran@10.16.82.202 hostname
# 应输出 node3 主机名
```

---

## 第二步：Windows 隧道脚本

### 2.1 创建目录

```powershell
mkdir C:\tunnel-mesh\scripts -Force
mkdir C:\tunnel-mesh\logs -Force
```

### 2.2 隧道脚本 1：阿里云 → node3

创建 `C:\tunnel-mesh\scripts\tunnel-1.ps1`：

```powershell
# 隧道1：阿里云:2201 → node3:5122
# 阿里云上执行: ssh -p 2201 wuxiaoran@localhost

while ($true) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [隧道1] 启动..."

    ssh -i $env:USERPROFILE\.ssh\id_aliyun `
        -R 2201:10.16.82.202:5122 `
        -o StrictHostKeyChecking=no `
        -o ServerAliveInterval=60 `
        -o ServerAliveCountMax=3 `
        -o ExitOnForwardFailure=yes `
        -N root@8.131.61.234

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [隧道1] 断开，10秒后重连..."
    Start-Sleep 10
}
```

### 2.3 隧道脚本 2：node3 → 阿里云

创建 `C:\tunnel-mesh\scripts\tunnel-2.ps1`：

```powershell
# 隧道2：node3:2223 → 阿里云:22
# node3 上执行: ssh -p 2223 root@localhost

while ($true) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [隧道2] 启动..."

    ssh -i $env:USERPROFILE\.ssh\id_node3 `
        -R 2223:8.131.61.234:22 `
        -o StrictHostKeyChecking=no `
        -o ServerAliveInterval=60 `
        -o ServerAliveCountMax=3 `
        -o ExitOnForwardFailure=yes `
        -N wuxiaoran@10.16.82.202 -p 5122

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [隧道2] 断开，10秒后重连..."
    Start-Sleep 10
}
```

**隧道1和隧道2的关键区别**：

| 隧道 | 连到哪个服务器 | 远程监听端口 | 转发目标 |
|------|-------------|-----------|---------|
| 隧道1 | 阿里云 (:22) | 2201 | node3:5122 |
| 隧道2 | node3 (:5122) | 2223 | 阿里云:22 |

---

## 第三步：注册 Windows 服务（开机自启）

```powershell
# 管理员 PowerShell

# 服务1
sc.exe create "Tunnel-1-Aliyun-Node3" `
    binPath= "powershell.exe -ExecutionPolicy Bypass -File C:\tunnel-mesh\scripts\tunnel-1.ps1" `
    start= auto `
    DisplayName= "Tunnel Mesh 1 - Aliyun to Node3"

sc.exe failure "Tunnel-1-Aliyun-Node3" reset= 86400 actions= restart/10000/restart/10000/restart/10000

# 服务2
sc.exe create "Tunnel-2-Node3-Aliyun" `
    binPath= "powershell.exe -ExecutionPolicy Bypass -File C:\tunnel-mesh\scripts\tunnel-2.ps1" `
    start= auto `
    DisplayName= "Tunnel Mesh 2 - Node3 to Aliyun"

sc.exe failure "Tunnel-2-Node3-Aliyun" reset= 86400 actions= restart/10000/restart/10000/restart/10000

# 启动
sc.exe start "Tunnel-1-Aliyun-Node3"
sc.exe start "Tunnel-2-Node3-Aliyun"
```

---

## 第四步：阿里云配置

```bash
mkdir -p ~/.ssh

cat >> ~/.ssh/config << 'EOF'

# node3（通过 Windows 反向隧道 2201）
Host node3
    HostName localhost
    Port 2201
    User wuxiaoran
    IdentityFile ~/.ssh/id_node3
    IdentitiesOnly yes
    StrictHostKeyChecking no
    HostKeyAlias node3
EOF

chmod 600 ~/.ssh/config
```

---

## 第五步：node3 配置

```bash
mkdir -p ~/.ssh

cat >> ~/.ssh/config << 'EOF'

# 阿里云（通过 Windows 反向隧道 2223）
Host aliyun
    HostName localhost
    Port 2223
    User root
    IdentityFile ~/.ssh/id_aliyun
    IdentitiesOnly yes
    StrictHostKeyChecking no
    HostKeyAlias aliyun
EOF

chmod 600 ~/.ssh/config
```

**注意**：阿里云和 node3 的配置完全对称，都是连 `localhost`，只是端口不同。

---

## 第六步：验证

### 测试 1：阿里云 → node3

```bash
ssh node3 hostname
# 路径: 阿里云 → localhost:2201 → 隧道1 → node3:5122
# 应输出: node3
```

### 测试 2：node3 → 阿里云

```bash
ssh aliyun hostname
# 路径: node3 → localhost:2223 → 隧道2 → 阿里云:22
# 应输出: 阿里云主机名
```

### 测试 3：Windows 直连

```powershell
ssh node3 hostname      # 正向，直连
ssh aliyun hostname     # 正向，直连
```

---

## 查看隧道状态

```powershell
# 检查两个服务
sc.exe query "Tunnel-1-Aliyun-Node3"
sc.exe query "Tunnel-2-Node3-Aliyun"

# 检查阿里云上的监听端口
ssh root@8.131.61.234 "ss -tlnp | grep 2201"

# 检查 node3 上的监听端口
ssh -p 5122 wuxiaoran@10.16.82.202 "ss -tlnp | grep 2223"
```

---

## 运维命令

```powershell
# 启动
sc.exe start "Tunnel-1-Aliyun-Node3"
sc.exe start "Tunnel-2-Node3-Aliyun"

# 停止
sc.exe stop "Tunnel-1-Aliyun-Node3"
sc.exe stop "Tunnel-2-Node3-Aliyun"

# 重启
sc.exe stop "Tunnel-1-Aliyun-Node3" ; sc.exe start "Tunnel-1-Aliyun-Node3"

# 删除服务
sc.exe delete "Tunnel-1-Aliyun-Node3"
```

---

## 常见问题

### Q: 重启 Windows 后隧道还在吗？

A: 在。两个服务都是 `start= auto`，重启后自动运行。

### Q: 隧道断了会怎样？

A: 脚本有 `while` 循环 + 服务恢复策略。双重保障。

### Q: 阿里云上 `ssh node3` 提示 connection refused？

A: 隧道1没运行。在 Windows 上 `sc start Tunnel-1-Aliyun-Node3`。

### Q: node3 上 `ssh aliyun` 提示 connection refused？

A: 隧道2没运行。在 Windows 上 `sc start Tunnel-2-Node3-Aliyun`。

### Q: 为什么不直接在阿里云和 node3 之间连？

A: 校园网封锁了 node3 的 22 端口出站。阿里云在公网，连不到内网的 node3。必须通过 Windows 中转。
