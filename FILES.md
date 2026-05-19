# Tunnel Mesh 文件树

```
tunnel-mesh/
│
├── ★ 用户直接使用（核心）
│   ├── linux-contract.sh              [sh] Linux 通用契约脚本
│   │   · export — 自动检测本机IP/端口/公钥，生成契约文书
│   │   · import — 粘贴对方契约文书，自动配置SSH+公钥
│   │
│   └── windows-contract.bat           [bat] Windows 契约大厅
│       · 导入契约文书，自动创建隧道+开机自启
│       · 查看/启动/停止/删除所有契约
│       · 测试连接，帮助文档
│
├── ★ 辅助脚本（可选使用）
│   ├── linux-export-contract.sh       [sh] Linux 导出（带交互引导）
│   ├── linux-setup-ssh-config.sh      [sh] Linux SSH config 快捷配置
│   ├── linux-install.sh               [sh] Linux 一键安装脚本
│   ├── windows-auto-setup.ps1         [ps1] Windows 一键安装向导
│   ├── windows-contract-hall.bat      [bat] Windows 契约大厅（完整版）
│   ├── windows-install.bat            [bat] Windows 环境安装
│   ├── windows-menu.bat               [bat] Windows 简化菜单（旧版）
│   ├── windows-export-config.bat      [bat] Windows 导出本机配置
│   └── linux-export-config.sh         [sh] Linux 导出配置（旧版）
│
├── ★ 文档
│   ├── README.md                      项目说明
│   ├── DESIGN.md                      设计规范（降秩分析、数据结构）
│   ├── SKILL.md                       Agent 使用文档
│   │
│   └── docs/
│       ├── SETUP-BEGINNER.md          ★ 小白完整指南（三服务器双向连接）
│       ├── SETUP-3SERVERS.md          三服务器详细配置
│       ├── OPERATION.md               日常操作流程
│       ├── TUTORIAL.md                总览
│       ├── TUTORIAL-LINUX.md          Linux 详细教程
│       ├── TUTORIAL-WINDOWS.md        Windows 详细教程
│       ├── windows-batch-guide.md     Windows 批量管理
│       ├── windows-tunnel-guide.md    Windows 隧道配置
│       ├── api-spec.md                API 接口规范
│       ├── connection-matrix.md       连接矩阵设计
│       ├── topology-spec.md           拓扑规范
│       ├── trust-levels.md            信任等级
│       └── reverse-tunnel-system.md   反向隧道体系
│
├── scripts/  底层实现（用户一般不直接使用）
│   ├── parse-contract.py              [py] 契约文书解析引擎
│   ├── parse-config.py                [py] 配置文本解析（旧版）
│   ├── key-manager.py                 [py] SSH密钥管理
│   ├── topology-manager.py            [py] 拓扑图管理
│   ├── graph.py                       [py] 图算法（Dijkstra路径规划）
│   ├── tunnel.py                      [py] autossh 隧道管理
│   ├── tunnel-manager-interactive.py  [py] 交互式隧道管理
│   ├── interactive-assistant.py       [py] 交互式配置助手
│   │
│   ├── windows-tunnel-batch.py        [py] Windows 批量隧道管理
│   ├── windows-tunnel-service.py      [py] Windows 隧道服务
│   ├── windows-tunnel-setup.py        [py] Windows 隧道安装
│   ├── linux-tunnel-service.py        [py] Linux systemd 隧道服务
│   │
│   ├── jump-server-manager.py         [py] 跳板端口管理
│   ├── master-api.py                  [py] 主控API服务
│   ├── join-client.py                 [py] 加入客户端
│   ├── matrix-ui.py                   [py] 矩阵界面
│   ├── quick-connect.sh               [sh] 快速连接
│   └── auto-discover.sh               [sh] 自动发现SSH config
│
└── templates/  配置模板
    ├── connection.yaml                连接配置模板
    ├── server-registration.yaml       服务器注册模板
    └── topology-graph.yaml            拓扑图模板
```

---

## 按使用场景索引

### 我想用这个工具，看哪个？

| 场景 | 文件 |
|------|------|
| 我是小白 | `docs/SETUP-BEGINNER.md` |
| 我在 Linux 上 | 运行 `linux-contract.sh` |
| 我在 Windows 上 | 双击 `windows-contract.bat` |
| 我是 Agent | 看 `SKILL.md` |
| 我想了解设计 | 看 `DESIGN.md` |

### 文件类型统计

| 类型 | 数量 | 说明 |
|------|------|------|
| [sh] Shell 脚本 | 6 | Linux 端 |
| [bat] Windows 批处理 | 5 | Windows 菜单/安装 |
| [ps1] PowerShell | 1 | Windows 安装向导 |
| [py] Python | 15 | 底层实现 |
| [md] 文档 | 14 | 设计+教程 |

### 文件归属

| 给谁用 | 文件 |
|--------|------|
| **小白用户** | `linux-contract.sh` `windows-contract.bat` `docs/SETUP-BEGINNER.md` |
| **进阶用户** | `linux-export-contract.sh` `windows-auto-setup.ps1` `scripts/*.py` |
| **Agent (AI)** | `SKILL.md` `DESIGN.md` |
| **开发者** | `DESIGN.md` `docs/*-spec.md` `templates/*.yaml` |
