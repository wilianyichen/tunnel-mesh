#!/usr/bin/env python3
"""
Windows 隧道服务管理
ssh.exe + Windows Service
注意：避免编码问题，使用 UTF-8
"""

import argparse
import subprocess
import time
from pathlib import Path
from typing import Dict, Optional
import json
import os


class WindowsTunnelService:
    """Windows 隧道服务管理"""
    
    def __init__(self):
        # Windows 路径
        self.config_dir = Path.home() / ".hermes" / "topology"
        self.ports_file = self.config_dir / "jump-ports.json"
        self.ssh_dir = Path.home() / ".ssh"
        
        # Windows SSH 路径
        self.ssh_exe = "C:\\Windows\\System32\\OpenSSH\\ssh.exe"
        self.sc_exe = "C:\\Windows\\System32\\sc.exe"
    
    def install(self, target_name: str, jump_ip: str, jump_user: str = "root",
                local_port: int = None, remote_port: int = 22,
                key_file: str = None):
        """安装隧道服务"""
        
        # 设置 UTF-8 编码
        os.system("chcp 65001 > nul 2>&1")
        
        # 获取端口
        if local_port is None:
            local_port = self._get_allocated_port(target_name)
        
        # 生成密钥
        if key_file is None:
            key_file = self._ensure_key(target_name)
        
        # Windows 密钥路径转换
        key_file_win = str(key_file).replace("/", "\\")
        
        service_name = f"Tunnel-{target_name}"
        
        print("=" * 60)
        print(f"Windows 隧道服务安装: {target_name}")
        print("=" * 60)
        
        # 生成 PowerShell 脚本
        ps_script = self._generate_ps_script(
            target_name, jump_ip, jump_user, local_port, remote_port, key_file_win
        )
        
        print("\n【PowerShell 安装脚本】")
        print("-" * 60)
        print(ps_script)
        print("-" * 60)
        
        # 保存脚本
        script_file = self.config_dir / f"install-tunnel-{target_name}.ps1"
        with open(script_file, 'w', encoding='utf-8') as f:
            f.write(ps_script)
        
        print(f"\n脚本已保存: {script_file}")
        print("\n请在 PowerShell (管理员) 中执行:")
        print(f"  powershell -ExecutionPolicy Bypass -File {script_file}")
        
        return True
    
    def _generate_ps_script(self, target_name: str, jump_ip: str, 
                            jump_user: str, local_port: int, 
                            remote_port: int, key_file: str) -> str:
        """生成 PowerShell 安装脚本"""
        
        service_name = f"Tunnel-{target_name}"
        
        script = f"""# Windows 隧道服务安装脚本
# UTF-8 编码
# 目标: {target_name}

# 设置编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF-8

# 参数
$ServiceName = "{service_name}"
$JumpIP = "{jump_ip}"
$JumpUser = "{jump_user}"
$LocalPort = {local_port}
$RemotePort = {remote_port}
$KeyFile = "{key_file}"

# SSH 命令
$SSHPath = "C:\\Windows\\System32\\OpenSSH\\ssh.exe"
$SSHArgs = "-N -i $KeyFile -R $LocalPort:localhost:$RemotePort $JumpUser@$JumpIP"

# 检查 SSH
if (-not (Test-Path $SSHPath)) {{
    Write-Host "SSH 未找到: $SSHPath"
    Write-Host "请安装 OpenSSH for Windows"
    exit 1
}}

# 检查密钥
if (-not (Test-Path $KeyFile)) {{
    Write-Host "密钥未找到: $KeyFile"
    exit 1
}}

# 停止已存在的服务
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {{
    Write-Host "停止已存在的服务..."
    Stop-Service -Name $ServiceName -Force
    sc.exe delete $ServiceName
    Start-Sleep -Seconds 2
}}

# 创建服务
Write-Host "创建服务: $ServiceName"
$BinPath = "`"$SSHPath`" $SSHArgs"

sc.exe create $ServiceName binPath= $BinPath start= auto

# 配置服务恢复
sc.exe failure $ServiceName reset= 86400 actions= restart/10000/restart/10000/restart/10000

# 启动服务
Write-Host "启动服务..."
Start-Service -Name $ServiceName

# 检查状态
$status = Get-Service -Name $ServiceName
Write-Host "服务状态: $($status.Status)"

Write-Host ""
Write-Host "安装完成!"
Write-Host "访问命令: ssh -p $LocalPort user@$JumpIP"
"""
        
        return script
    
    def uninstall(self, target_name: str):
        """卸载服务"""
        service_name = f"Tunnel-{target_name}"
        
        print("请在 PowerShell (管理员) 中执行:")
        print(f"""
Stop-Service -Name "{service_name}" -Force
sc.exe delete "{service_name}"
""")
    
    def status(self, target_name: str):
        """查看状态"""
        service_name = f"Tunnel-{target_name}"
        
        print("请在 PowerShell 中执行:")
        print(f"Get-Service -Name '{service_name}'")
    
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
            ], encoding='utf-8')
        
        return str(key_file)
    
    def _get_allocated_port(self, target_name: str) -> int:
        """获取分配的端口"""
        if self.ports_file.exists():
            with open(self.ports_file, encoding='utf-8') as f:
                config = json.load(f)
            return config["allocated_ports"].get(target_name, {}).get("port", 2201)
        return 2201


def main():
    parser = argparse.ArgumentParser(description="Windows 隧道服务管理")
    subparsers = parser.add_subparsers(dest="command")
    
    # install
    install_parser = subparsers.add_parser("install", help="安装隧道服务")
    install_parser.add_argument("--target", required=True)
    install_parser.add_argument("--jump-ip", required=True)
    install_parser.add_argument("--jump-user", default="root")
    install_parser.add_argument("--local-port", type=int)
    install_parser.add_argument("--remote-port", type=int, default=22)
    install_parser.add_argument("--key")
    
    # uninstall
    uninstall_parser = subparsers.add_parser("uninstall", help="卸载服务")
    uninstall_parser.add_argument("--target", required=True)
    
    # status
    status_parser = subparsers.add_parser("status", help="查看状态")
    status_parser.add_argument("--target", required=True)
    
    args = parser.parse_args()
    
    service = WindowsTunnelService()
    
    if args.command == "install":
        service.install(args.target, args.jump_ip, args.jump_user,
                        args.local_port, args.remote_port, args.key)
    elif args.command == "uninstall":
        service.uninstall(args.target)
    elif args.command == "status":
        service.status(args.target)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()