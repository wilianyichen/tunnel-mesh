#!/usr/bin/env python3
"""
Windows 批量隧道服务管理器
在 Windows 上批量创建、启动、停止反向隧道服务

使用方法:
    python windows-tunnel-batch.py init --jump aliyun --ip YOUR_JUMP_SERVER_IP
    python windows-tunnel-batch.py add --name node3 --target YOUR_TARGET_IP:22
    python windows-tunnel-batch.py install-all
    python windows-tunnel-batch.py start-all
    python windows-tunnel-batch.py status
"""

import argparse
import subprocess
import json
import time
import os
from pathlib import Path
from typing import Dict, List, Optional


class WindowsTunnelBatch:
    """Windows 批量隧道服务管理"""
    
    def __init__(self):
        self.config_dir = Path("C:/tunnel-mesh")
        self.config_file = self.config_dir / "tunnels.json"
        self.scripts_dir = self.config_dir / "scripts"
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.scripts_dir.mkdir(parents=True, exist_ok=True)
        
        # SSH 路径
        self.ssh_exe = "C:\\Windows\\System32\\OpenSSH\\ssh.exe"
    
    def init_jump(self, jump_name: str, jump_ip: str, jump_user: str = "root",
                  key_file: str = None):
        """初始化跳板服务器配置"""
        
        config = self._load_config()
        config["jump"] = {
            "name": jump_name,
            "ip": jump_ip,
            "user": jump_user,
            "key": key_file or f"C:\\Users\\{os.getenv('USERNAME')}\\.ssh\\id_{jump_name}"
        }
        config["tunnels"] = config.get("tunnels", {})
        
        self._save_config(config)
        
        print(f"✓ 跳板服务器已配置")
        print(f"  名称: {jump_name}")
        print(f"  IP: {jump_ip}")
        print(f"  用户: {jump_user}")
        print(f"  密钥: {config['jump']['key']}")
    
    def add_tunnel(self, name: str, target: str, port: int = None, 
                   platform: str = "linux"):
        """添加隧道配置
        
        Args:
            name: 隧道名称
            target: 目标地址 (IP:PORT)
            port: 跳板上的端口（自动分配）
            platform: 目标平台 linux/windows
        """
        
        config = self._load_config()
        
        if "jump" not in config:
            print("✗ 请先初始化跳板服务器: init --jump xxx --ip xxx")
            return False
        
        # 解析目标地址
        if ":" in target:
            target_ip, target_port = target.rsplit(":", 1)
            target_port = int(target_port)
        else:
            target_ip = target
            target_port = 22
        
        # 自动分配端口
        if port is None:
            port = self._allocate_port(config)
        
        config["tunnels"][name] = {
            "target_ip": target_ip,
            "target_port": target_port,
            "port": port,
            "platform": platform,
            "status": "pending",
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        
        self._save_config(config)
        
        print(f"✓ 隧道已添加")
        print(f"  名称: {name}")
        print(f"  目标: {target_ip}:{target_port}")
        print(f"  端口: {port}")
        print(f"  访问: ssh -p {port} user@{config['jump']['ip']}")
        
        return True
    
    def remove_tunnel(self, name: str):
        """移除隧道"""
        config = self._load_config()
        
        if name not in config.get("tunnels", {}):
            print(f"✗ 未找到: {name}")
            return False
        
        # 先停止服务
        self.stop_tunnel(name)
        
        port = config["tunnels"][name]["port"]
        del config["tunnels"][name]
        self._save_config(config)
        
        print(f"✓ 已移除: {name} (端口 {port})")
        return True
    
    def install_all(self):
        """安装所有隧道服务"""
        config = self._load_config()
        
        if "jump" not in config:
            print("✗ 请先初始化跳板服务器")
            return False
        
        tunnels = config.get("tunnels", {})
        if not tunnels:
            print("✗ 没有配置隧道")
            return False
        
        print(f"=== 批量安装 {len(tunnels)} 个隧道服务 ===\n")
        
        for name, info in tunnels.items():
            self._install_service(name, info, config["jump"])
            print()
        
        print("=== 安装完成 ===")
        return True
    
    def install_tunnel(self, name: str):
        """安装单个隧道服务"""
        config = self._load_config()
        
        if name not in config.get("tunnels", {}):
            print(f"✗ 未找到: {name}")
            return False
        
        return self._install_service(name, config["tunnels"][name], config["jump"])
    
    def _install_service(self, name: str, info: Dict, jump: Dict) -> bool:
        """安装单个服务"""
        
        service_name = f"Tunnel-{name}"
        
        print(f"安装服务: {service_name}")
        
        # 生成启动脚本
        script_path = self.scripts_dir / f"start-{name}.ps1"
        self._generate_start_script(name, info, jump, script_path)
        
        # 创建 Windows 服务
        # 使用 sc.exe 创建服务
        bin_path = f'powershell.exe -ExecutionPolicy Bypass -File "{script_path}"'
        
        # 先删除已存在的服务
        subprocess.run(
            ["sc.exe", "delete", service_name],
            capture_output=True
        )
        time.sleep(1)
        
        # 创建服务
        result = subprocess.run([
            "sc.exe", "create", service_name,
            f"binPath= {bin_path}",
            "start= auto",
            f"DisplayName= Tunnel Mesh - {name}"
        ], capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"  ✗ 创建服务失败: {result.stderr}")
            return False
        
        # 配置服务恢复策略
        subprocess.run([
            "sc.exe", "failure", service_name,
            "reset= 86400",
            "actions= restart/10000/restart/10000/restart/10000"
        ], capture_output=True)
        
        print(f"  ✓ 服务已创建: {service_name}")
        print(f"  启动: net start {service_name}")
        print(f"  停止: net stop {service_name}")
        
        return True
    
    def _generate_start_script(self, name: str, info: Dict, jump: Dict, 
                                script_path: Path):
        """生成启动脚本"""
        
        # SSH 隧道命令
        # -R [跳板端口]:[目标IP]:[目标端口]
        ssh_args = [
            "-i", jump["key"],
            "-R", f"{info['port']}:{info['target_ip']}:{info['target_port']}",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ServerAliveInterval=60",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-N",
            f"{jump['user']}@{jump['ip']}"
        ]
        
        script = f"""# Tunnel Mesh 启动脚本
# 隧道: {name}
# 生成时间: {time.strftime('%Y-%m-%d %H:%M:%S')}

$ErrorActionPreference = "Stop"

Write-Host "Starting tunnel: {name}"

# SSH 隧道命令
$SSHPath = "{self.ssh_exe}"
$SSHArgs = @(
    "-i", "{jump['key']}",
    "-R", "{info['port']}:{info['target_ip']}:{info['target_port']}",
    "-o", "StrictHostKeyChecking=no",
    "-o", "ServerAliveInterval=60",
    "-o", "ServerAliveCountMax=3",
    "-o", "ExitOnForwardFailure=yes",
    "-N",
    "{jump['user']}@{jump['ip']}"
)

# 检查密钥
if (-not (Test-Path "{jump['key']}")) {{
    Write-Error "密钥不存在: {jump['key']}"
    exit 1
}}

# 启动 SSH 隧道
while ($true) {{
    Write-Host "Connecting to {jump['ip']}..."
    
    $process = Start-Process -FilePath $SSHPath -ArgumentList $SSHArgs -PassThru -NoNewWindow
    
    # 等待进程退出
    $process.WaitForExit()
    
    $exitCode = $process.ExitCode
    Write-Host "SSH exited with code: $exitCode"
    
    # 如果正常退出（用户手动停止），则退出
    if ($exitCode -eq 0) {{
        break
    }}
    
    # 否则等待后重连
    Write-Host "Reconnecting in 5 seconds..."
    Start-Sleep -Seconds 5
}}
"""
        
        with open(script_path, 'w', encoding='utf-8') as f:
            f.write(script)
        
        print(f"  脚本: {script_path}")
    
    def start_all(self):
        """启动所有隧道服务"""
        config = self._load_config()
        tunnels = config.get("tunnels", {})
        
        print(f"=== 启动 {len(tunnels)} 个隧道服务 ===\n")
        
        for name in tunnels:
            self.start_tunnel(name)
        
        print("\n=== 启动完成 ===")
    
    def start_tunnel(self, name: str):
        """启动单个隧道"""
        service_name = f"Tunnel-{name}"
        
        result = subprocess.run(
            ["net", "start", service_name],
            capture_output=True, text=True
        )
        
        if result.returncode == 0:
            print(f"✓ 已启动: {name}")
        else:
            print(f"✗ 启动失败: {name} - {result.stderr.strip()}")
    
    def stop_all(self):
        """停止所有隧道服务"""
        config = self._load_config()
        tunnels = config.get("tunnels", {})
        
        print(f"=== 停止 {len(tunnels)} 个隧道服务 ===\n")
        
        for name in tunnels:
            self.stop_tunnel(name)
        
        print("\n=== 停止完成 ===")
    
    def stop_tunnel(self, name: str):
        """停止单个隧道"""
        service_name = f"Tunnel-{name}"
        
        result = subprocess.run(
            ["net", "stop", service_name],
            capture_output=True, text=True
        )
        
        if result.returncode == 0:
            print(f"✓ 已停止: {name}")
        else:
            print(f"✗ 停止失败: {name}")
    
    def status(self):
        """查看所有隧道状态"""
        config = self._load_config()
        
        print("=" * 70)
        print("   Tunnel Mesh 状态")
        print("=" * 70)
        
        jump = config.get("jump", {})
        if jump:
            print(f"\n跳板服务器: {jump.get('name')} ({jump.get('ip')})")
        
        tunnels = config.get("tunnels", {})
        if not tunnels:
            print("\n暂无隧道配置")
            return
        
        print(f"\n隧道列表 ({len(tunnels)} 个):")
        print("-" * 70)
        print(f"{'名称':<15} {'端口':<8} {'目标':<25} {'服务状态':<10}")
        print("-" * 70)
        
        for name, info in sorted(tunnels.items(), key=lambda x: x[1]["port"]):
            target = f"{info['target_ip']}:{info['target_port']}"
            
            # 检查服务状态
            service_name = f"Tunnel-{name}"
            result = subprocess.run(
                ["sc.exe", "query", service_name],
                capture_output=True, text=True
            )
            
            if "RUNNING" in result.stdout:
                status = "运行中"
            elif "STOPPED" in result.stdout:
                status = "已停止"
            else:
                status = "未安装"
            
            print(f"{name:<15} {info['port']:<8} {target:<25} {status:<10}")
        
        print("=" * 70)
    
    def list_tunnels(self):
        """列出所有隧道"""
        config = self._load_config()
        tunnels = config.get("tunnels", {})
        
        if not tunnels:
            print("暂无隧道配置")
            return
        
        print(f"\n隧道列表 ({len(tunnels)} 个):")
        print("-" * 60)
        
        for name, info in sorted(tunnels.items(), key=lambda x: x[1]["port"]):
            target = f"{info['target_ip']}:{info['target_port']}"
            print(f"  {name:<15} → 端口 {info['port']:<5} → {target}")
        
        print("-" * 60)
    
    def export_ssh_config(self):
        """导出 SSH config"""
        config = self._load_config()
        jump = config.get("jump", {})
        tunnels = config.get("tunnels", {})
        
        if not jump or not tunnels:
            print("没有配置跳板或隧道")
            return
        
        print("# Tunnel Mesh SSH Config")
        print(f"# 跳板: {jump['name']} ({jump['ip']})\n")
        
        for name, info in sorted(tunnels.items(), key=lambda x: x[1]["port"]):
            print(f"Host {name}")
            print(f"    HostName {jump['ip']}")
            print(f"    Port {info['port']}")
            print(f"    User root")
            print(f"    StrictHostKeyChecking no")
            print()
    
    def _allocate_port(self, config: Dict) -> int:
        """分配端口"""
        used = {v["port"] for v in config.get("tunnels", {}).values()}
        
        for port in range(2201, 2300):
            if port not in used:
                return port
        
        return 2201
    
    def _load_config(self) -> Dict:
        """加载配置"""
        if self.config_file.exists():
            with open(self.config_file, encoding='utf-8') as f:
                return json.load(f)
        return {}
    
    def _save_config(self, config: Dict):
        """保存配置"""
        with open(self.config_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)


def main():
    parser = argparse.ArgumentParser(description="Windows 批量隧道服务管理")
    subparsers = parser.add_subparsers(dest="command")
    
    # init
    init_parser = subparsers.add_parser("init", help="初始化跳板服务器")
    init_parser.add_argument("--jump", required=True, help="跳板名称")
    init_parser.add_argument("--ip", required=True, help="跳板 IP")
    init_parser.add_argument("--user", default="root", help="跳板用户")
    init_parser.add_argument("--key", help="SSH 密钥路径")
    
    # add
    add_parser = subparsers.add_parser("add", help="添加隧道")
    add_parser.add_argument("--name", required=True, help="隧道名称")
    add_parser.add_argument("--target", required=True, help="目标地址 IP:PORT")
    add_parser.add_argument("--port", type=int, help="跳板端口（自动分配）")
    add_parser.add_argument("--platform", default="linux", help="平台类型")
    
    # remove
    remove_parser = subparsers.add_parser("remove", help="移除隧道")
    remove_parser.add_argument("--name", required=True)
    
    # install
    subparsers.add_parser("install-all", help="安装所有隧道服务")
    install_parser = subparsers.add_parser("install", help="安装单个隧道服务")
    install_parser.add_argument("--name", required=True)
    
    # start
    subparsers.add_parser("start-all", help="启动所有隧道服务")
    start_parser = subparsers.add_parser("start", help="启动单个隧道")
    start_parser.add_argument("--name", required=True)
    
    # stop
    subparsers.add_parser("stop-all", help="停止所有隧道服务")
    stop_parser = subparsers.add_parser("stop", help="停止单个隧道")
    stop_parser.add_argument("--name", required=True)
    
    # status
    subparsers.add_parser("status", help="查看状态")
    subparsers.add_parser("list", help="列出隧道")
    subparsers.add_parser("export", help="导出 SSH config")
    
    args = parser.parse_args()
    
    manager = WindowsTunnelBatch()
    
    if args.command == "init":
        manager.init_jump(args.jump, args.ip, args.user, args.key)
    elif args.command == "add":
        manager.add_tunnel(args.name, args.target, args.port, args.platform)
    elif args.command == "remove":
        manager.remove_tunnel(args.name)
    elif args.command == "install-all":
        manager.install_all()
    elif args.command == "install":
        manager.install_tunnel(args.name)
    elif args.command == "start-all":
        manager.start_all()
    elif args.command == "start":
        manager.start_tunnel(args.name)
    elif args.command == "stop-all":
        manager.stop_all()
    elif args.command == "stop":
        manager.stop_tunnel(args.name)
    elif args.command == "status":
        manager.status()
    elif args.command == "list":
        manager.list_tunnels()
    elif args.command == "export":
        manager.export_ssh_config()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
