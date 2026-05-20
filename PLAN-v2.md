# Tunnel Mesh 2.0 — 实现规划

## 零、核心抽象

### 单向图 = 真实物理连接网络

```
节点 = 服务器（有唯一名字，如数学符号 x, y, z）
边   = 相邻服务器之间可以建立 SSH 连接
方向 = 主 → 仆（谁发起连接）
类型 = forward（直连SSH）或 reverse（反向隧道）
```

### 用户的连接 vs 物理连接

```
物理连接图（工具管理）：
  A → B → C → D
  （每条边是一条真实 TCP 隧道或直连）

用户想要：
  A 访问 D（ssh D）
  
工具内部：
  自动 ProxyJump: A → B → C → D
  递归路径规划，用户只需要一个命令
```

### 不关心实现细节的颗粒度

```
粗颗粒：单向图 + 唯一命名
  → 只需要知道 A 能到 B，不关心是正向还是反向隧道

细颗粒：每条边的实现
  → 正向还是反向？谁来维持？端口多少？
```

---

## 一、项目拆分

### Part A: 开源通用工具

给任何人用，配自己的服务器。

```
功能：
  - 服务器命名管理（唯一ID，冲突检测+改名）
  - 交互式边规划（一步步问，判定正向/反向）
  - 公钥生成 + 交互式部署（复制粘贴）
  - 教程生成（md文件，流程图+编号步骤）
  - 路径规划（多跳 ProxyJump 自动配置）
  - 契约持久化（重启不丢）
```

### Part B: 用户专属配置指南

针对 node3 + 阿里云 + Windows 的具体网络。

```
使用 Part A 的通用工具，产生具体配置步骤。
文档形式：教程 md 文件 + 交互式输出。
```

---

## 二、新架构

```
tunnel-mesh/
├── tunnel-mesh.sh              ★ Linux 入口
├── tunnel-mesh.ps1             ★ Windows 入口（bat仅作启动器）
│
├── scripts/
│   ├── lib/
│   │   ├── detect.sh           ← 身份检测
│   │   ├── graph.sh            ← 图管理 + 路径规划
│   │   └── tutorial.sh         ← 教程生成
│   │
│   ├── server.sh               ← 服务器命名管理
│   ├── key.sh                  ← 密钥生成+部署
│   ├── edge.sh                 ← 边规划（单条边）
│   ├── path.sh                 ← 多跳路径
│   ├── status.sh               ← 查看图状态
│   └── remove.sh               ← 删除节点/边
│
├── docs/
│   └── SETUP.md                ← 用户专属教程
│
└── PROJECT-OVERVIEW.md
```

---

## 三、交互式边规划流程（单条边 A→B）

```
Step 1: 确认 A 的身份
  → 如果 A 还没命名 → 让用户起名（检测冲突 → 显示重复名 → 允许改名）

Step 2: 确认 B 的身份
  → 如果 B 还没命名 → 同上
  → 收集 B 的 IP/端口/用户（可以粘贴身份卡）

Step 3: 检测连通性
  → A 能直连 B 吗？  → TCP 测试 B 的 IP:SSH端口
  → B 能直连 A 吗？  → 需要用户在 B 上确认

Step 4: 判定边类型
  可达情况             边类型
  ─────────────────────────────────
  A能到B 且 B能到A  →  随便，正向/反向都可以
  A能到B  B不能到A  →  forward（A 直连 B）
  A不能到B B能到A  →  reverse（B 连 A，建立反向隧道）
  都不能            →  需要 bridge（找中间节点C）

Step 5: 如果是 reverse → 问维持者
  → 谁维持？ B 自己 / 外部机器（Windows）

Step 6: 分配端口，生成隧道命令

Step 7: 输出教程片段（单步编号 + 命令）
```

---

## 四、服务器命名管理

### 规则

```
- 全局唯一，类似数学符号 {x₁, x₂, ...}
- 默认：主机名
- 冲突时：显示冲突列表 + 让用户选择改名
```

### UI 示例

```
当前已知服务器：
  [1] node3     10.16.82.202:5122    wuxiaoran
  [2] aliyun    8.131.61.234:22      root
  [3] windows   10.16.73.249:22      wilia

检测到重名: node3 已存在
  已存在的: node3 (10.16.82.202:5122)
  新服务器: 10.16.82.202:5122
  
  请改名：
  [1] 修改已有的 → 新名: _
  [2] 修改新的   → 新名: node3-gpu
  [3] 保留两个   → node3 和 node3-1
```

---

## 五、教程生成

### 流程图（第一版）

```
# 连接教程：A → B

## 拓扑
```
A (10.0.1.1) → B (10.0.1.2) → C (192.168.1.1)
  正向            反向隧道
