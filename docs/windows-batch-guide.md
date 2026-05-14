# Windows 批量隧道服务使用指南

## 工具说明

`windows-tunnel-batch.py` 是在 Windows 上批量管理反向隧道服务的工具。

**核心功能**：
- 批量创建隧道服务
- 自动分配端口
- 开机自启动
- 断线自动重连
- 统一管理所有隧道

---

## 快速开始

### 1. 初始化跳板服务器

```powershell
python windows-tunnel-batch.py init --jump aliyun --ip YOUR_JUMP_SERVER_IP --user root --key C:\Users\wilia\.ssh\id_aliyun
```

### 2. 添加隧道

```powershell
# 添加 node3 隧道
python windows-tunnel-batch.py add --name node3 --target YOUR_TARGET_IP:22

# 添加更多隧道
python windows-tunnel-batch.py add --name server2 --target YOUR_SERVER2_IP:22
python windows-tunnel-batch.py add --name server3 --target YOUR_SERVER3_IP:22
```

### 3. 批量安装服务

```powershell
# 安装所有隧道服务
python windows-tunnel-batch.py install-all
```

### 4. 启动服务

```powershell
# 启动所有隧道
python windows-tunnel-batch.py start-all

# 或启动单个
python windows-tunnel-batch.py start --name node3
```

### 5. 查看状态

```powershell
python windows-tunnel-batch.py status
```

---

## 完整命令列表

| 命令 | 说明 |
|------|------|
| `init` | 初始化跳板服务器 |
| `add` | 添加隧道配置 |
| `remove` | 移除隧道 |
| `install-all` | 批量安装所有隧道服务 |
| `install` | 安装单个隧道服务 |
| `start-all` | 批量启动所有隧道 |
| `start` | 启动单个隧道 |
| `stop-all` | 批量停止所有隧道 |
| `stop` | 停止单个隧道 |
| `status` | 查看所有隧道状态 |
| `list` | 列出隧道配置 |
| `export` | 导出 SSH config |

---

## 实际使用示例

### 场景：阿里云 ↔ node3 双向连接

#### 在 Windows 上操作：

```powershell
# 1. 初始化
python windows-tunnel-batch.py init --jump aliyun --ip YOUR_JUMP_SERVER_IP

# 2. 添加 node3 隧道（反向隧道：阿里云访问 node3）
python windows-tunnel-batch.py add --name node3 --target YOUR_TARGET_IP:22

# 3. 安装服务
python windows-tunnel-batch.py install-all

# 4. 启动
python windows-tunnel-batch.py start-all

# 5. 查看状态
python windows-tunnel-batch.py status
```

#### 在阿里云上验证：

```bash
# 通过隧道连接 node3
ssh -p 2201 wuxiaoran@localhost
```

---

## 服务特性

### 自动重连

脚本内置循环重连机制：
- SSH 断开后自动等待 5 秒重连
- 配置 `ServerAliveInterval=60` 保持连接活跃

### 开机自启动

服务配置为 `start= auto`，Windows 启动时自动运行。

### 服务恢复策略

配置了服务失败后的恢复策略：
- 第一次失败：10 秒后重启
- 第二次失败：10 秒后重启
- 第三次失败：10 秒后重启

---

## 配置文件位置

| 文件 | 位置 |
|------|------|
| 隧道配置 | `C:\tunnel-mesh\tunnels.json` |
| 启动脚本 | `C:\tunnel-mesh\scripts\start-{name}.ps1` |

---

## 端口分配规则

默认端口范围：`2201-2299`

按添加顺序自动分配：
- 第一个隧道：2201
- 第二个隧道：2202
- ...

---

## 常见问题

### Q: 服务创建失败？

确保以管理员权限运行 PowerShell。

### Q: SSH 连接失败？

检查密钥路径是否正确，确保密钥已添加到跳板服务器。

### Q: 如何查看服务日志？

```powershell
# 查看服务状态
sc query Tunnel-node3

# 查看事件日志
Get-EventLog -LogName System -Source Service Control Manager -Newest 10
```

### Q: 如何手动重启单个服务？

```powershell
net stop Tunnel-node3
net start Tunnel-node3
```

---

## 与其他工具配合

### 导出 SSH config

```powershell
python windows-tunnel-batch.py export
```

输出可直接添加到 `~/.ssh/config`。

### 在阿里云上使用导出的配置

```bash
# 在阿里云上添加 SSH config
cat >> ~/.ssh/config << 'EOF'
Host node3
    HostName localhost
    Port 2201
    User wuxiaoran
    StrictHostKeyChecking no
EOF

# 直接连接
ssh node3
```