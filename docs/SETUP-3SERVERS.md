# 三服务器双向连接操作流程

## 你的三台服务器

- **node3**: 10.16.82.202:5122 (内网, 校园网)
- **阿里云**: 8.131.61.234:22 (公网 VPS)
- **Windows**: 10.16.73.249:22 (校园网, 能同时连两个)

---

## Phase 1: 密钥部署

### 每台服务器上

```bash
cd ~/software/tunnel-mesh
git pull
sed -i 's/\r$//' *.sh scripts/*.sh scripts/lib/*.sh
bash tunnel-mesh.sh → [1]密钥 → [1]生成
```

**复制身份卡，互相部署。**

### Windows 上

```
双击 tunnel-mesh.bat → [2]导出身份卡 → 复制
```

### 在阿里云和 node3 上

```
bash tunnel-mesh.sh → [1]密钥 → [2]部署 → 粘贴 Windows 身份卡
```

同样，node3 的身份卡部署到阿里云，阿里云的部署到 node3。

---

## Phase 2: 边规划

### 边1: 阿里云 → node3

```bash
# 在阿里云上
bash tunnel-mesh.sh → [2]边规划
```

```
主: aliyun (本机)
仆: node3 (已知)
检测: 不可达 → 反向隧道
维持者: [2] 外部机器
隧道端口: 2201
```

→ 输出隧道命令，复制。

### 边2: node3 → 阿里云

```bash
# 在 node3 上
bash tunnel-mesh.sh → [2]边规划
```

```
主: node3 (本机)
仆: aliyun (已知)
检测: 不可达 → 反向隧道
维持者: [2] 外部机器
隧道端口: 2223
```

→ 输出隧道命令，复制。

---

## Phase 3: Windows 导入

```
双击 tunnel-mesh.bat → [1]导入
→ 粘贴边1的隧道命令
→ [1]导入
→ 粘贴边2的隧道命令
```

---

## 验证

```bash
# 阿里云上
ssh node3 hostname

# node3 上
ssh aliyun hostname
```
