# Tunnel Mesh 使用指南

## 操作流程

每台服务器只需一个命令：`bash tunnel-mesh.sh`，然后选数字。

---

## 第一步：node3 导出身份卡

```bash
ssh -p 5122 wuxiaoran@10.16.82.202
bash tunnel-mesh.sh
```

```
选 [1] 导出身份卡
→ 复制输出的身份卡（只有 node3 自己的信息，不需要填别的）
```

---

## 第二步：阿里云导入 + 导出

```bash
ssh root@8.131.61.234
bash tunnel-mesh.sh
```

```
选 [2] 导入身份卡
→ 粘贴 node3 的身份卡
→ 问「你能直接连到 node3 吗？」 选 [2] 不能
→ 问「维持者？」选 [2] 其他机器（Windows）

自动完成：
  ✓ 本机 SSH config（Host node3 → localhost:2201）
  ✓ 公钥添加
→ 输出隧道命令（给 Windows 的）

然后，继续在阿里云上：

选 [1] 导出身份卡
→ 复制输出的身份卡（只有阿里云自己的信息）
```

---

## 第三步：node3 导入

```bash
# 回到 node3
bash tunnel-mesh.sh
```

```
选 [2] 导入身份卡
→ 粘贴阿里云的身份卡
→ 问「你能直接连到 aliyun 吗？」 选 [2] 不能
→ 问「维持者？」选 [2] 其他机器（Windows）

自动完成：
  ✓ 本机 SSH config（Host aliyun → localhost:2223）
  ✓ 公钥添加
→ 输出隧道命令（给 Windows 的）
```

---

## 第四步：Windows 导入

```
双击 windows-contract.bat
选 [1] 导入契约
→ 粘贴第二步输出的隧道命令
→ 粘贴第三步输出的隧道命令

自动完成：
  ✓ 两条隧道脚本
  ✓ 开机自启
  ✓ 立即启动
```

---

## 完成

```
阿里云: ssh node3 hostname     → node3
node3:  ssh aliyun hostname    → 阿里云
Windows: 直接连任意
```
