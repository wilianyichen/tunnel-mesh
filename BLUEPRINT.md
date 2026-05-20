# Tunnel Mesh 2.0 — 完整项目蓝图

---

## 一、一句话目标

**用户在任何服务器上，输入 `ssh 目标名` 就能连通。**
不管中间经过几跳、是正向还是反向隧道，工具内部处理，用户不需要知道。

---

## 二、核心抽象：物理连接单向图

```
图 = (节点集, 边集)

节点 = 服务器
  └─ 属性：唯一名称、IP、端口、用户、公钥、指纹

边 = 相邻服务器之间可建立的 SSH 连接
  └─ 属性：主(发起方)、仆(目标)、类型(forward/reverse)、隧道端口、维持者
  └─ 方向：主 → 仆
```

**关键区分**：图描述的是"网络能怎么连"，不是"用户想怎么连"。

```
例：用户想 A 连 D
手段：A→B→C→D（物理连接图）
工具内部：递归路径规划 → ssh -J B,C D
用户操作：ssh D（一行命令）
```

---

## 三、两层颗粒度

### 粗粒度：图 = 用户视角

```
只关心谁连谁，不关心内部实现。
节点唯一命名，边表示可达。
用户看这个图就知道网络拓扑。
```

### 细粒度：边 = 工具视角

```
每条边内部：
  → 正向？直连 SSH + 密钥
  → 反向？反向隧道 + 维持者 + 端口
  → 桥接？通过中间节点间接连
```

---

## 四、项目拆分

### Part A：通用开源工具（tunnel-mesh）

给任何人用。

```
tunnel-mesh/
├── tunnel-mesh.sh              ★ Linux 交互菜单
├── tunnel-mesh.ps1             ★ Windows 交互菜单
├── tunnel-mesh.bat             ★ Windows 启动器 (5行)
│
├── scripts/
│   ├── lib/
│   │   ├── detect.sh           ← 身份自动检测
│   │   ├── config.sh           ← config.json 读写
│   │   ├── graph.sh            ← 图 CRUD + 路径搜索
│   │   └── network.sh          ← TCP 检测 + 可达性判断
│   │
│   ├── phase1-key.sh           ← 密钥阶段：生成/导出/部署
│   ├── phase2-edge.sh          ← 边规划：交互式构建单条边
│   ├── phase3-tunnel.sh        ← 隧道创建：生成脚本+计划任务
│   ├── status.sh               ← 查看图 + 显示命令
│   ├── tutorial.sh             ← 生成教程文件
│   ├── remove.sh               ← 删除节点/边
│   ├── path.sh                 ← 多跳路径 + ProxyJump 配置
│   └── ssh-config.sh           ← SSH config 管理
│
├── docs/
│   ├── TUTORIAL.md             ← 通用教程
│   ├── SETUP-3SERVERS.md       ← 用户专属：node3+aliyun
│   └── ...
│
└── config.json                 ← 图数据持久化
```

### Part B：用户专属配置指南（docs/SETUP-3SERVERS.md）

用 Part A 的工具产生，针对具体网络。

---

## 五、完整配置流程（三个 Phase）

### Phase 1：密钥阶段

每个服务器生成密钥 + 交换公钥。**与网络连通性无关。**

```
每个服务器：
  bash tunnel-mesh.sh → 选 [密钥] → [生成]
  → 输出身份卡（含公钥）
  → 复制到其他服务器
  → 其他服务器：[密钥] → [部署]
  → 公钥写入 authorized_keys

Windows 也参与：
  tunnel-mesh.ps1 → [2] 导出身份卡
  → 复制到 Linux
  → Linux: [密钥] → [部署]
```

**Phase 1 完成后：所有服务器之间可以免密 SSH（在它们网络可达的前提下）**

### Phase 2：边规划阶段

对图中每条边，交互式判定连接方式。

