# Tunnel Mesh — 项目文件地图

## 入口

```
tunnel-mesh.sh         主入口 (Bash)
tunnel-mesh.bat        Windows 启动器 → tunnel-mesh.ps1
tunnel-mesh.ps1        Windows PowerShell 实现
```

## 核心脚本 `scripts/`

```
phase1-key.sh          加密信任 — 密钥生成/身份卡/部署/批量导入
phase2-edge.sh         网络信任 — 经典单跳建边 + 可达报告驱动建边
phase2-recursive.sh    网络信任 — 递归建边（含 fabric 输出）
phase3-tunnel.sh       维持信任 — Fabric 管理中心
ssh-config.sh          SSH config 管理工具
graph.py               Dijkstra 图引擎 (Python)
migrate-v3.sh          数据迁移 v2 → v3
register-tunnel.ps1    Windows 隧道注册 (PowerShell)
```

## 库 `scripts/lib/`

```
config.sh              config.json 读写 + 端口池 + 边操作
detect.sh              本机身份检测 + 身份卡解析
fabric.sh              fabric.json shell 封装
_fabric_op.py          fabric.json Python 引擎
graph.sh               路径探寻 + ProxyJump + 链式 SSH + 拓扑
_json_op.py            config.json Python 引擎
network.sh             TCP 可达性检测 + 中间节点推荐
reachability.sh        网络可达探测引擎 + 部署指南
_reachability.py       可达报告合并 + 边类型推荐 + 部署指南生成
tunnel-builder.sh      ssh -L / ssh -R 命令生成 + 健康检查
```

## 数据文件 `~/.tunnel-mesh/`

```
config.json            逻辑图 — servers + edges
fabric.json            物理连接层 — hops + transit_nodes + maintainers
config.json.bak.*      自动备份（保留最近 5 个）
```

## 文档 `docs/`

```
ARCHITECTURE.md        双层架构设计
```

## 工程文件

```
README.md              项目说明
FILES.md               本文件
LICENSE                MIT
CHANGELOG.md           版本变更
.gitignore             Git 忽略规则
install.sh             安装脚本
```
