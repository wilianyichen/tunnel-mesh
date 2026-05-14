# Tunnel Mesh

> 简单易用的反向隧道管理工具，让内网服务器连接变得简单。

## 特点

- **小白友好**：复制粘贴即可完成配置
- **双平台支持**：Windows 图形化菜单 + Linux 一键脚本
- **批量管理**：一次管理多个隧道
- **自动重连**：断线自动重连
- **开机自启**：重启后自动恢复连接

## 快速开始

### 场景：从家里连接公司内网服务器

#### 第 1 步：在公司服务器上运行

```bash
curl -sSL https://raw.githubusercontent.com/wilianyichen/tunnel-mesh/main/linux-export-config.sh | bash
```

#### 第 2 步：复制输出的配置文本

#### 第 3 步：在 Windows 上粘贴

1. 双击 **Tunnel Mesh** 图标
2. 选择 **[5] 导入配置**
3. 粘贴配置文本
4. 选择 **[3] 启动所有隧道**

**完成！**

## 安装

### Windows

1. 下载 `windows-install.bat`
2. 右键 → 以管理员身份运行

### Linux

无需安装，直接运行脚本。

## 文档

- [使用教程（小白友好版）](docs/TUTORIAL.md)
- [Windows 批量管理指南](docs/windows-batch-guide.md)
- [完整配置指南](docs/windows-tunnel-guide.md)

## 目录结构

```
tunnel-mesh/
├── windows-install.bat          # Windows 一键安装
├── windows-menu.bat             # Windows 图形化菜单
├── linux-export-config.sh       # Linux 配置导出
├── scripts/
│   ├── windows-tunnel-batch.py  # Windows 批量管理
│   ├── parse-config.py          # 配置解析
│   └── ...
├── docs/
│   ├── TUTORIAL.md              # 小白教程
│   └── ...
└── SKILL.md                     # Agent 文档
```

## 平台支持

| 平台 | 功能 | 方式 |
|------|------|------|
| Windows | 隧道管理 | 图形化菜单 |
| Linux | 配置导出 | 一键脚本 |

## 许可证

MIT License
