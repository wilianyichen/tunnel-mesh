# Tunnel Mesh 完整使用指南（通用工具版）

本指南使用通用脚本，适用于任何服务器组合。

---

## 工具说明

| 脚本 | 在哪里用 | 作用 |
|------|----------|------|
| `linux-contract.sh` | 任意 Linux | export 导出身份 / import 导入契约 |
| `windows-contract.bat` | Windows | 导入契约 + 管理隧道 |

---

## 你的三服务器双向连接

两台服务器（阿里云和 node3）要互相访问，Windows 做桥。

需要建立 **两条契约**：

```
契约A: node3 → 阿里云方向（阿里云能访问 node3）
契约B: 阿里云 → node3方向（node3 能访问 阿里云）
```

---

## 契约A：让阿里云能访问 node3

### A1：在 node3 上导出契约

```bash
# SSH 登录 node3
ssh -p 5122 wuxiaoran@10.16.82.202

# 运行导出脚本
bash linux-contract.sh export
```

**交互选择**：

```
这个服务器在网络中的角色是？
  [1] 我是「仆」- 别人要连我
  [2] 我是「中转」- 有公网IP
选择: 1                          ← node3 是仆

对方能用什么方式连你？
  [1] 直接SSH
  [2] 反向隧道
选择: 2                          ← 阿里云不能直连 node3

中转服务器IP: 8.131.61.234       ← 阿里云的公网IP
中转服务器SSH端口: 22
中转服务器用户: root
隧道端口: 2201

谁来维持这个反向隧道？
  [1] 我自己
  [2] 别人替我维持
选择: 2                          ← Windows 替 node3 维持
```

**输出两份配置**：

```
=== 契约文书（复制给 Windows）===
=== 中转服务器配置（复制给阿里云）===
```

---

### A2：在阿里云上贴配置

```bash
# SSH 登录阿里云
ssh root@8.131.61.234

# 粘贴 node3 输出的「中转服务器配置」那段
cat >> ~/.ssh/config << 'EOF'
Host node3
    HostName localhost
    Port 2201
    User wuxiaoran
    ...
EOF
chmod 600 ~/.ssh/config
```

---

### A3：在 Windows 上导入契约

```
双击 windows-contract.bat
选择 [1] 导入契约
粘贴 node3 输出的「契约文书」
```

自动完成：创建隧道脚本 + 注册开机自启 + 启动隧道

---

## 契约B：让 node3 能访问 阿里云

### B1：在阿里云上导出契约

```bash
# 在阿里云上
bash linux-contract.sh export
```

**交互选择**：

```
这个服务器在网络中的角色是？
选择: 1                          ← 阿里云这次是仆

对方能用什么方式连你？
选择: 2                          ← node3 不能直连阿里云（22端口被封）

中转服务器IP: 10.16.82.202        ← 这次 node3 作为隧道接收端
中转服务器SSH端口: 5122
中转服务器用户: wuxiaoran
隧道端口: 2223

谁来维持这个反向隧道？
选择: 2                          ← Windows 维持
```

---

### B2：在 node3 上贴配置

```bash
# 在 node3 上
# 粘贴阿里云输出的「中转服务器配置」那段
cat >> ~/.ssh/config << 'EOF'
Host aliyun
    HostName localhost
    Port 2223
    User root
    ...
EOF
chmod 600 ~/.ssh/config
```

---

### B3：在 Windows 上导入契约

```
双击 windows-contract.bat
选择 [1] 导入契约
粘贴阿里云输出的「契约文书」
```

---

## 完成！验证

```
阿里云上:
  ssh node3 hostname     →  应该输出 node3

node3上:
  ssh aliyun hostname    →  应该输出阿里云主机名

Windows上:
  ssh node3 hostname     →  正向直连
  ssh aliyun hostname    →  正向直连
```

---

## 开机自启

Windows 已自动配置两个计划任务：

```
Tunnel-node3     → 反向隧道: 阿里云→node3
Tunnel-aliyun    → 反向隧道: node3→阿里云
```

重启 Windows 后自动恢复。

---

## 信息流动图

```
契约A:
  node3 导出 ──→ 契约文书 → Windows 导入 → 创建隧道
              ──→ 中转配置 → 阿里云粘贴 → SSH config

契约B:
  阿里云导出 ──→ 契约文书 → Windows 导入 → 创建隧道
              ──→ 中转配置 → node3 粘贴 → SSH config
```
