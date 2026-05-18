# Tunnel Mesh 完整操作流程

## 场景

三台服务器：阿里云、Windows、node3。
需要建立阿里云 ↔ node3 双向稳定连接。

---

## 三步操作

### 第一步：Windows 安装 (5分钟)

```powershell
# 1. 打开 PowerShell（管理员）
# 2. 运行安装脚本
PowerShell -ExecutionPolicy Bypass -File windows-auto-setup.ps1
```

**脚本自动完成**：
- 生成两个隧道脚本 (tunnel-1.ps1, tunnel-2.ps1)
- 注册 Windows 计划任务（开机自启 + 断线重连）
- 立即启动隧道

**安装后 Windows 上会多两个计划任务**：
```
Tunnel-1-Aliyun-Node3    → 阿里云:2201 → node3:5122
Tunnel-2-Node3-Aliyun    → node3:2223 → 阿里云:22
```

---

### 第二步：阿里云配置 (1分钟)

```bash
# 复制 linux-setup-ssh-config.sh 到阿里云
# 或直接添加 SSH config：

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
```

**验证**：
```bash
ssh node3 hostname
# 输出: node3
```

---

### 第三步：node3 配置 (1分钟)

```bash
# 或直接添加 SSH config：

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
```

**验证**：
```bash
ssh aliyun hostname
# 输出: 阿里云主机名
```

---

## 完成后的连接方式

```
阿里云上:
  ssh node3         → 通过隧道1 (localhost:2201)

node3上:
  ssh aliyun        → 通过隧道2 (localhost:2223)

Windows上:
  ssh node3         → 正向，直连
  ssh aliyun        → 正向，直连
```

---

## 日常管理

### Windows 契约大厅

```
双击桌面「契约大厅」→

  [2] 审视契约  → 查看所有隧道状态
  [3] 契约之仪  → 启动所有隧道
  [4] 解除契约  → 停止所有隧道
  [7] 测试连通  → 快速测试连接
```

### Windows PowerShell 命令

```powershell
# 查看隧道状态
Get-ScheduledTask -TaskName "Tunnel-1*","Tunnel-2*" | Select TaskName, State

# 手动启动
Start-ScheduledTask -TaskName "Tunnel-1-Aliyun-Node3"

# 手动停止
Stop-ScheduledTask -TaskName "Tunnel-2-Node3-Aliyun"

# 运行日志
Get-Content C:\tunnel-mesh\logs\tunnel-1.log -Tail 20
```

---

## 开机自启验证

```powershell
# 重启后检查
Get-ScheduledTask -TaskName "Tunnel-1*","Tunnel-2*" | Select TaskName, State
# 应显示: Running
```
