# Tunnel Mesh

> 几台分散在各处的 Linux 服务器，自动算出最短路径，通过 SSH 隧道彼此连接。

## 安装

```bash
# 方式 1: 一键安装
curl -sSL https://raw.githubusercontent.com/wilianyichen/tunnel-mesh/main/install.sh | bash

# 方式 2: 手动
git clone https://github.com/wilianyichen/tunnel-mesh.git
cd tunnel-mesh && bash tunnel-mesh.sh
```

**依赖**: `python3`, `ssh`（系统自带）, `bash 4+`

## 30 秒快速开始

```bash
# 1. 在服务器 A 上生成密钥，获取"身份卡"
bash tunnel-mesh.sh
→ [1] 建立加密信任 → [1] 生成密钥 + 导出身份卡
# 复制输出的身份卡

# 2. 在服务器 B 上部署 A 的公钥
bash tunnel-mesh.sh
→ [1] 建立加密信任 → [2] 部署公钥
# 粘贴 A 的身份卡

# 3. 回到 A，建立连接
→ [2] 建立网络信任 → [2] 递归建边
# 主=本机, 仆=B, 自动检测网络方向，按提示操作

# 4. 连接
ssh B hostname
```

## 核心概念

```
config.json（逻辑图）          fabric.json（物理连接层）
┌──────────────────┐          ┌─────────────────────────┐
│ servers: 登录目标 │          │ hops: [每跳 ssh -L/-R]  │
│ edges: [{         │ ────→   │ transit_nodes: 中转服务器 │
│   fabric_id ──────┤          │ maintainers: [维持者]    │
│   weight          │          └─────────────────────────┘
│ }]                │
└──────────────────┘
```

- **逻辑边**: 主→仆的"可达关系"，含 Dijkstra 权重
- **物理跳**: 每条逻辑边分解为若干 `ssh -L` / `ssh -R` 跳
- **中转节点**: 不在逻辑图中，只存在于物理连接层
- **统一端口**: 整条链路共用同一个端口号，每跳 `上一跳的 localhost:P → 下一跳:22`

## 5 个 Phase

| Phase | 功能 | 说明 |
|-------|------|------|
| 1. 建立加密信任 | 生成密钥 + 交换身份卡 | SSH key pair + SHA256 校验 |
| 2. 建立网络信任 | 递归建边 | 从主出发，沿网络可达方向递归直到触达仆 |
| 3. 维持信任 | Fabric 管理中心 | 查看/启停隧道、健康检查、生成部署指南 |
| 4. 审视信任 | 双层拓扑 + 路径探寻 | 逻辑图 + 物理图；ProxyJump / 嵌套 SSH |
| 5. 撤销信任 | 删边 + 释放端口 | 自动清理 SSH config、fabric 和端口池 |

## 三种典型场景

### 场景 1: 双方都能互连（最简单）
```
master ────直连──→ servant
```
正向边，权重 1.0。生成标准 SSH config。

### 场景 2: 一方能连另一方（反向隧道）
```
master ←──ssh -R── servant（运行隧道）
```
servant 运行 `ssh -R` 在 master 上打开端口。

### 场景 3: 双方不能互连，引入中间节点
```
master ←──ssh -R── Windows ──ssh -L──→ servant
         (跳1)              (跳2)
```
Windows 同时维持两条隧道，master 通过 ProxyCommand 链式到达 servant。

## 文档

| 文档 | 内容 |
|------|------|
| [文件地图](FILES.md) | 全部文件清单 |
| [架构设计](docs/ARCHITECTURE.md) | 双层架构详解 |

## 贡献

Bug 报告和 PR 欢迎。提交前请确保 `shellcheck` 通过。

## 许可证

MIT © 2026 wilianyichen
