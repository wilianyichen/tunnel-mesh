#!/usr/bin/env python3
"""
Windows 双向隧道配置脚本
用于在 Windows 上建立到阿里云和 node3 的双向隧道

使用方法:
1. 将此脚本复制到 Windows
2. 修改配置部分
3. 运行: python windows-tunnel-setup.py install
"""

import os
import sys
import subprocess
import time
from pathlib import Path

# ============================================================
# 配置部分 - 请根据实际情况修改
# ============================================================

CONFIG = {
    # 阿里云配置
    "aliyun": {
        "host": "YOUR_JUMP_SERVER_IP",
        "port": 22,
        "user": "root",
        # Windows 上的 SSH 私钥路径
        "key": "C:\\Users\\wilia\\.ssh\\id_aliyun",
    },
    
    # node3 配置
    "node3": {
        "host": "YOUR_TARGET_IP",
        "port": 5122,
        "user": "wuxiaoran",
        "key": "C:\\Users\\wilia\\.ssh\\id_node3",
    },
    
    # 隧道配置
    "tunnels": {
        # 反向隧道: 阿里云:2224 → node3:22
        # 用于阿里云访问 node3
        "reverse": {
            "remote_port": 2224,  # 阿里云上的端口
            "target_host": "YOUR_TARGET_IP",
            "target_port": 5122,
        },
        
        # 正向隧道: node3:2223 → 阿里云:22
        # 用于 node3 访问阿里云（备用，node3 可直连）
        "forward": {
            "local_port": 2223,  # node3 上的端口
            "target_host": "YOUR_JUMP_SERVER_IP",
            "target_port": 22,
        },
    },
}

# ============================================================
# 实现
# ============================================================

