#!/usr/bin/env python3
"""
跳板服务器端口管理器
管理反向隧道的端口分配
"""

import argparse
import json
import yaml
import subprocess
from pathlib import Path
from typing import Dict, List, Optional
import time


class JumpServerManager:
    """跳板服务器端口管理"""
    
    def __init__(self):
        self.config_dir = Path.home() / ".hermes" / "topology"
        self.ports_file = self.config_dir / "jump-ports.json"
        self.config_dir.mkdir(parents=True, exist_ok=True)
        
        # 端口范围
        self.port_start = 2201
        self.port_end = 2299
    
    def init_jump_server(self, jump_host: str, jump_ip: str, jump_user: str = "root"):
        """初始化跳板服务器"""
        config = {
            "jump_host": jump_host,
            "jump_ip": jump_ip,
            "jump_user": jump_user,
            "port_range": [self.port_start, self.port_end],
            "allocated_ports": {},
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        
        with open(self.ports_file, 'w') as f:
            json.dump(config, f, indent=2)
        
        print(f"✓ 跳板服务器已初始化")
        print(f"  主机: {jump_host}")
        print(f"  IP: {jump_ip}")
        print(f"  端口范围: {self.port_start}-{self.port_end}")
    
    def allocate_port(self, target_name: str, target_ip: str, target_port: int = 22,
                      target_user: str = "root", platform: str = "linux") -> int:
        """分配端口给目标服务器"""
        config = self._load_config()
        
        # 检查是否已分配
        if target_name in config["allocated_ports"]:
            port = config["allocated_ports"][target_name]["port"]
            print(f"端口已分配: {target_name} → {port}")
            return port
        
        # 查找空闲端口
        used_ports = {v["port"] for v in config["allocated_ports"].values()}
        
        for port in range(self.port_start, self.port_end + 1):
            if port not in used_ports:
                # 分配端口
                config["allocated_ports"][target_name] = {
                    "port": port,
                    "target_ip": target_ip,
                    "target_port": target_port,
                    "target_user": target_user,
                    "platform": platform,
                    "status": "pending",
                    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
                }
                
                self._save_config(config)
                
                print(f"✓ 端口已分配")
                print(f"  目标: {target_name}")
                print(f"  端口: {port}")
                print(f"  地址: {target_ip}:{target_port}")
                print(f"  平台: {platform}")
                
                return port
        
        raise RuntimeError("无可用端口")
    
    def release_port(self, target_name: str):
        """释放端口"""
        config = self._load_config()
        
        if target_name not in config["allocated_ports"]:
            print(f"未找到: {target_name}")
            return
        
        port = config["allocated_ports"][target_name]["port"]
        del config["allocated_ports"][target_name]
        
        self._save_config(config)
        print(f"✓ 端口已释放: {target_name} (端口 {port})")
    
    def list_ports(self):
        """列出所有端口分配"""
        config = self._load_config()
        
        if not config.get("allocated_ports"):
            print("暂无端口分配")
            return
        
        print("端口分配列表:")
        print("=" * 70)
        print(f"{'目标':<15} {'端口':<8} {'地址':<25} {'平台':<10} {'状态':<10}")
        print("-" * 70)
        
        for name, info in sorted(config["allocated_ports"].items(), 
                                  key=lambda x: x[1]["port"]):
            addr = f"{info['target_ip']}:{info['target_port']}"
            print(f"{name:<15} {info['port']:<8} {addr:<25} {info['platform']:<10} {info['status']:<10}")
        
        print("=" * 70)
        print(f"跳板服务器: {config.get('jump_host', 'N/A')} ({config.get('jump_ip', 'N/A')})")
    
    def show_config(self, target_name: str):
        """显示目标服务器的配置命令"""
        config = self._load_config()
        
        if target_name not in config["allocated_ports"]:
            print(f"未找到: {target_name}")
            return
        
        info = config["allocated_ports"][target_name]
        jump = config
        
        port = info["port"]
        jump_ip = jump["jump_ip"]
        jump_user = jump["jump_user"]
        target_ip = info["target_ip"]
        target_port = info["target_port"]
        target_user = info["target_user"]
        platform = info["platform"]
        
        print("=" * 70)
        print(f"目标服务器: {target_name}")
        print("=" * 70)
        
        if platform == "linux":
            print("\n【Linux 隧道命令】")
            print(f"autossh -M 0 -f -N \\")
            print(f"  -o ServerAliveInterval=30 \\")
            print(f"  -o ServerAliveCountMax=3 \\")
            print(f"  -o ExitOnForwardFailure=yes \\")
            print(f"  -R {port}:{target_ip}:{target_port} \\")
            print(f"  {jump_user}@{jump_ip}")
            
            print("\n【systemd 服务文件】")
            print(f"[Unit]")
            print(f"Description=Tunnel to {target_name}")
            print(f"After=network.target")
            print()
            print(f"[Service]")
            print(f"Type=simple")
            print(f"User={target_user}")
            print(f"ExecStart=/usr/bin/autossh -M 0 -N \\")
            print(f"  -o ServerAliveInterval=30 \\")
            print(f"  -o ServerAliveCountMax=3 \\")
            print(f"  -o ExitOnForwardFailure=yes \\")
            print(f"  -R {port}:{target_ip}:{target_port} \\")
            print(f"  {jump_user}@{jump_ip}")
            print(f"Restart=always")
            print(f"RestartSec=10")
            print()
            print(f"[Install]")
            print(f"WantedBy=multi-user.target")
            
        elif platform == "windows":
            print("\n【Windows 隧道命令 (PowerShell)】")
            print(f"ssh -N -R {port}:{target_ip}:{target_port} {jump_user}@{jump_ip}")
            
            print("\n【Windows 服务安装】")
            print(f"# 1. 创建服务")
            print(f"sc create Tunnel-{target_name} \\")
            print(f'  binPath= "C:\\Windows\\System32\\OpenSSH\\ssh.exe -N -R {port}:{target_ip}:{target_port} {jump_user}@{jump_ip}"')
            print(f"  start= auto")
            print()
            print(f"# 2. 启动服务")
            print(f"sc start Tunnel-{target_name}")
        
        print("\n【跳板服务器访问命令】")
        print(f"ssh -p {port} {target_user}@{jump_ip}")
        
        print("=" * 70)
    
    def export_all(self, format: str = "yaml"):
        """导出所有配置"""
        config = self._load_config()
        
        if format == "yaml":
            print(yaml.dump(config, default_flow_style=False))
        else:
            print(json.dumps(config, indent=2))
    
    def _load_config(self) -> Dict:
        """加载配置"""
        if self.ports_file.exists():
            with open(self.ports_file) as f:
                return json.load(f)
        return {
            "jump_host": "unknown",
            "jump_ip": "unknown",
            "jump_user": "root",
            "port_range": [self.port_start, self.port_end],
            "allocated_ports": {}
        }
    
    def _save_config(self, config: Dict):
        """保存配置"""
        with open(self.ports_file, 'w') as f:
            json.dump(config, f, indent=2)


def main():
    parser = argparse.ArgumentParser(description="跳板服务器端口管理")
    subparsers = parser.add_subparsers(dest="command")
    
    # init
    init_parser = subparsers.add_parser("init", help="初始化跳板服务器")
    init_parser.add_argument("--host", required=True, help="跳板主机名")
    init_parser.add_argument("--ip", required=True, help="跳板IP地址")
    init_parser.add_argument("--user", default="root", help="跳板用户")
    
    # allocate
    alloc_parser = subparsers.add_parser("allocate", help="分配端口")
    alloc_parser.add_argument("--target", required=True, help="目标服务器名")
    alloc_parser.add_argument("--ip", required=True, help="目标IP")
    alloc_parser.add_argument("--port", type=int, default=22, help="目标端口")
    alloc_parser.add_argument("--user", default="root", help="目标用户")
    alloc_parser.add_argument("--platform", default="linux", 
                               choices=["linux", "windows"], help="平台类型")
    
    # release
    release_parser = subparsers.add_parser("release", help="释放端口")
    release_parser.add_argument("--target", required=True, help="目标服务器名")
    
    # list
    subparsers.add_parser("list", help="列出端口分配")
    
    # show
    show_parser = subparsers.add_parser("show", help="显示配置")
    show_parser.add_argument("--target", required=True, help="目标服务器名")
    
    # export
    export_parser = subparsers.add_parser("export", help="导出配置")
    export_parser.add_argument("--format", default="yaml", choices=["yaml", "json"])
    
    args = parser.parse_args()
    
    manager = JumpServerManager()
    
    if args.command == "init":
        manager.init_jump_server(args.host, args.ip, args.user)
    elif args.command == "allocate":
        manager.allocate_port(args.target, args.ip, args.port, args.user, args.platform)
    elif args.command == "release":
        manager.release_port(args.target)
    elif args.command == "list":
        manager.list_ports()
    elif args.command == "show":
        manager.show_config(args.target)
    elif args.command == "export":
        manager.export_all(args.format)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()