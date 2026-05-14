# 反向隧道服务体系

## 架构概述

```
跳板服务器 (公网 IP)
├── 监听端口 2201-2299
├── 每个端口对应一个内网服务器
└── 内网服务器主动连接跳板

示例：
跳板: YOUR_JUMP_SERVER_IP
├── 端口 2201 → node3 (内网)
├── 端口 2202 → windows (内网)
└── 端口 2203 → server-x (内网)
```

---

## 端口分配规范

| 端口范围 | 用途 |
|----------|------|
| 2201-2210 | Linux 服务器 |
| 2211-2220 | Windows 服务器 |
| 2221-2299 | 预留 |

---

## Linux 客户端配置

### 依赖

```bash
apt install autossh
```

### 安装服务

```bash
python3 linux-tunnel-service.py install \
  --target node3 \
  --jump-ip YOUR_JUMP_SERVER_IP \
  --local-port 2201
```

### 生成的 systemd 服务

```ini
[Unit]
Description=SSH Tunnel to node3
After=network-online.target

[Service]
Type=simple
User=wuxiaoran
Environment="AUTOSSH_GATETIME=0"
ExecStart=/usr/bin/autossh -M 0 -N \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -R 2201:localhost:22 \
  root@YOUR_JUMP_SERVER_IP
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## Windows 客户端配置

### 编码问题处理

Windows PowerShell 默认使用 GBK 编码，需要设置 UTF-8：

```powershell
chcp 65001
[Console]::OutputEncoding = [System.Text.Encoding]::UTF-8
```

### 安装服务

```powershell
python windows-tunnel-service.py install `
  --target windows `
  --jump-ip YOUR_JUMP_SERVER_IP `
  --local-port 2202
```

### 生成的 PowerShell 脚本

脚本自动处理：
1. UTF-8 编码设置
2. 服务创建 (sc.exe)
3. 自动启动配置
4. 失败重启策略

---

## 密钥管理

### 生成专用密钥

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_tunnel_node3 -N "" -C "tunnel-node3"
```

### 部署公钥到跳板

```bash
ssh-copy-id -i ~/.ssh/id_tunnel_node3.pub root@YOUR_JUMP_SERVER_IP
```

### 密钥权限

```bash
chmod 600 ~/.ssh/id_tunnel_*
chmod 644 ~/.ssh/id_tunnel_*.pub
```

---

## 故障排查

### 隧道不通

1. 检查服务状态
   ```bash
   systemctl status tunnel-node3
   ```

2. 检查端口监听
   ```bash
   ss -tlnp | grep 2201
   ```

3. 检查 SSH 连接
   ```bash
   ssh -v -p 2201 user@jump-server
   ```

### Windows 编码问题

1. 确认 PowerShell 使用 UTF-8
2. 检查脚本文件编码（应为 UTF-8 without BOM）
3. 使用 `chcp 65001` 切换编码

### 自动重连失败

检查 autossh 参数：
- `ServerAliveInterval=30`：每 30 秒发送心跳
- `ServerAliveCountMax=3`：3 次失败后断开
- `ExitOnForwardFailure=yes`：端口占用时退出重试