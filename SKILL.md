---
name: tunnel-mesh
title: Tunnel Mesh - 反向隧道管理系统
description: 让服务器连接变得简单。支持平等契约（双向直连）和主仆契约（单向中转），Windows/Linux 双平台。
author: Hermes
version: 2.0.0
triggers:
  - 连接服务器
  - SSH
  - 反向隧道
  - 内网穿透
  - 契约
---

# Tunnel Mesh

## 核心概念

### 契约类型

| 契约 | 方向 | 条件 | 操作 |
|------|------|------|------|
| 平等契约 | 双向 | 网络互通 | 双方交换契约文书 |
| 主仆契约 | 单向 | 需中转服务器 | 仆端生成，主端导入 |

### 契约之塔（中转服务器）

有公网IP的服务器，双方都能SSH连上它。通常是阿里云/腾讯云等 VPS。

---

## 工作流程

### 平等契约

```
双方各自运行导出脚本 → 交换契约文书 → 互相导入 → 完成
```

### 主仆契约

```
仆端运行 linux-export-config.sh → 生成契约文书
主端运行 windows-menu.bat → [1]缔结新契约 → 粘贴
→ [3]契约之仪 → 完成
```

---

## 文本格式

```
===CONTRACT_START===
CONTRACT_TYPE=2
SERVER_NAME=node3
SERVER_IP=192.168.1.100
SERVER_PORT=22
RELAY_NAME=aliyun
RELAY_IP=1.2.3.4
RELAY_PORT=22
RELAY_USER=root
PUB_KEY=ssh-ed25519 AAAA...
===CONTRACT_END===
```

---

## 字段说明

| 字段 | 说明 | 示例 |
|------|------|------|
| CONTRACT_TYPE | 1=平等 2=主仆 | 2 |
| SERVER_NAME | 对方服务器名字 | node3 |
| SERVER_IP | 对方IP | 192.168.1.100 |
| SERVER_PORT | 对方SSH端口 | 22 |
| RELAY_IP | 中转服务器公网IP | 1.2.3.4 |
| PUB_KEY | SSH公钥 | ssh-ed25519 AAAA... |

---

## 文件清单

| 文件 | 平台 | 用途 |
|------|------|------|
| `linux-export-config.sh` | Linux | 契约文书生成 |
| `windows-export-config.bat` | Windows | 契约文书生成 |
| `windows-menu.bat` | Windows | 契约大厅（管理界面） |
| `windows-install.bat` | Windows | 一键安装 |
| `scripts/parse-contract.py` | Windows | 契约解析 |
| `scripts/windows-tunnel-batch.py` | Windows | 批量隧道管理 |
