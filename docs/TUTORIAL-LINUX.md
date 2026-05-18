# Tunnel Mesh Linux 使用教程

## 是什么

Tunnel Mesh 让你在 Linux 上管理所有服务器的 SSH 连接。
**只需要回答几个问题，自动生成配置，一键连接。**

---

## 前置条件

- Linux 系统（Ubuntu / CentOS / Debian 均可）
- 已安装 `ssh` 和 `ssh-keygen`（系统自带）
- 可选：`autossh`（反向隧道保活用，`apt install autossh`）

---

## 安装

```bash
# 下载并运行安装脚本
curl -sSL https://raw.githubusercontent.com/wilianyichen/tunnel-mesh/main/linux-install.sh | bash
```

或手动安装：
```bash
git clone https://github.com/wilianyichen/tunnel-mesh.git
cd tunnel-mesh
sudo cp linux-contract-hall.sh /usr/local/bin/tunnel-mesh
chmod +x /usr/local/bin/tunnel-mesh
```

安装后输入 `tunnel-mesh` 即可进入契约大厅。

---

## 场景 1：连接一台你能直接 SSH 的服务器

**条件**：你的 Linux 能直接 ping 通目标服务器。

```
$ tunnel-mesh

  [1] 缔结契约
  → 选择触达方式: [1] 正向（我能直连仆）

  仆人名称: web-server          ← 随便起个名
  IP: 192.168.1.100            ← 目标的IP
  端口 [22]:                    ← 目标的SSH端口
  用户 [root]: admin            ← 用哪个账号登录
  密钥: [1] 生成新密钥

  结果：
    ✓ 密钥已生成: ~/.ssh/id_web-server
    ✓ SSH config 已添加: Host web-server
    ✓ 测试通过

  现在可以直接: ssh web-server
```

**发生了什么**：
```
你的Linux ──SSH──→ web-server (192.168.1.100:22)
                  直接TCP连接，只需密钥
```

---

## 场景 2：连接一台内网服务器（需反向隧道）

**条件**：目标在内网，你不能直接连它，但它能连你（或通过中间服务器）。

```
$ tunnel-mesh

  [1] 缔结契约
  → 选择触达方式: [2] 反向（我不能直连仆）

  仆人名称: db-server
  IP: 10.0.1.50
  端口: 22

  系统检测到 10.0.1.50 不可达...

  你有能同时连你和仆的中间服务器吗？
  [1] 有 → 输入中间服务器的契约名称: aliyun
  [2] 没有 → 需要仆端主动连接你

  选择 [1]:
    中间服务器: aliyun (已有契约)
    分配监听端口: 2201

    生成契约文书：
    ┌─────────────────────────────────────────┐
    │ ===CONTRACT===                          │
    │ REACH=reverse                           │
    │ MASTER=aliyun                           │
    │ SERVANT=db-server                       │
    │ SERVANT_IP=10.0.1.50                    │
    │ SERVANT_PORT=22                         │
    │ TUNNEL_PORT=2201                        │
    │ ===END===                               │
    └─────────────────────────────────────────┘

    将文书复制到中间服务器 (aliyun) 上执行：
    tunnel-mesh → [1]缔结契约 → 粘贴文书

  在 aliyun 上完成导入后，回到本机：
  [6] 契约之仪 → 启动隧道
  
  现在可以: ssh -p 2201 aliyun  ← 连到 db-server
```

**发生了什么**：
```
你的Linux ──SSH──→ aliyun:2201 ──隧道──→ db-server:22
                                            ↑
                                    aliyun运行: ssh -R 2201:db-server:22
```

---

## 场景 3：通过已有仆人连接新仆人（传递控制）

**条件**：你想连 server-C，自己不直接可达，但你的仆人 server-B 可达。

```
$ tunnel-mesh

  [3] 追寻仆人
  输入目标: gpu-cluster

  路径分析中...

  已知：
    你 → aliyun           [正向]
    aliyun → node3        [反向]
    node3 → gpu-cluster   [正向]

  发现路径：
    你 → aliyun → node3 → gpu-cluster
    （共 3 跳）

  是否保存为契约？[Y/n]: y

  契约名称: gpu-cluster
  保存为: Host gpu-cluster (ProxyJump aliyun,node3)

  现在可以直接: ssh gpu-cluster
  自动执行: ssh -J aliyun,node3 gpu-cluster
```

**你不需要管中间跳了几次。工具自动帮你配置。**

---

## 场景 4：作为仆端被连接

**条件**：别人要连你的服务器，但你在他那边是内网。

```
$ tunnel-mesh

  [2] 撰写文书

  本机信息（已自动获取）：
    主机名: node3
    IP: 10.16.82.202
    SSH端口: 5122

  对方的契约名称: aliyun
  对方 IP: 8.131.61.234
  对方端口: 22
  对方用户: root
  你的密钥: id_node3 (已有)

  生成契约文书：
  ┌─────────────────────────────────────────┐
  │ ===CONTRACT===                          │
  │ REACH=reverse                           │
  │ SERVANT=node3                           │
  │ SERVANT_IP=10.16.82.202                 │
  │ SERVANT_PORT=5122                       │
  │ SERVANT_USER=wuxiaoran                   │
  │ MASTER=aliyun                           │
  │ MASTER_IP=8.131.61.234                  │
  │ MASTER_PORT=22                          │
  │ PUB_KEY=ssh-ed25519 AAAA...             │
  │ ===END===                               │
  └─────────────────────────────────────────┘

  将文书复制给对方。
  对方导入后，你的服务器需要确保能连到对方。
```

---

## 日常管理命令

```
$ tunnel-mesh

  [2] 审视契约     → 列出我所有的仆和连接方式
  [3] 追寻仆人     → 探索多级仆人
  [4] 连接仆人     → 选择并连接
  [5] 断契         → 删除某条契约
  [6] 契约之仪     → 启动/重连所有反向隧道
  [7] 密钥保管     → 查看/生成/删除密钥
```

### 审视契约输出示例

```
你的契约：

  aliyun       正向   8.131.61.234:22      root     ● 在线
  node3        反向   10.16.82.202:5122    wuxiaoran ● 在线 (端口2201)
  gpu-cluster  传递   10.0.3.100:22        admin    ● 在线 (经由 aliyun,node3)

  在线: 3  离线: 0
```

### 断契操作

```
  [5] 断契
  选择: node3

  确认删除「node3」？
  这将：
    - 停止隧道服务
    - 删除 SSH config 条目
    - 是否同时删除关联密钥？[Y/n]

  确认: y
  ✓ 已删除契约 node3
  ✓ 端口 2201 已释放
  ✓ 密钥已删除
```

---

## 配置文件位置

```
~/.ssh/config           ← SSH config（自动添加条目）
~/.ssh/tunnel-mesh/     ← 密钥存储
~/.tunnel-mesh/
  contracts.json        ← 契约数据
  topology.json         ← 网络拓扑
```

---

## 常见问题

**Q: 为什么缔结反向契约时需要中间服务器？**
A: 因为你不能直接连仆。需要一个双方都能连的中间节点来转发。

**Q: 端口冲突了怎么办？**
A: 系统自动检测并分配下一个可用端口。不会冲突。

**Q: 重启后隧道还在吗？**
A: 反向隧道自动配 systemd 服务，重启后自动恢复。
