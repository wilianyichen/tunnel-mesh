#!/usr/bin/env python3
"""
隧道管理 - autossh 长连接
"""

import argparse
import subprocess
import time
from pathlib import Path


class TunnelManager:
    """隧道管理器"""
    
    def __init__(self):
        self.tunnel_dir = Path.home() / ".hermes" / "topology" / "tunnels"
        self.tunnel_dir.mkdir(parents=True, exist_ok=True)
    
    def establish(self, from_server: str, to_server: str, via: str = None,
                  local_port: int = None, remote_port: int = 22):
        """建立隧道"""
        
        # 生成本地端口
        if not local_port:
            local_port = self._get_free_port()
        
        # 构建命令
        if via:
            # 多跳隧道
            cmd = [
                "autossh", "-M", "0",
                "-o", "ServerAliveInterval=30",
                "-o", "ServerAliveCountMax=3",
                "-o", "ExitOnForwardFailure=yes",
                "-J", via,
                "-L", f"{local_port}:{to_server}:{remote_port}",
                "-N", "-f",
                from_server
            ]
        else:
            # 直连隧道
            cmd = [
                "autossh", "-M", "0",
                "-o", "ServerAliveInterval=30",
                "-o", "ServerAliveCountMax=3",
                "-o", "ExitOnForwardFailure=yes",
                "-L", f"{local_port}:{to_server}:{remote_port}",
                "-N", "-f",
                from_server
            ]
        
        print(f"建立隧道: {from_server} → {to_server}")
        if via:
            print(f"  跳板: {via}")
        print(f"  本地端口: {local_port}")
        
        # 检查 autossh
        if not self._check_autossh():
            print("✗ autossh 未安装")
            print("  安装: apt install autossh 或 yum install autossh")
            return False
        
        # 启动隧道
        try:
            subprocess.run(cmd, check=True)
            
            # 保存隧道信息
            self._save_tunnel(from_server, to_server, local_port, via)
            
            print(f"✓ 隧道已建立")
            print(f"  连接命令: ssh -p {local_port} user@localhost")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"✗ 建立失败: {e}")
            return False
    
    def list_tunnels(self):
        """列出所有隧道"""
        tunnels = self._load_tunnels()
        
        if not tunnels:
            print("暂无隧道")
            return
        
        print("隧道列表:")
        print("-" * 60)
        for t in tunnels:
            status = "🟢" if self._check_tunnel(t["local_port"]) else "🔴"
            print(f"{status} {t['from']} → {t['to']}")
            print(f"   本地端口: {t['local_port']}")
            if t.get("via"):
                print(f"   跳板: {t['via']}")
    
    def stop(self, from_server: str, to_server: str):
        """停止隧道"""
        tunnels = self._load_tunnels()
        
        for t in tunnels:
            if t["from"] == from_server and t["to"] == to_server:
                # 查找并杀死进程
                result = subprocess.run(
                    ["lsof", "-ti", f":{t['local_port']}"],
                    capture_output=True, text=True
                )
                
                if result.stdout.strip():
                    pids = result.stdout.strip().split("\n")
                    for pid in pids:
                        subprocess.run(["kill", pid])
                    print(f"✓ 已停止隧道: {from_server} → {to_server}")
                else:
                    print(f"隧道未运行: {from_server} → {to_server}")
                
                # 从列表移除
                tunnels.remove(t)
                self._save_all_tunnels(tunnels)
                return
        
        print(f"未找到隧道: {from_server} → {to_server}")
    
    def _check_autossh(self) -> bool:
        """检查 autossh 是否安装"""
        result = subprocess.run(["which", "autossh"], capture_output=True)
        return result.returncode == 0
    
    def _get_free_port(self, start: int = 2200) -> int:
        """获取空闲端口"""
        import socket
        
        for port in range(start, 65535):
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.bind(("", port))
                    return port
            except OSError:
                continue
        
        return start
    
    def _check_tunnel(self, port: int) -> bool:
        """检查隧道是否运行"""
        result = subprocess.run(
            ["lsof", "-ti", f":{port}"],
            capture_output=True
        )
        return result.returncode == 0
    
    def _save_tunnel(self, from_server: str, to_server: str, 
                     local_port: int, via: str = None):
        """保存隧道信息"""
        tunnels = self._load_tunnels()
        
        tunnels.append({
            "from": from_server,
            "to": to_server,
            "local_port": local_port,
            "via": via,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        })
        
        self._save_all_tunnels(tunnels)
    
    def _load_tunnels(self) -> list:
        """加载隧道列表"""
        tunnel_file = self.tunnel_dir / "tunnels.json"
        if tunnel_file.exists():
            import json
            with open(tunnel_file) as f:
                return json.load(f)
        return []
    
    def _save_all_tunnels(self, tunnels: list):
        """保存所有隧道"""
        import json
        tunnel_file = self.tunnel_dir / "tunnels.json"
        with open(tunnel_file, "w") as f:
            json.dump(tunnels, f, indent=2)


def main():
    parser = argparse.ArgumentParser(description="隧道管理")
    subparsers = parser.add_subparsers(dest="command")
    
    # establish
    est_parser = subparsers.add_parser("establish", help="建立隧道")
    est_parser.add_argument("--from", dest="from_server", required=True)
    est_parser.add_argument("--to", dest="to_server", required=True)
    est_parser.add_argument("--via", help="跳板服务器")
    est_parser.add_argument("--local-port", type=int, help="本地端口")
    
    # list
    subparsers.add_parser("list", help="列出隧道")
    
    # stop
    stop_parser = subparsers.add_parser("stop", help="停止隧道")
    stop_parser.add_argument("--from", dest="from_server", required=True)
    stop_parser.add_argument("--to", dest="to_server", required=True)
    
    args = parser.parse_args()
    
    manager = TunnelManager()
    
    if args.command == "establish":
        manager.establish(args.from_server, args.to_server, args.via, args.local_port)
    elif args.command == "list":
        manager.list_tunnels()
    elif args.command == "stop":
        manager.stop(args.from_server, args.to_server)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