```
bash tunnel-mesh.sh → [边规划]

Step 1: 谁连谁？
  主: aliyun  仆: node3

Step 2: 收集仆的信息
  粘贴 node3 的身份卡 或手动输入 IP/端口/用户

Step 3: 检测连通性
  阿里云能直连 node3 吗？ → TCP 测试 → 不可达 ✗
  node3 能直连阿里云吗？ → 询问/测试 → 也不可达 ✗

Step 4: 两个都不能 → 需要中间节点
  已知服务器中，谁能同时连通双方？
  候选: Windows ✓

Step 5: 维持者
  Windows 维持反向隧道

Step 6: 分配端口 2201，生成隧道命令

Step 7: 本机写 SSH config
  Host node3 → localhost:2201

Step 8: 输出教程片段 + 隧道命令
```

### Phase 3：隧道创建阶段

Windows 导入隧道命令，创建计划任务。

```
tunnel-mesh.ps1 → [1] 导入隧道命令
→ 粘贴 ssh -R ...
→ 生成 tunnel-N.ps1 + run-N.bat
→ Register-ScheduledTask
→ 开机自启 ✓
```

---

## 六、三种边类型判定逻辑

```
给定服务器 A（主）和 B（仆）：

  A 能 TCP 到 B:PORT？    B 能 TCP 到 A:PORT？
  ─────────────────────────────────────────────
      ✓                        ✓          → 正向或反向都可以，默认正向
      ✓                        ✗          → 正向（A 直连 B）
      ✗                        ✓          → 反向（B 连 A，隧道）
      ✗                        ✗          → 需要桥接（找中间节点 C）

桥接逻辑：
  在图的所有已知节点中，找 C 满足：
    C 能到 A（或 A 能到 C）且 C 能到 B（或 B 能到 C）
  如果找到 → C 作为维持者，两条边：C→A 和 C→B
```

---

## 七、多跳路径 = 递归

```
用户：ssh D

工具在图里查：
  A → B → C → D

第一步：ssh -J B,C D
第二步：B 的连接方式是什么？
  如果是 forward：SSH 直连 B 22 端口
  如果是 reverse：B 在 localhost:2201
第三步：C 的连接方式同理
  ...

结果：一行 ssh D，底层自动 ProxyJump + 隧道端口
```

### 用户想知道时

```
bash tunnel-mesh.sh → [路径详情]
输入: D

路径: A → B → C → D
  跳1: A → B    正向，ssh B
  跳2: B → C    反向隧道，B 上 localhost:2201
  跳3: C → D    正向，ssh D
```

---

## 八、服务器命名管理

```
规则：
  - 全局唯一，默认 = 主机名
  - 导入身份卡时自动用 NAME= 字段
  - 冲突时：

  检测到重名: node3
    [1] 已存在的 node3 (10.16.82.202:5122)  → 改名为: _
    [2] 新的 node3 (10.20.1.1:22)           → 改名为: _
    [3] 都保留（自动加后缀）
```

---

## 九、教程生成

### Phase 2 边规划完成后

```
输出教程文件 docs/tutorial-<timestamp>.md：

# 连接教程：aliyun → node3

## 拓扑
aliyun ──反向隧道:2201──→ node3 (维持者: Windows)

## 操作步骤

### Step 1: 阿里云配置 SSH
\`\`\`bash
cat >> ~/.ssh/config << 'EOF'
Host node3
    HostName localhost
    Port 2201
EOF
\`\`\`

### Step 2: Windows 导入隧道
\`\`\`
双击 tunnel-mesh.bat → [1]导入 → 粘贴:
ssh -R 2201:10.16.82.202:5122 root@8.131.61.234
\`\`\`

### Step 3: 验证
\`\`\`bash
ssh node3 hostname
\`\`\`
```

**翻页模式**：每步一页，按回车翻到下一步。

---

## 十、config.json v2

