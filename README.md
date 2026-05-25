# Tunnel Mesh

> 几台分散在各处的服务器，自动算出最优连接路径，通过 SSH 隧道彼此连通。
> 支持 NAT/防火墙穿透、多跳链式跳转、ProxyJump 中转，一键部署为持久化 systemd 服务。

## 安装

```bash
# 在线安装
curl -fsSL https://raw.githubusercontent.com/wilianyichen/tunnel-mesh/main/install.sh | bash

# 或手动克隆
git clone https://github.com/wilianyichen/tunnel-mesh.git ~/tunnel-mesh
cd ~/tunnel-mesh && bash tunnel-mesh.sh
```

**依赖**: `python3`, `ssh`, `bash 4+`（Linux/macOS/Windows Git Bash）

## 60 秒快速开始

以下是一个三节点组网场景：**node3**（内网）↔ **aliyun**（公网）↔ **windows**（内网）。

```bash
# 1. 每台机器生成"身份卡"（SSH 公钥 + 元信息）
tunnel-mesh --cmd identity          # 查看当前节点名
# 进入交互菜单 → [1] 加密信任 → [1] 生成密钥
# 复制输出的 ===IDENTITY v1=== 块

# 2. 收集身份卡到主控机器，批量导入
cat node3.card aliyun.card windows.card | tunnel-mesh --cmd import
# ✓ 导入完成

# 3. 每台机器运行网络可达探测
tunnel-mesh --cmd reachability --ports 22,80,443,8080 > node3-reach.json
# 三台机器各自运行，收集 JSON 报告到一处

# 4. 合并报告 → 查看可达矩阵 + 推荐连接方案
tunnel-mesh --cmd reachability-merge node3-reach.json aliyun-reach.json windows-reach.json
# 输出: N×N 可达矩阵、正向直连、反向隧道、ProxyJump 候选

# 5. 一键部署
tunnel-mesh --cmd apply --dry-run   # 预览
tunnel-mesh --cmd apply --yes       # 执行

# 6. 日常使用
ssh node3 hostname                  # 直接连
tunnel-mesh --cmd status            # 查看隧道状态
tunnel-mesh --cmd health            # 健康检查
```

## 核心原理

工具通过 TCP 多端口并行探测，摸清 N 台机器之间的真实网络可达情况，然后自动决策每条连接的最优方案：

| 场景 | 判定条件 | 方案 | 示例 |
|------|---------|------|------|
| 正向直连 | A 可达 B 任一端口 | `ssh B` | `ssh aliyun` |
| 端口切换 | 默认端口 22 被封，其他端口通 | `ssh -p 80 B` | `ssh -p 8080 aliyun` |
| 反向隧道 | B 完全不可达 A，但 A 可达 B | A 维持 `ssh -R` | node3 在 aliyun 上开端口 |
| ProxyJump | 双方互不通，但有公共中转 | `ssh -J C B` | `ssh -J aliyun windows` |
| 链式多跳 | 需经多台中转节点 | 递归建边 | `master→I1→I2→servant` |

**端口池**: 2201-2299，自动分配，冲突检测。

## 命令参考