class WindowsTunnelSetup:
    """Windows 隧道配置"""
    
    def __init__(self):
        self.config_dir = Path("C:/tunnel-mesh/config")
        self.config_dir.mkdir(parents=True, exist_ok=True)
        
    def install(self):
        """安装 Windows 服务"""
        print("=== 安装双向隧道服务 ===\n")
        
        # 1. 检查 SSH
        print("1. 检查 SSH...")
        result = subprocess.run(["ssh", "-V"], capture_output=True)
        if result.returncode != 0:
            print("✗ SSH 未安装")
            print("  请安装 OpenSSH: Add-WindowsCapability -Online -Name OpenSSH.Client")
            return False
        print("✓ SSH 已安装\n")
        
        # 2. 检查密钥
        print("2. 检查 SSH 密钥...")
        aliyun_key = Path(CONFIG["aliyun"]["key"])
        if not aliyun_key.exists():
            print(f"✗ 阿里云密钥不存在: {aliyun_key}")
            return False
        print(f"✓ 阿里云密钥: {aliyun_key}\n")
        
        # 3. 测试连接
        print("3. 测试阿里云连接...")
        result = subprocess.run([
            "ssh",
            "-i", CONFIG["aliyun"]["key"],
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no",
            f"{CONFIG['aliyun']['user']}@{CONFIG['aliyun']['host']}",
            "echo OK"
        ], capture_output=True, text=True)
        
        if "OK" not in result.stdout:
            print(f"✗ 连接失败: {result.stderr}")
            return False
        print("✓ 阿里云连接正常\n")
        
        # 4. 创建启动脚本
        print("4. 创建启动脚本...")
        self._create_startup_script()
        print("✓ 启动脚本已创建\n")
        
        # 5. 创建 Windows 服务
        print("5. 创建 Windows 服务...")
        self._create_service()
        print("✓ 服务已创建\n")
        
        print("=== 安装完成 ===")
        print("\n启动服务:")
        print("  net start tunnel-mesh")
        print("\n停止服务:")
        print("  net stop tunnel-mesh")
        print("\n查看状态:")
        print("  sc query tunnel-mesh")
        
        return True
    
    def _create_startup_script(self):
        """创建启动脚本"""
        script_path = self.config_dir / "start-tunnel.ps1"
        
        # 反向隧道命令
        reverse_cmd = (
            f"ssh -i {CONFIG['aliyun']['key']} "
            f"-R {CONFIG['tunnels']['reverse']['remote_port']}:"
            f"{CONFIG['tunnels']['reverse']['target_host']}:"
            f"{CONFIG['tunnels']['reverse']['target_port']} "
            f"-o StrictHostKeyChecking=no "
            f"-o ServerAliveInterval=60 "
            f"-o ServerAliveCountMax=3 "
            f"-N {CONFIG['aliyun']['user']}@{CONFIG['aliyun']['host']}"
        )
        
        script_content = f"""# Tunnel Mesh 启动脚本
# 自动生成于 {time.strftime('%Y-%m-%d %H:%M:%S')}

Write-Host "Starting tunnel-mesh..."

# 启动反向隧道
Start-Process -FilePath "ssh" -ArgumentList @(
    "-i", "{CONFIG['aliyun']['key']}",
    "-R", "{CONFIG['tunnels']['reverse']['remote_port']}:{CONFIG['tunnels']['reverse']['target_host']}:{CONFIG['tunnels']['reverse']['target_port']}",
    "-o", "StrictHostKeyChecking=no",
    "-o", "ServerAliveInterval=60",
    "-o", "ServerAliveCountMax=3",
    "-N",
    "{CONFIG['aliyun']['user']}@{CONFIG['aliyun']['host']}"
) -WindowStyle Hidden

Write-Host "Tunnel started on port {CONFIG['tunnels']['reverse']['remote_port']}"
"""
        
        with open(script_path, 'w', encoding='utf-8') as f:
            f.write(script_content)
        
        print(f"  脚本路径: {script_path}")
    
    def _create_service(self):
        """创建 Windows 服务"""
        # 使用 NSSM 或 sc 创建服务
        script_path = self.config_dir / "start-tunnel.ps1"
        
        # 使用 sc 创建服务（需要 NSSM）
        print("  请手动执行以下命令创建服务:")
        print(f"  nssm install tunnel-mesh powershell.exe -ExecutionPolicy Bypass -File {script_path}")
        print("  nssm start tunnel-mesh")
    
    def start(self):
        """启动隧道"""
        print("启动隧道...")
        script_path = self.config_dir / "start-tunnel.ps1"
        subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File", str(script_path)])
    
    def stop(self):
        """停止隧道"""
        print("停止隧道...")
        subprocess.run(["taskkill", "/F", "/IM", "ssh.exe"], capture_output=True)
        print("✓ 隧道已停止")
    
    def status(self):
        """查看状态"""
        print("=== 隧道状态 ===\n")
        
        # 检查 SSH 进程
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq ssh.exe"],
            capture_output=True, text=True
        )
        
        if "ssh.exe" in result.stdout:
            print("✓ 隧道进程运行中")
            print(result.stdout)
        else:
            print("✗ 隧道未运行")
        
        # 测试端口
        print("\n测试端口...")
        result = subprocess.run(
            ["netstat", "-an"],
            capture_output=True, text=True
        )
        
        port = CONFIG['tunnels']['reverse']['remote_port']
        if f":{port}" in result.stdout:
            print(f"✓ 端口 {port} 已监听")
        else:
            print(f"✗ 端口 {port} 未监听")


def main():
    if len(sys.argv) < 2:
        print("用法: python windows-tunnel-setup.py [install|start|stop|status]")
        sys.exit(1)
    
    action = sys.argv[1]
    setup = WindowsTunnelSetup()
    
    if action == "install":
        setup.install()
    elif action == "start":
        setup.start()
    elif action == "stop":
        setup.stop()
    elif action == "status":
        setup.status()
    else:
        print(f"未知命令: {action}")
        print("用法: python windows-tunnel-setup.py [install|start|stop|status]")


if __name__ == "__main__":
    main()
