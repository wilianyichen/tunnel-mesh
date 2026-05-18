# Tunnel Mesh

> 通用服务器连接工具，Linux / Windows 双平台

## 核心概念

```
每台服务器运行一次导出 → 生成「契约文书」→ 复制到对方 → 粘贴完成
```

不需要懂 SSH、隧道、端口。跟着脚本提示选就行。

---

## 快速开始

### Linux 上：

```bash
# 导出模式 - 生成我的身份信息给对方
bash linux-contract.sh export

# 导入模式 - 粘贴对方给我的契约文书
bash linux-contract.sh import
```

### Windows 上：

```
双击 windows-contract.bat → [1]导入契约 → 粘贴契约文书
```

---

## 完整教程

| 场景 | 文档 |
|------|------|
| **三服务器双向连接（阿里云↔node3）** | [SETUP-BEGINNER.md](docs/SETUP-BEGINNER.md) |
| **三服务器详细配置指南** | [SETUP-3SERVERS.md](docs/SETUP-3SERVERS.md) |
| **Linux 详细教程** | [TUTORIAL-LINUX.md](docs/TUTORIAL-LINUX.md) |
| **Windows 详细教程** | [TUTORIAL-WINDOWS.md](docs/TUTORIAL-WINDOWS.md) |

---

## 项目文件

| 文件 | 平台 | 作用 |
|------|------|------|
| `linux-contract.sh` | Linux | **通用脚本**（导出+导入） |
| `windows-contract.bat` | Windows | **通用脚本**（导入+管理） |
| `linux-export-contract.sh` | Linux | 导出+自动检测 |
| `linux-setup-ssh-config.sh` | Linux | SSH config 配置 |
| `windows-auto-setup.ps1` | Windows | 一键安装向导 |

---

## 许可证

MIT
