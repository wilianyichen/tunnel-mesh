# Tunnel Mesh

> 让服务器连接变得简单。跟着提示操作，不需要懂技术。

## 安装

**Windows**：以管理员身份运行 PowerShell，执行：

```powershell
PowerShell -ExecutionPolicy Bypass -File windows-auto-setup.ps1
```

**Linux**：导出自己的信息给对方：

```bash
bash linux-export-contract.sh
```

---

## 使用场景

| 场景 | 教程 |
|------|------|
| **我的三台服务器怎么配？** | [小白完整指南](docs/SETUP-BEGINNER.md) |
| **三服务器详细配置** | [完整配置指南](docs/SETUP-3SERVERS.md) |
| **日常管理** | [操作流程](docs/OPERATION.md) |
| **Linux 教程** | [Linux 使用教程](docs/TUTORIAL-LINUX.md) |
| **Windows 教程** | [Windows 使用教程](docs/TUTORIAL-WINDOWS.md) |

---

## 项目文件

| 文件 | 给谁用 | 作用 |
|------|--------|------|
| `windows-auto-setup.ps1` | Windows 用户 | 一键安装向导 |
| `windows-contract-hall.bat` | Windows 用户 | 契约大厅（管理所有隧道） |
| `linux-export-contract.sh` | Linux 用户 | 导出信息给对端 |
| `linux-setup-ssh-config.sh` | Linux 用户 | 导入对端配置 |
| `docs/SETUP-BEGINNER.md` | 小白 | 三服务器完整指南 |

---

## 许可证

MIT