| 命令 | 说明 |
|------|------|
| `server-list` | 列出所有服务器 |
| `server-add <name> <ip> [port] [user]` | 添加服务器 |
| `server-exists <name>` | 检查服务器是否存在 |
| `server-remove <name>` | 删除服务器 |
| `edge-list` | 列出所有边 |
| `edge-add <from> <to> <type> [port] [cmd] [maintainer]` | 添加边 |
| `edge-remove <id>` | 删除边 |
| `reachability [--ports a,b,c]` | 多端口并行 TCP 可达探测 |
| `reachability-merge <report.json>...` | 合并多机报告，输出推荐边 |
| `deploy-guide <report.json>...` | 按机器生成部署指南 |
| `discover [--ports ...]` | 自动拓扑探测，生成边类型建议 |
| `quickstart [--non-interactive] [--yes]` | 引导式一键配置 |
| `ensure <server\|edge\|key> ...` | 幂等操作，可安全重复执行 |
| `apply [--dry-run\|--yes]` | 部署隧道（systemd + SSH config） |
| `key-deploy <server> [--key <path>]` | 部署公钥到目标服务器 |
| `deploy-windows <server>` | 部署到 Windows（推送脚本 + Scheduled Task） |
| `status` | 查看所有隧道运行状态 |
| `health` | 健康检查（存活/断开） |
| `viz` | ASCII 逻辑拓扑图 |
| `fabric-viz` | 物理拓扑图 |
| `path <from> <to>` | 查询最短路径 |
| `port-allocate` | 分配下一个可用端口 |
| `port-is-free <port>` | 检查端口是否可用 |
| `tutorial` | 生成部署教程 markdown |
| `identity` | 显示当前节点名 |
| `identity-import [card_text]` | 导入身份卡 |
| `import` | 从 stdin 批量导入身份卡 |
| `upgrade` | 从 GitHub 拉取最新版本 |

## Agent 模式（--json）

所有命令支持 `--json` 输出，统一 schema，适合脚本和 AI agent 调用：

```bash
# 查询
tunnel_mesh.py server-list --json     # {"status":"ok","data":{"servers":{...}}}
tunnel_mesh.py server-exists aliyun --json  # {"status":"ok","data":{"exists":true}}
tunnel_mesh.py discover --json        # {"status":"ok","data":{"suggestions":[...]}}

# 幂等操作（agent 首选，可安全重复）
tunnel_mesh.py ensure server aliyun 8.131.61.234 --json  # 已存在则 noop
tunnel_mesh.py ensure edge a b forward 2224 "ssh ..." --json
tunnel_mesh.py ensure key aliyun --json

# 一键部署
tunnel_mesh.py quickstart --non-interactive --yes --json

# 非 TTY 自动 JSON（管道/脚本无需显式 --json）
echo "" | tunnel_mesh.py server-list   # 自动输出 JSON
tunnel_mesh.py server-list --no-json  # 显式人类可读
```

错误统一输出到 stderr：`{"status":"error","error":"<消息>"}`

## 非交互模式

所有命令均支持非 TTY 调用，适合脚本和 `ssh remote '...'` 远程执行：

```bash
# 远程探测（无需登录交互式菜单）
ssh node3 'tunnel-mesh reachability > node3-reach.json'

# 裸命令自动转为 --cmd 模式
ssh aliyun 'tunnel-mesh server-list'
# 等价于: ssh aliyun 'tunnel-mesh --cmd server-list'

# 管道输入
echo '{"servers":{...}}' | tunnel-mesh --cmd import
```

非 TTY 无参数时打印帮助并 exit 0，不会卡在 `read -p`。

## 架构

双层设计：**逻辑图**（谁要连谁）+ **物理连接层**（怎么连过去）。

```
config.json（逻辑图）            fabric.json（物理连接层）
┌────────────────────┐          ┌─────────────────────────┐
│ servers: 登录目标  │          │ hops: [每跳 ssh -L/-R]  │
│ edges: [{          │ ──────→ │ transit_nodes: 中转节点  │
│   from, to, type,  │          │ maintainers: [维持者]    │
│   fabric_id, weight│          │ external_maintainers: [] │
│ }]                 │          └─────────────────────────┘
│ ports: 端口池      │
└────────────────────┘
```

- **config.json** 的 `servers` 只存登录目标，中转节点隔离在 fabric.json
- **边** 含 `weight` 字段（forward=1.0, reverse=1.5），供 Dijkstra 最短路径算法
- **fabric.json** 记录每一条逻辑边对应的物理跳序列、维持者、持久化方式

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 文档

| 文档 | 内容 |
|------|------|
| [文件地图](FILES.md) | 全部文件清单 |
| [架构设计](docs/ARCHITECTURE.md) | 双层架构详解 |

## 贡献

Bug 报告和 PR 欢迎。提交前请确保测试通过：

```bash
python3 tests/test_smoke.py -v
```

## 许可证

MIT © 2026 wilianyichen
