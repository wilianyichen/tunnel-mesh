# Tunnel Mesh

> SSH 连接管理工具，Linux / Windows 双平台，选菜单即用。

## 核心概念

```
主仆关系 ─ 主发起控制，仆被控制
触达方式 ─ 正向（直连）或 反向（需隧道）
传递控制 ─ 通过已有仆人连接更深层的服务器
```

## 安装

**Linux**：
```bash
curl -sSL https://raw.githubusercontent.com/wilianyichen/tunnel-mesh/main/linux-install.sh | bash
```

**Windows**：下载 `windows-install.bat`，右键 → 以管理员身份运行。

## 使用教程

| 平台 | 教程 |
|------|------|
| Linux | [Linux 使用教程](docs/TUTORIAL-LINUX.md) |
| Windows | [Windows 使用教程](docs/TUTORIAL-WINDOWS.md) |
| 总览 | [快速开始](docs/TUTORIAL.md) |

## 功能

- 缔结契约 - 建立主仆关系（正向直连 / 反向隧道 / 多级跳转）
- 审视契约 - 列出所有仆及连接状态
- 追寻仆人 - 自动发现多级仆人（传递控制）
- 连接仆人 - 一键连接，自动选最优路径
- 契约之仪 - 启动所有反向隧道（开机自启）
- 断契 - 删除契约（停隧道 + 删配置 + 可选删密钥）
- 密钥保管 - 独立管理每对关系的 SSH 密钥

## 文件说明

```
tunnel-mesh/
├── README.md                         # 项目说明
├── DESIGN.md                         # 设计规范
├── SKILL.md                          # Agent 文档
├── linux-install.sh                  # Linux 安装
├── linux-export-config.sh            # Linux 契约大厅
├── windows-install.bat               # Windows 安装
├── windows-contract-hall.bat         # Windows 契约大厅
├── windows-export-config.bat         # Windows 导出文书
├── docs/
│   ├── TUTORIAL.md                   # 总览
│   ├── TUTORIAL-LINUX.md             # Linux 教程
│   └── TUTORIAL-WINDOWS.md           # Windows 教程
└── scripts/
    ├── parse-contract.py             # 契约解析
    ├── key-manager.py                # 密钥管理
    └── windows-tunnel-batch.py       # 批量隧道管理
```

## 许可证

MIT License
