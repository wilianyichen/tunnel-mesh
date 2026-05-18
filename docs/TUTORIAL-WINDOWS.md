# Tunnel Mesh Windows 使用教程

## 是什么

Tunnel Mesh 让你在 Windows 上管理所有服务器的 SSH 连接。
**双击图标，选菜单，粘贴文书，完成。**

---

## 前置条件

- Windows 10 或 Windows 11
- 已安装 OpenSSH Client（Win10 自带，设置→应用→可选功能→OpenSSH 客户端）
- 可选：Python 3（脚本功能需要）

---

## 安装

### 方法 1：一键安装（推荐）

1. 下载 `windows-install.bat`
2. **右键** → **以管理员身份运行**
3. 等待完成
4. 桌面出现 **契约大厅** 快捷方式

### 方法 2：手动安装

```powershell
# 以管理员身份运行 PowerShell
mkdir C:\tunnel-mesh
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/wilianyichen/tunnel-mesh/main/windows-contract-hall.bat" -OutFile "C:\tunnel-mesh\contract-hall.bat"
```

双击 `C:\tunnel-mesh\contract-hall.bat` 即可运行。

---

## 场景 1：连接一台你能直接 SSH 的服务器

**条件**：你的 Windows 能直接 ping 通目标服务器。

```
双击桌面「契约大厅」图标

  ╔════════════════════════════════════════╗
  ║         Tunnel Mesh  契约大厅          ║
  ╠════════════════════════════════════════╣
  ║                                        ║
  ║  [1] 缔结契约                          ║
  ║  [2] 审视契约                          ║
  ║  [3] 追寻仆人                          ║
  ║  [4] 连接仆人                          ║
  ║  ...                                   ║
  ╚════════════════════════════════════════╝

  选择: 1

  ─────────────────────────────────────────
  选择触达方式：
    [1] 正向 - 我可以直接连到仆
    [2] 反向 - 仆可以连到我，但我不能连仆
    [3] 通过路径 - 通过已有仆人间接连新仆
  
  选择: 1

  仆人名称: web-server
  IP:端口: 192.168.1.100:22
  用户: admin
  密钥: [1] 生成新密钥

  ✓ 契约已缔结！
  ssh web-server
```

**发生了什么**：
```
你的Windows ──直接SSH──→ web-server (192.168.1.100:22)
```

---

## 场景 2：连接一台你无法直连的服务器

**条件**：目标在别的地方，你不能直接连它。但有一台中间服务器（如阿里云）双方都能连。

```
  选择: 1  (缔结契约)
  选择触达方式: [2] 反向

  仆人名称: node3
  IP:端口: 10.16.82.202:5122
  用户: wuxiaoran

  系统检测到 10.16.82.202 不可达...

  你有能同时连你和仆的中间服务器吗？
  [1] 有，名称: aliyun
  [2] 没有

  选择 [1]，输入: aliyun

  分配端口: 2201
  生成契约文书...

  ┌─────────────────────────────────────────┐
  │ ===CONTRACT===                          │
  │ REACH=reverse                           │
  │ MASTER=aliyun                           │
  │ SERVANT=node3                           │
  │ SERVANT_IP=10.16.82.202                 │
  │ SERVANT_PORT=5122                       │
  │ TUNNEL_PORT=2201                        │
  │ ===END===                               │
  └─────────────────────────────────────────┘

  隧道将在你的 Windows 上运行（因为你同时能连 aliyun 和 node3）
  自动创建 Windows 服务: Tunnel-node3
  开机自启动 ✓

  现在可以: ssh -p 2201 aliyun
```

**发生了什么**：
```
你的Windows ──反向隧道──→ aliyun:2201 ──转发──→ node3:5122
     │                      ↑
     │       ssh -R 2201:node3:5122 root@aliyun
     │
     └── 这个命令作为 Windows 服务自动运行
```

---

## 场景 3：通过中间服务器连更深层的服务器

**条件**：你想连 gpu-cluster，你已经能连 aliyun，阿里云能连 node3，node3 能连 gpu-cluster。

```
  选择: [3] 追寻仆人
  输入: gpu-cluster

  路径分析...

  发现路径：
    你 → aliyun → node3 → gpu-cluster

  保存为契约？[Y/n]: y

  ✓ 已保存
  ssh gpu-cluster
  （自动执行 ssh -J aliyun,node3 gpu-cluster）
```

---

## 场景 4：让别人连你（作为仆端）

**条件**：别人的电脑要连你的 Windows，你不能直连他。

```
  选择: [2] 撰写文书

  本机信息：
    主机名: MY-PC
    IP: 10.16.73.249

  对方的契约名称: boss-pc
  对方 IP: 8.131.61.234
  对方端口: 22

  生成契约文书：
  ┌─────────────────────────────────────────┐
  │ ===CONTRACT===                          │
  │ REACH=reverse                           │
  │ SERVANT=MY-PC                           │
  │ SERVANT_IP=10.16.73.249                 │
  │ ...                                     │
  │ ===END===                               │
  └─────────────────────────────────────────┘

  将文书复制给对方即可。
```

---

## 日常使用

### 连接服务器

```
  [4] 连接仆人
  选择一个:
    1. aliyun
    2. node3
    3. gpu-cluster

  选 2 → 自动打开 SSH 连接到 node3
```

### 查看状态

```
  [2] 审视契约

  你的契约：
    aliyun       正向   在线
    node3        反向   在线 (端口2201)
    gpu-cluster  传递   在线 (经由 aliyun,node3)
```

### 删除不需要的契约

```
  [5] 断契
  选择: old-server

  确认删除？这将：
    - 停止相关隧道服务
    - 删除 SSH config
    - 释放端口
  
  确认 [Y/n]: y
  ✓ 已删除
```

### 密钥管理

```
  [7] 密钥保管

  [1] 查看所有密钥
  [2] 生成新密钥
  [3] 显示公钥（复制给对方）
  [4] 删除密钥
```

---

## Windows 特有功能

### 隧道作为 Windows 服务运行

反向隧道自动注册为 Windows 服务，开机自启：

```
服务名: Tunnel-<仆人名称>
状态: 运行中 / 已停止

管理：
  net start Tunnel-node3    ← 手动启动
  net stop Tunnel-node3     ← 手动停止
  sc query Tunnel-node3     ← 查看状态
```

### 桌面快捷方式

安装后桌面自动创建「契约大厅」快捷方式，双击即用。

---

## 文件位置

```
C:\tunnel-mesh\
  contracts.json          ← 契约数据
  config\                  ← 配置目录
  scripts\                 ← 生成的启动脚本
  logs\                    ← 运行日志

C:\Users\<用户名>\.ssh\
  config                   ← SSH config（自动添加）
  tunnel-mesh\             ← 密钥存储
```

---

## 常见问题

**Q: 为什么提示"SSH未找到"？**
A: 需要安装 OpenSSH 客户端。设置→应用→可选功能→添加功能→OpenSSH 客户端。

**Q: 隧道服务启动失败？**
A: 确保以管理员身份运行安装脚本。检查 `sc query Tunnel-xxx` 查看错误信息。

**Q: 中文乱码？**
A: 所有脚本开头有 `chcp 65001` 设置 UTF-8 编码，不会乱码。

**Q: 重启后隧道还在吗？**
A: 是的。反向隧道注册为 Windows 服务，设置为自动启动。