```json
{
  "servers": {
    "node3": {
      "name": "node3",
      "ip": "10.16.82.202",
      "port": 5122,
      "user": "wuxiaoran",
      "fingerprint": "SHA256:...",
      "pubkey": "ssh-ed25519 AAAA..."
    },
    "aliyun": {
      "name": "aliyun",
      "ip": "172.28.38.190",
      "public_ip": "8.131.61.234",
      "port": 22,
      "user": "root",
      "fingerprint": "SHA256:..."
    },
    "windows": {
      "name": "windows",
      "ip": "10.16.73.249",
      "port": 22,
      "user": "wilia"
    }
  },
  "edges": [
    {
      "id": "windows→aliyun",
      "from": "windows",
      "to": "aliyun",
      "type": "forward"
    },
    {
      "id": "aliyun→node3",
      "from": "aliyun",
      "to": "node3",
      "type": "reverse",
      "tunnel_port": 2201,
      "tunnel_cmd": "ssh -R 2201:10.16.82.202:5122 root@8.131.61.234",
      "maintainer": "windows",
      "status": "active"
    }
  ],
  "ports": {"used": [2201, 2223]}
}
```

---

## 十一、实现任务列表

### P0：基础设施

| ID | 任务 | 文件 | 依赖 |
|----|------|------|------|
| P0-1 | detect.sh — 身份检测（含公网IP） | scripts/lib/detect.sh | 无 |
| P0-2 | config.sh — JSON 读写+备份+端口管理 | scripts/lib/config.sh | 无 |
| P0-3 | network.sh — TCP 检测+可达性判断 | scripts/lib/network.sh | 无 |
| P0-4 | graph.sh — 图 CRUD + Dijkstra 路径 | scripts/lib/graph.sh | P0-1 |

### P1：密钥阶段

| ID | 任务 | 文件 |
|----|------|------|
| P1-1 | phase1-key.sh — 生成+导出+部署公钥 | scripts/phase1-key.sh |
| P1-2 | 更新 Windows 导出身份卡 | tunnel-mesh.ps1 |

### P2：边规划阶段

| ID | 任务 | 文件 | 依赖 |
|----|------|------|------|
| P2-1 | phase2-edge.sh — 交互式单条边规划 | scripts/phase2-edge.sh | P0-1..4, P1-1 |
| P2-2 | 命名管理 — 冲突检测+改名 | 集成到 P2-1 | |

### P3：隧道 + 教程

| ID | 任务 | 文件 | 依赖 |
|----|------|------|------|
| P3-1 | phase3-tunnel.sh — 生成隧道脚本 | scripts/phase3-tunnel.sh | P2-1 |
| P3-2 | tutorial.sh — 生成教程文件 | scripts/tutorial.sh | P2-1 |
| P3-3 | 更新 Windows 隧道导入 | tunnel-mesh.ps1 | |

### P4：入口 + 整合

| ID | 任务 | 文件 |
|----|------|------|
| P4-1 | tunnel-mesh.sh 新菜单 | tunnel-mesh.sh |
| P4-2 | 状态查看 + 路径查看 + 恢复 | scripts/status.sh, path.sh |
| P4-3 | docs/SETUP-3SERVERS.md | docs/ |

### P5：用户专属文档

| ID | 任务 | 文件 |
|----|------|------|
| P5-1 | 三服务器完整操作流程 | docs/SETUP-3SERVERS.md |
| P5-2 | 验证 + 排错指南 | docs/TROUBLESHOOTING.md |

---

## 十二、信任模式

```
主 Agent（本会话）：
  保留：架构判断、图模型、最终验证
  派发：每个 P0-P5 任务是边界明确的 Worker 任务

Worker Agent：
  只修改分配的文件
  不跨模块修改
  返回结果 + 自测报告
```

---

## 十三、config.json v2 存储路径

```
Linux:   ~/.tunnel-mesh/config.json
Windows: %USERPROFILE%\.tunnel-mesh\config.json
```

两个文件结构相同，方便跨平台兼容。

---

## 十四、原则总结

```
1. 降秩：只保留生成器（节点+边+可达性），砍掉一切派生概念
2. 两阶段：先配密钥，再规划边（公钥就绪后一切简单）
3. 图驱动：所有逻辑从图出发（路径、教程、状态查看）
4. 交互式：每一步都问清楚，给出可执行的输出
5. 小白友好：每步有解释，输出可以直接复制粘贴
6. 持久化：config.json 存一切，重启不丢
7. 双平台对称：Linux .sh + Windows .ps1 功能一致
8. 自愈：隧道命令多处存储，一处坏了下处可用
```
