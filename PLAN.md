# Tunnel Mesh 开发任务规划

---

## Task 1：交互式配置向导 `tunnel-mesh-wizard.sh`

**目标**：一个脚本跑完全程，不需要记步骤。

**流程**：

```
$ bash tunnel-mesh-wizard.sh

  你想做什么？
  [1] 连接两台服务器（建立一条主仆关系）
  [2] 双向连接（两台服务器互相访问）
  [3] 多台服务器组网（3+台）
  [4] 查看当前网络状态

→ 选 [2]

  第一台服务器是谁？
  在哪个服务器上操作？[本机 / 其他]

→ 交互式逐步询问 → 输出完整操作步骤 → 引导执行
```

**输入**：目标（谁连谁）、方向、网络可达性
**输出**：步骤清单 + 每步需要执行的命令 + 验证命令

---

## Task 2：配置持久化 `~/.tunnel-mesh/config.json`

**数据结构**：

```json
{
  "servers": {
    "node3": {
      "name": "node3",
      "ip": "10.16.82.202",
      "port": 5122,
      "user": "wuxiaoran",
      "fingerprint": "SHA256:xxx",
      "last_seen": "2026-05-15"
    }
  },
  "contracts": [
    {
      "id": "aliyun→node3",
      "master": "aliyun",
      "servant": "node3",
      "type": "reverse",
      "tunnel_port": 2201,
      "tunnel_cmd": "ssh -R ...",
      "maintainer": "bridge",
      "status": "active",
      "created": "2026-05-15"
    }
  ],
  "ports": {
    "used": [2201, 2223],
    "next": 2202
  }
}
```

**修改点**：

| 脚本 | 改什么 |
|------|--------|
| `tunnel-mesh.sh` import | 保存服务器信息 + 契约到 config.json |
| `tunnel-mesh.sh` export | 如果已有，显示「已导出过」 |
| `tunnel-mesh.sh` 新增菜单 | [4] 审视契约 / [5] 废契 |
| `windows-contract.bat` import | 同步保存到 Windows 版 config |

---

## Task 3：端口管理

**当前问题**：每次从 2201 开始分配，不知道哪些已用。

**方案**：
- 读取 `config.json` 中 `ports.used`
- 如果有跨脚本冲突（比如其他工具占用了 2201），导入时检测：
  ```bash
  ss -tlnp | grep ":2201 "  # 检查端口是否被占用
  ```
- 冲突时自动跳过

---

## Task 4：重复导入检测

**场景**：用户再次粘贴同一个身份卡。

**检测**：对比 `config.json` 中的 `servers[].fingerprint`。

**行为**：
```
该服务器已存在:
  node3 (SHA256:xxx)
  上次导入: 2026-05-15
  是否覆盖？[y/N]
```

---

## Task 5：多跳路径

**依赖**：Task 2（需要有 config.json 才能算路径）

**集成**：graph.py 已有 Dijkstra，需要：
- 从 config.json 构建图
- 新增菜单 `[6] 探寻路径`
- 输入目标服务器名 → 输出路径

---

## Task 6：配置恢复

**场景**：SSH config 被误删，或换了一台新电脑。

**操作**：
```
[7] 重新生成配置
→ 从 config.json 读取所有契约
→ 重新生成 SSH config 条目
→ 重新生成隧道脚本
```

---

## 实施顺序

```
P0（必须，先做）
  Task 2: 配置持久化       ← 基础，其他都依赖它
  Task 3: 端口管理         ← 集成到 Task 2
  Task 4: 重复导入检测     ← 集成到 Task 2

P1（重要，做完 P0 再做）
  Task 1: 交互式配置向导   ← 改善体验
  Task 5: 多跳路径         ← 集成 graph.py

P2（增强）
  Task 6: 配置恢复
```
