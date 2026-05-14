# Windows 双向隧道配置指南

## 目标

建立稳定的双向连接：
- 阿里云 (YOUR_JUMP_SERVER_IP) ←→ node3 (YOUR_TARGET_IP:22)
- 通过 Windows 作为跳板
- 开机自启动

---

## 网络拓扑

```
阿里云 (YOUR_JUMP_SERVER_IP)
    ↑↓
    │ 反向隧道 (端口 2224)
    │
Windows (YOUR_WINDOWS_IP)
    │
    │ Windows 运行 SSH 隧道
    │
node3 (YOUR_TARGET_IP:22)
```

---

## 方案 1：手动启动（快速）

### 在 Windows 上执行

```powershell
# 建立反向隧道：阿里云:2224 → node3:22
ssh -i C:\Users\wilia\.ssh\id_aliyun `
    -R 2224:YOUR_TARGET_IP:22 `
    -o StrictHostKeyChecking=no `
    -o ServerAliveInterval=60 `
    -o ServerAliveCountMax=3 `
    -N root@YOUR_JUMP_SERVER_IP
```

### 验证

在阿里云上：
```bash
ssh -p 2224 wuxiaoran@localhost
```

---

## 方案 2：开机自启动（推荐）

### 步骤 1：下载脚本

将 `windows-tunnel-setup.py` 复制到 Windows：
```
C:\tunnel-mesh\windows-tunnel-setup.py
```

### 步骤 2：修改配置

编辑脚本中的配置部分：

```python
CONFIG = {
    "aliyun": {
        "host": "YOUR_JUMP_SERVER_IP",
        "user": "root",
        "key": "C:\\Users\\wilia\\.ssh\\id_aliyun",
    },
    "tunnels": {
        "reverse": {
            "remote_port": 2224,
            "target_host": "YOUR_TARGET_IP",
            "target_port": 5122,
        },
    },
}
```

### 步骤 3：安装服务

```powershell
# 管理员权限运行
python C:\tunnel-mesh\windows-tunnel-setup.py install
```

### 步骤 4：启动服务

```powershell
net start tunnel-mesh
```

---

## 方案 3：使用 Windows 任务计划

### 步骤 1：创建启动脚本

保存为 `C:\tunnel-mesh\start-tunnel.ps1`：

```powershell
# 启动反向隧道
Start-Process -FilePath "ssh" -ArgumentList @(
    "-i", "C:\Users\wilia\.ssh\id_aliyun",
    "-R", "2224:YOUR_TARGET_IP:22",
    "-o", "StrictHostKeyChecking=no",
    "-o", "ServerAliveInterval=60",
    "-o", "ServerAliveCountMax=3",
    "-N",
    "root@YOUR_JUMP_SERVER_IP"
) -WindowStyle Hidden
```

### 步骤 2：创建任务计划

```powershell
# 创建开机自启动任务
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\tunnel-mesh\start-tunnel.ps1"

$trigger = New-ScheduledTaskTrigger -AtStartup

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask -TaskName "TunnelMesh" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -RunLevel Highest
```

---

## 验证连接

### 阿里云 → node3

```bash
# 在阿里云上
ssh -p 2224 wuxiaoran@localhost
```

### node3 → 阿里云

```bash
# 在 node3 上（直连公网）
ssh root@YOUR_JUMP_SERVER_IP

# 或通过隧道
ssh -p 2223 root@localhost
```

---

## 常见问题

### Q: 隧道断开怎么办？

A: 使用 `ServerAliveInterval=60` 保持连接，断开后自动重连

### Q: Windows 重启后隧道不自动启动？

A: 使用任务计划或 Windows Service

### Q: 如何查看隧道状态？

```powershell
# 检查 SSH 进程
tasklist /FI "IMAGENAME eq ssh.exe"

# 检查端口
netstat -an | findstr "2224"
```

---

## 命令速查

| 操作 | 命令 |
|------|------|
| 启动隧道 | `net start tunnel-mesh` |
| 停止隧道 | `net stop tunnel-mesh` |
| 查看状态 | `sc query tunnel-mesh` |
| 手动启动 | `python windows-tunnel-setup.py start` |
| 手动停止 | `python windows-tunnel-setup.py stop` |
