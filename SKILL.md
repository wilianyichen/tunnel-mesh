---
name: tunnel-mesh
title: Tunnel Mesh - 反向隧道管理系统
description: 管理服务器网络拓扑和反向隧道，支持 Windows/Linux 双平台，一键配置，小白友好。
author: Hermes
version: 1.0.0
triggers:
  - 反向隧道
  - SSH 隧道
  - 内网穿透
  - 隧道管理
  - tunnel mesh
---

# Tunnel Mesh

## 目标

帮助用户建立服务器之间的反向隧道连接，支持：
- Windows 批量管理隧道服务
- Linux 一键导出配置
- 小白友好的图形化菜单

---

## 核心功能

### 1. 配置导出（Linux 端）

```bash
# 在被连接服务器上运行
bash linux-export-config.sh
```

输出固定格式的配置文本，包含：
- 服务器名称、IP、端口
- 中转服务器信息
- SSH 公钥

### 2. 配置导入（Windows 端）

```batch
# 在 Windows 上运行
windows-menu.bat
# 选择 [5] 导入配置
# 粘贴配置文本
```

自动解析并创建隧道。

### 3. 批量管理

```batch
# 查看状态
windows-menu.bat → [1]

# 启动所有隧道
windows-menu.bat → [3]

# 停止所有隧道
windows-menu.bat → [4]
```

---

## 使用流程

```
┌─────────────────────────────────────────────────────────────┐
│                    完整使用流程                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Linux 服务器（被连接端）                                    │
│  ─────────────────────                                      │
│  1. 运行 linux-export-config.sh                             │
│  2. 复制输出的配置文本                                       │
│                                                             │
│                         ↓ 复制                              │
│                                                             │
│  Windows 电脑（连接端）                                      │
│  ─────────────────────                                      │
│  1. 双击 Tunnel Mesh 图标                                   │
│  2. 选择 [5] 导入配置                                       │
│  3. 粘贴配置文本                                            │
│  4. 选择 [3] 启动所有隧道                                   │
│                                                             │
│                         ↓ 完成                              │
│                                                             │
│  连接命令: ssh -p 2201 user@中转IP                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 文件说明

| 文件 | 用途 | 平台 |
|------|------|------|
| `windows-install.bat` | 一键安装 | Windows |
| `windows-menu.bat` | 图形化菜单 | Windows |
| `linux-export-config.sh` | 配置导出 | Linux |
| `scripts/parse-config.py` | 配置解析 | Windows |
| `scripts/windows-tunnel-batch.py` | 批量管理 | Windows |

---

## 配置文本格式

```
===TUNNEL_CONFIG_START===
SERVER_NAME=node3
SERVER_IP=192.168.1.100
SERVER_PORT=22
RELAY_NAME=aliyun
RELAY_IP=1.2.3.4
RELAY_PORT=22
RELAY_USER=root
PUB_KEY=ssh-ed25519 AAAA...
===TUNNEL_CONFIG_END===
```

---

## 常见问题处理

### 问题 1：Windows 编码错误

**原因**：Windows 默认使用 GBK 编码

**解决**：所有 .bat 文件开头添加 `chcp 65001 >nul`

### 问题 2：SSH 连接失败

**检查**：
1. 中转服务器 SSH 是否开放
2. 防火墙是否放行
3. 密钥是否正确

### 问题 3：服务无法启动

**解决**：
```batch
# 检查服务状态
sc query Tunnel-node3

# 手动启动
net start Tunnel-node3
```

---

## 端口分配规则

默认范围：2201-2299

按添加顺序自动分配：
- 第 1 个隧道：2201
- 第 2 个隧道：2202
- ...

---

## 安全注意事项

1. **不要在代码中硬编码敏感信息**
2. **配置文本中不要包含真实 IP**
3. **使用模板变量**：`YOUR_SERVER_IP`、`YOUR_API_KEY`
4. **推送前检查**：`grep -rE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`

---

## 命令速查

### Windows

```batch
# 安装
windows-install.bat

# 打开菜单
windows-menu.bat

# 命令行方式
python tunnel-batch.py init --relay aliyun --ip 1.2.3.4
python tunnel-batch.py add --name node3 --target 192.168.1.100:22
python tunnel-batch.py install-all
python tunnel-batch.py start-all
python tunnel-batch.py status
```

### Linux

```bash
# 导出配置
bash linux-export-config.sh

# 一键运行
curl -sSL URL | bash
```
