#!/usr/bin/env python3
"""
Linux 隧道服务管理
autossh + systemd 服务
"""

import argparse
import subprocess
import time
from pathlib import Path
from typing import Dict, Optional
import json


class LinuxTunnelService:
    """Linux 隧道服务管理"""
    
    def __init__(self):
        self.config_dir = Path.home() / ".hermes" / "topology"
        self.ports_file = self.config_dir / "jump-ports.json"
        self.service_dir = Path("/etc/systemd/system")
        self.ssh_dir = Path.home() / ".ssh"
    
    def install(self, target_name: str, jump_host: str, jump_user: str = "root",
                jump_ip: str = None, local_port: int = None, remote_port: int = 22,
                key_file: str = None):
        """安装隧道服务"""
        
        # 获取端口配置
        if local_port is None:
            local_port = self._get_allocated_port(target_name)
        
        if jump_ip is None:
            jump_ip = self._get_jump_ip()
        
        # 检查 autossh
        if not self._check_autossh():
            print("✗ autossh 未安装")
            print("  安装: apt install autossh 或 yum install autossh")
            return False
        
        # 生成密钥（如果需要）
        if key_file is None:
            key_file = self._ensure_key(target_name)
        
        # 创建 systemd 服务
        service_name = f"tunnel-{target_name}"
        service_file = self.service_dir / f"{service_name}.service"
        
        service_content = f"""[Unit]
Description=SSH Tunnel to {target_name}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={Path.home().name}
Environment="AUTOSSH_GATETIME=0"
ExecStart=/usr/bin/autossh -M 0 -N \\
  -o ServerAliveInterval=30 \\
  -o ServerAliveCountMax=3 \\
  -o ExitOnForwardFailure=yes \\
  -o StrictHostKeyChecking=no \\
  -i {key_file} \\
  -R {local_port}:localhost:{remote_port} \\
  {jump_user}@{jump_ip}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
"""
        
        # 写入服务文件（需要 sudo）
        print(f"创建 systemd 服务: {service_name}")
        print("-" * 60)
        print(service_content)
        print("-" * 60)
        
        print("\n请执行以下命令（需要 sudo 权限）:")
        print(f"""
sudo tee {service_file} > /dev/null << 'EOF'
{service_content}EOF

sudo systemctl daemon-reload
sudo systemctl enable {service_name}
sudo systemctl start {service_name}
""")
        
        return True
    
    def uninstall(self, target_name: str):
        """卸载隧道服务"""
        service_name = f"tunnel-{target_name}"
        service_file = self.service_dir / f"{service_name}.service"
        
        print("请执行以下命令（需要 sudo 权限）:")
        print(f"""
sudo systemctl stop {service_name}
sudo systemctl disable {service_name}
sudo rm -f {service_file}
sudo systemctl daemon-reload
""")
    
    def status(self, target_name: str):
        """查看服务状态"""
        service_name = f"tunnel-{target_name}"
        
        result = subprocess.run(
            ["systemctl", "status", service_name],
            capture_output=True, text=True
        )
        
        print(result.stdout)
    
    def list_services(self):
        """列出所有隧道服务"""
        result = subprocess.run(
            ["systemctl", "list-units", "--type=service", "--all"],
            capture_output=True, text=True
        )
        
        print("隧道服务列表:")
        print("-" * 60)
        
        for line in result.stdout.split("\n"):
            if "tunnel-" in line:
                print(line)
    
    def test_connection(self, target_name: str):
        """测试隧道连接"""
        local_port = self._get_allocated_port(target_name)
        jump_ip = self._get_jump_ip()
        
        print(f"测试连接: {target_name}")
        print(f"命令: ssh -p {local_port} user@{jump_ip}")
        
        # 在跳板服务器上测试
        result = subprocess.run(
            ["ssh", jump_ip, f"nc -z localhost {local_port} && echo OK || echo FAIL"],
            capture_output=True, text=True
        )
        
        if "OK" in result.stdout:
            print("✓ 端口可达")
        else:
            print("✗ 端口不可达")
    
    def _check_autossh(self) -> bool:
        """检查 autossh"""
        result = subprocess.run(["which", "autossh"], capture_output=True)
        return result.returncode == 0
    
    def _ensure_key(self, target_name: str) -> str:
        """确保密钥存在"""
        key_name = f"id_tunnel_{target_name}"
        key_file = self.ssh_dir / key_name
        
        if not key_file.exists():
            print(f"生成密钥: {key_name}")
            subprocess.run([
                "ssh-keygen", "-t", "ed25519",
                "-f", str(key_file),
                "-N", "",
                "-C", f"tunnel-{target_name}"
            ])
        
        return str(key_file)
    
    def _get_allocated_port(self, target_name: str) -> int:
        """获取分配的端口"""
        if self.ports_file.exists():
            with open(self.ports_file) as f:
                config = json.load(f)
            return config["allocated_ports"].get(target_name, {}).get("port", 2201)
        return 2201
    
    def _get_jump_ip(self) -> str:
        """获取跳板 IP"""
        if self.ports_file.exists():
            with open(self.ports_file) as f:
                config = json.load(f)
            return config.get("jump_ip", "8.131.61.234")
        return "8.131.61.234"


def main():
    parser = argparse.ArgumentParser(description="Linux 隧道服务管理")
    subparsers = parser.add_subparsers(dest="command")
    
    # install
    install_parser = subparsers.add_parser("install", help="安装隧道服务")
    install_parser.add_argument("--target", required=True, help="目标服务器名")
    install_parser.add_argument("--jump-host", help="跳板主机")
    install_parser.add_argument("--jump-user", default="root", help="跳板用户")
    install_parser.add_argument("--jump-ip", help="跳板IP")
    install_parser.add_argument("--local-port", type=int, help="本地端口（跳板上）")
    install_parser.add_argument("--remote-port", type=int, default=22, help="远程端口")
    install_parser.add_argument("--key", help="SSH 密钥文件")
    
    # uninstall
    uninstall_parser = subparsers.add_parser("uninstall", help="卸载隧道服务")
    uninstall_parser.add_argument("--target", required=True, help="目标服务器名")
    
    # status
    status_parser = subparsers.add_parser("status", help="查看服务状态")
    status_parser.add_argument("--target", required=True, help="目标服务器名")
    
    # list
    subparsers.add_parser("list", help="列出所有隧道服务")
    
    # test
    test_parser = subparsers.add_parser("test", help="测试隧道连接")
    test_parser.add_argument("--target", required=True, help="目标服务器名")
    
    args = parser.parse_args()
    
    service = LinuxTunnelService()
    
    if args.command == "install":
        service.install(args.target, args.jump_host, args.jump_user,
                        args.jump_ip, args.local_port, args.remote_port, args.key)
    elif args.command == "uninstall":
        service.uninstall(args.target)
    elif args.command == "status":
        service.status(args.target)
    elif args.command == "list":
        service.list_services()
    elif args.command == "test":
        service.test_connection(args.target)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()