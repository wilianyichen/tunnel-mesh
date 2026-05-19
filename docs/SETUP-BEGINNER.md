# Tunnel Mesh 完整使用指南

用这套通用脚本，任何服务器组合都能配。按提示选就行。

---

## 你的三服务器双向连接

```
要建立两条隧道：

隧道A：阿里云访问 node3
隧道B：node3 访问阿里云

两条隧道都由 Windows 维持，开机自启。
```

---

## 第一步：node3 导出契约

```bash
ssh -p 5122 wuxiaoran@10.16.82.202
bash linux-contract.sh export
```

**交互选择**：

```
对方能直接连到你吗？
  [2] 不能     → 选这个，阿里云不能直连 node3

谁来维持反向隧道？
  [2] 别人替我维持   → Windows 替你维持

隧道接收端 IP？      → 8.131.61.234  （Windows 要连到阿里云）
隧道接收端 SSH端口？ → 22
隧道接收端 用户名？   → root
隧道接收端开的端口？  → 2201
```

**输出两段**：
1. 契约文书（复制给 Windows）
2. 阿里云 SSH config（复制给阿里云）

---

## 第二步：阿里云贴配置

```bash
ssh root@8.131.61.234
# 粘贴第一步输出的「阿里云 SSH config」
```

---

## 第三步：阿里云导出契约

```bash
bash linux-contract.sh export
```

**交互选择**：

```
对方能直接连到你吗？
  [2] 不能     → node3 的校园网封了22端口

谁来维持反向隧道？
  [2] 别人替我维持   → Windows 替你维持

隧道接收端 IP？      → 10.16.82.202  （Windows 要连到 node3）
隧道接收端 SSH端口？ → 5122
隧道接收端 用户名？   → wuxiaoran
隧道接收端开的端口？  → 2223
```

---

## 第四步：node3 贴配置

```bash
# 在 node3 上
# 粘贴第三步输出的「node3 SSH config」
```

---

## 第五步：Windows 导入两条契约

```bash
双击 windows-contract.bat

[1] 导入契约 → 粘贴 node3 的契约文书
[1] 导入契约 → 粘贴阿里云的契约文书
```

**自动完成**：创建两条隧道 + 注册开机自启 + 启动

---

## 验证

```
阿里云上: ssh node3 hostname     → node3
node3上:  ssh aliyun hostname    → 阿里云主机名
Windows:  ssh node3 hostname     → 正向直连
Windows:  ssh aliyun hostname    → 正向直连
```
