# Tunnel Mesh

服务器网络拓扑管理工具，支持反向隧道、多平台服务、密钥管理。

## 功能

- **跳板服务器端口管理**：自动分配和管理反向隧道端口
- **Linux 隧道服务**：autossh + systemd 自动保活
- **Windows 隧道服务**：ssh.exe + Windows Service
- **密钥管理**：SSH 密钥生成、部署、配置
- **交互式终端**：增删改查隧道配置

## 快速开始

### 交互式管理（推荐）

```bash
python3 scripts/tunnel-manager-interactive.py
```

### 命令行方式

```bash
# 1. 初始化跳板服务器
python3 scripts/jump-server-manager.py init --host aliyun --ip 8.131.61.234

# 2. 分配端口
python3 scripts/jump-server-manager.py allocate --target node3 --ip 10.16.82.202

# 3. 生成密钥
python3 scripts/key-manager.py generate --name tunnel-node3

# 4. 安装隧道服务
python3 scripts/linux-tunnel-service.py install --target node3
```

## 目录结构

```
tunnel-mesh/
├── scripts/
│   ├── jump-server-manager.py      # 跳板端口管理
│   ├── linux-tunnel-service.py     # Linux 隧道服务
│   ├── windows-tunnel-service.py   # Windows 隧道服务
│   ├── key-manager.py              # 密钥管理
│   ├── tunnel-manager-interactive.py # 交互式终端
│   └── topology-manager.py         # 拓扑管理
├── templates/
│   ├── systemd/                    # systemd 服务模板
│   └── windows/                    # Windows 服务模板
└── docs/
    ├── topology-spec.md            # 拓扑规范
    ├── connection-matrix.md        # 连接矩阵设计
    └── trust-levels.md             # 信任等级定义
```

## 平台支持

| 平台 | 隧道命令 | 保活方式 | 自启动 |
|------|----------|----------|--------|
| Linux | autossh | systemd | systemctl enable |
| Windows | ssh.exe | Windows Service | sc create |

## 许可证

MIT License