# Tunnel Mesh 完整连接指南（三服务器版本）

跟着做就行，不需要懂技术。

---

## 你需要准备的东西

- 阿里云服务器的 IP 地址
- node3 服务器的 IP 地址和端口
- 两台服务器的登录用户名

---

## 第一步：Windows 操作（10分钟）

### 1. 右键以管理员身份打开 PowerShell

按键盘 `Win+X`，选「Windows PowerShell(管理员)」

### 2. 进入项目目录

```powershell
cd C:\tunnel-mesh
```

（如果没有这个目录，先下载项目：`git clone https://github.com/wilianyichen/tunnel-mesh.git C:\tunnel-mesh`）

### 3. 运行安装脚本

```powershell
PowerShell -ExecutionPolicy Bypass -File windows-auto-setup.ps1
```

### 4. 按提示输入信息

脚本会问你：

```
阿里云IP:         输入 8.131.61.234
node3 IP:         输入 10.16.82.202
node3 端口:       输入 5122
node3 用户名:      输入 wuxiaoran
```

然后就等着，脚本会自动：
- 创建两个隧道脚本
- 注册开机自启任务
- 启动隧道

### 5. 记住输出的配置文本

脚本最后会输出两段配置文本。**先不要关窗口**。

输出类似：

```
────────────────────────────────────────
  将此配置添加到 阿里云 的 ~/.ssh/config
────────────────────────────────────────

Host node3
    HostName localhost
    Port 2201
    ...

────────────────────────────────────────
  将此配置添加到 node3 的 ~/.ssh/config
────────────────────────────────────────

Host aliyun
    HostName localhost
    Port 2223
    ...
```

**把这两段分别复制下来。**

---

## 第二步：配置阿里云（2分钟）

### 1. 登录阿里云

在你的 Windows 上：

```powershell
ssh root@8.131.61.234
```

### 2. 粘贴配置

把你刚才复制的「阿里云配置」那一段，直接粘贴到终端里，回车。

内容大概长这样：

```bash
cat >> ~/.ssh/config << 'EOF'

Host node3
    HostName localhost
    Port 2201
    User wuxiaoran
    StrictHostKeyChecking no
    HostKeyAlias node3
EOF
chmod 600 ~/.ssh/config
```

### 3. 验证

```bash
ssh node3 hostname
```

**如果输出 `node3`，说明成功了！**

如果连不上，在 Windows 上检查隧道是否运行：

```powershell
Get-ScheduledTask -TaskName "Tunnel-1*" | Select State
```

---

## 第三步：配置 node3（2分钟）

### 1. 登录 node3

```powershell
ssh -p 5122 wuxiaoran@10.16.82.202
```

### 2. 粘贴配置

把你刚才复制的「node3 配置」那一段，直接粘贴到终端里，回车。

内容大概长这样：

```bash
cat >> ~/.ssh/config << 'EOF'

Host aliyun
    HostName localhost
    Port 2223
    User root
    StrictHostKeyChecking no
    HostKeyAlias aliyun
EOF
chmod 600 ~/.ssh/config
```

### 3. 验证

```bash
ssh aliyun hostname
```

**如果输出阿里云的主机名，说明成功了！**

---

## 完成！

现在三台服务器可以互相连接了：

```
在哪里            输入什么命令        连到哪里
─────────────────────────────────────────────
阿里云            ssh node3          node3
node3             ssh aliyun         阿里云
你的 Windows      ssh node3          node3
你的 Windows      ssh aliyun         阿里云
```

---

## 如果出问题了

### 问题1：阿里云上 ssh node3 连不上

**原因**：Windows 上的隧道1没运行。

**解决**：在 Windows PowerShell（管理员）里：

```powershell
Start-ScheduledTask -TaskName "Tunnel-1-Aliyun-Node3"
Get-ScheduledTask -TaskName "Tunnel-1*" | Select State
# 应显示 Running
```

### 问题2：node3 上 ssh aliyun 连不上

**原因**：Windows 上的隧道2没运行。

**解决**：在 Windows PowerShell（管理员）里：

```powershell
Start-ScheduledTask -TaskName "Tunnel-2-Node3-Aliyun"
```

### 问题3：重启电脑后连不上

**原因**：计划任务可能延迟启动。

**解决**：等1分钟再试。开机自启已配置，会自动启动的。

### 问题4：隧道状态看不明白

**解决**：双击桌面的「契约大厅」图标，选 `[2] 审视契约`。

---

## 日常管理

双击桌面的「契约大厅」：

```
[1] 添加新的连接
[2] 查看所有隧道状态
[3] 启动所有隧道
[4] 停止所有隧道
[7] 测试某个连接
```

---

## 原理说明（不需要看，但是万一想知道）

```
你的 Windows 运行着两条隧道：

隧道1：
  Windows 连到阿里云，在阿里云上开了一个门（端口2201）
  有人敲阿里云的2201门，就被传送到 node3:5122
  
隧道2：
  Windows 连到 node3，在 node3 上开了一个门（端口2223）
  有人敲 node3 的2223门，就被传送到 阿里云:22

阿里云上的配置：ssh node3 = 敲你自己的2201门 = 到node3
node3上的配置：  ssh aliyun = 敲你自己的2223门 = 到阿里云
```