```

## 操作步骤

### Step 1: A 部署公钥到 B
```bash
# 在 A 上
bash tunnel-mesh.sh key export

# 复制身份卡，在 B 上
bash tunnel-mesh.sh key import
```

### Step 2: B 建立到 C 的反向隧道
```bash
# 在 B 上
bash tunnel-mesh.sh edge create
# 选择: reverse → C → 隧道端口 2201

# 输出隧道命令，复制到维持者
```

### Step 3: Windows 导入隧道命令
```
双击 tunnel-mesh.bat → [1]导入 → 粘贴
```
```

### 支持翻页

```
md 文件分段，每步一页。
交互式输出时按回车翻到下一步。
```

---

## 六、公钥管理

### 与边规划分离

```
Phase 1: 密钥阶段
  每个服务器: bash tunnel-mesh.sh key generate
  → 生成密钥
  → 输出身份卡（含公钥）
  → 复制到其他服务器
  → 其他服务器: bash tunnel-mesh.sh key import
  → 自动部署到 authorized_keys

Phase 2: 边规划阶段  
  密钥已就绪 → 只管网络连通性 → 构建边
```

### Windows 也参与

```
Windows 生成密钥 → 身份卡 → 复制到 Linux
Linux key import → 部署 Windows 公钥 → Windows 免密连 Linux
```

---

## 七、路径规划

### 内部递归

```
用户: ssh D

工具查找图:
  A → B → C → D

生成 SSH config:
  Host D
      ProxyJump B,C

ssh D ← 自动: ssh -J B,C D
```

### 多跳内部实现

```
跳1: A → B (forward)      → ssh B ok
跳2: B → C (reverse)      → ssh -p 2201 localhost (B上)
跳3: C → D (forward)      → ssh D (C上)

合并: ssh -J B,C D
      B 通过 ProxyJump 自动处理
      C 的 localhost:2201 对 B 透明
```

---

## 八、实现任务列表

### P0：核心数据层

| 任务 | 说明 |
|------|------|
| graph.sh | 图 CRUD：添加节点/边，查找，路径 |
| server.sh | 服务器命名管理 + 冲突检测 + 改名 |
| config.json v2 | 新数据结构：节点列表 + 边列表 |

### P1：密钥层

| 任务 | 说明 |
|------|------|
| key.sh | 生成密钥 + 导出身份卡 + 导入部署 |
| key.sh (batch) | key 部署的交互流程 |

### P2：边规划层

| 任务 | 说明 |
|------|------|
| edge.sh | 单条边规划：Tcp检测→判定→生成隧道 |
| edge.sh | 交互式：一步步问 + 即时反馈 |

### P3：教程层

| 任务 | 说明 |
|------|------|
| tutorial.sh | 从图生成 md 教程文件 |
| tutorial.sh | 流程图 + 编号步骤 + 翻页 |

### P4：路径层

| 任务 | 说明 |
|------|------|
| path.sh | 多跳路径查找 + ProxyJump 配置 |
| path.sh | 递归处理每跳的内部实现 |

### P5：入口 + 整合

| 任务 | 说明 |
|------|------|
| tunnel-mesh.sh | 新菜单（key | edge | graph | tutorial）|
| tunnel-mesh.ps1 | 同步更新 |
| 用户专属教程 | docs/SETUP.md |

---

## 九、信任模式

```
主 Agent（本会话）：
  保留：架构判断、集成、最终验证
  派发：边界明确的实现任务

Worker Agent：
  只修改分配给自己的文件
  不跨模块修改
  返回实现结果供主 Agent 审查
```

---

## 十、config.json v2

```json
{
  "servers": {
    "node3": {"ip": "10.16.82.202", "port": 5122, "user": "wuxiaoran", "pubkey": "...", "fingerprint": "..."},
    "aliyun": {"ip": "8.131.61.234", "port": 22, "user": "root", "pubkey": "...", "public_ip": "8.131.61.234"},
    "windows": {"ip": "10.16.73.249", "port": 22, "user": "wilia", "pubkey": "..."}
  },
  "edges": [
    {"from": "windows", "to": "aliyun",  "type": "forward"},
    {"from": "windows", "to": "node3",   "type": "forward"},
    {"from": "aliyun",  "to": "node3",   "type": "reverse", "port": 2201, "cmd": "ssh -R ...", "maintainer": "windows"},
    {"from": "node3",   "to": "aliyun",  "type": "reverse", "port": 2223, "cmd": "ssh -R ...", "maintainer": "windows"}
  ],
  "ports": {"used": [2201, 2223]}
}
```
