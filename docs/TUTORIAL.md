# Tunnel Mesh 使用教程（小白友好版）

## 这是什么？

Tunnel Mesh 帮你从家里的电脑连接到公司的服务器，即使服务器在内网也能连接。

**简单说**：在公司服务器上运行一个脚本，复制一段文本，在家里电脑上粘贴，就能连接了。

---

## 快速开始（3 步完成）

### 第 1 步：在公司服务器上运行

```bash
# 下载并运行
curl -sSL https://raw.githubusercontent.com/wilianyichen/tunnel-mesh/main/linux-export-config.sh | bash
```

或手动运行：
```bash
bash linux-export-config.sh
```

### 第 2 步：复制配置文本

脚本会输出类似这样的内容：

```
===TUNNEL_CONFIG_START===
SERVER_NAME=node3
SERVER_IP=192.168.1.100
SERVER_PORT=22
JUMP_NAME=aliyun
JUMP_IP=YOUR_PUBLIC_IP
JUMP_PORT=22
JUMP_USER=root
PUB_KEY=ssh-ed25519 AAAA...
===TUNNEL_CONFIG_END===
```

**复制这段文本（包含 === 行）**

### 第 3 步：在 Windows 上粘贴

1. 双击桌面上的 **Tunnel Mesh** 图标
2. 选择 **[5] 导入配置**
3. **粘贴**刚才复制的文本
4. 按 **Ctrl+Z** 然后 **Enter**
5. 选择 **[3] 启动所有隧道**

**完成！**

---

## 安装方法

### Windows 安装

1. 下载 `windows-install.bat`
2. **右键** → **以管理员身份运行**
3. 等待安装完成
4. 桌面会出现 **Tunnel Mesh** 图标

### Linux/服务器端

无需安装，直接运行脚本即可。

---

## 常见问题

### Q: 连接不上怎么办？

检查以下几点：
1. 跳板服务器的 SSH 是否开放
2. 跳板服务器的防火墙是否放行
3. 密钥是否正确

### Q: 如何查看连接状态？

在 Windows 上：
1. 打开 Tunnel Mesh
2. 选择 **[1] 查看隧道状态**

### Q: 如何断开连接？

在 Windows 上：
1. 打开 Tunnel Mesh
2. 选择 **[4] 停止所有隧道**

### Q: 重启电脑后还能连接吗？

可以！隧道服务会自动启动。

---

## 视频教程

（待补充）

---

## 需要帮助？

- GitHub: https://github.com/wilianyichen/tunnel-mesh
- 问题反馈: https://github.com/wilianyichen/tunnel-mesh/issues
