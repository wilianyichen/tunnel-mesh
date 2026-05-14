#!/usr/bin/env python3
"""
隧道管理交互式终端
支持增删改查反向隧道服务器
"""

import os
import sys
import json
import time
from pathlib import Path
from typing import Dict, List, Optional


class TunnelManagerInteractive:
    """交互式隧道管理"""
    
    def __init__(self):
        self.config_dir = Path.home() / ".hermes" / "topology"
        self.ports_file = self.config_dir / "jump-ports.json"
        self.config_dir.mkdir(parents=True, exist_ok=True)
    
    def clear(self):
        """清屏"""
        os.system('clear' if os.name == 'posix' else 'cls')
    
    def run(self):
        """主循环"""
        while True:
            self.clear()
            self.show_header()
            self.show_status()
            self.show_menu()
            
            choice = input("\n选择: ").strip().lower()
            
            if choice == '1':
                self.add_tunnel()
            elif choice == '2':
                self.list_tunnels()
            elif choice == '3':
                self.edit_tunnel()
            elif choice == '4':
                self.delete_tunnel()
            elif choice == '5':
                self.test_tunnel()
            elif choice == '6':
                self.manage_keys()
            elif choice == '7':
                self.export_config()
            elif choice == 'q':
                print("\n再见!")
                break
            else:
                input("无效选择，按 Enter 继续...")
    
    def show_header(self):
        """显示标题"""
        print("=" * 60)
        print("   反向隧道管理终端")
        print("   (交互式模式)")
        print("=" * 60)
    
    def show_status(self):
        """显示状态"""
        config = self._load_config()
        tunnels = config.get("allocated_ports", {})
        
        print(f"\n跳板服务器: {config.get('jump_host', '未配置')}")
        print(f"跳板 IP: {config.get('jump_ip', '未配置')}")
        print(f"已配置隧道: {len(tunnels)} 个")
        print("-" * 60)
    
    def show_menu(self):
        """显示菜单"""
        print("\n操作菜单:")
        print("  [1] 添加隧道")
        print("  [2] 列出所有隧道")
        print("  [3] 编辑隧道")
        print("  [4] 删除隧道")
        print("  [5] 测试隧道连接")
        print("  [6] 密钥管理")
        print("  [7] 导出配置")
        print("  [q] 退出")
    
    def add_tunnel(self):
        """添加隧道"""
        self.clear()
        print("=" * 60)
        print("   添加新隧道")
        print("=" * 60)
        
        # 检查跳板配置
        config = self._load_config()
        if not config.get("jump_ip"):
            print("\n请先配置跳板服务器")
            jump_host = input("跳板主机名: ").strip()
            jump_ip = input("跳板 IP: ").strip()
            jump_user = input("跳板用户 [root]: ").strip() or "root"
            
            config["jump_host"] = jump_host
            config["jump_ip"] = jump_ip
            config["jump_user"] = jump_user
            config["allocated_ports"] = {}
            self._save_config(config)
            print("✓ 跳板已配置\n")
        
        # 收集信息
        target_name = input("目标服务器名称: ").strip()
        if not target_name:
            input("名称不能为空，按 Enter 返回...")
            return
        
        target_ip = input("目标 IP: ").strip()
        target_port = input("目标端口 [22]: ").strip() or "22"
        target_user = input("目标用户 [root]: ").strip() or "root"
        
        print("\n平台类型:")
        print("  [1] Linux")
        print("  [2] Windows")
        platform_choice = input("选择 [1]: ").strip() or "1"
        platform = "linux" if platform_choice == "1" else "windows"
        
        # 分配端口
        port = self._allocate_port(target_name, target_ip, int(target_port),
                                    target_user, platform)
        
        print(f"\n✓ 隧道已添加")
        print(f"  目标: {target_name}")
        print(f"  端口: {port}")
        print(f"  平台: {platform}")
        
        input("\n按 Enter 继续...")
    
    def list_tunnels(self):
        """列出隧道"""
        self.clear()
        print("=" * 60)
        print("   隧道列表")
        print("=" * 60)
        
        config = self._load_config()
        tunnels = config.get("allocated_ports", {})
        
        if not tunnels:
            print("\n暂无隧道")
        else:
            print(f"\n{'名称':<15} {'端口':<8} {'地址':<25} {'平台':<10}")
            print("-" * 60)
            
            for name, info in sorted(tunnels.items(), key=lambda x: x[1]["port"]):
                addr = f"{info['target_ip']}:{info['target_port']}"
                print(f"{name:<15} {info['port']:<8} {addr:<25} {info['platform']:<10}")
            
            print("=" * 60)
        
        input("\n按 Enter 继续...")
    
    def edit_tunnel(self):
        """编辑隧道"""
        self.clear()
        print("=" * 60)
        print("   编辑隧道")
        print("=" * 60)
        
        config = self._load_config()
        tunnels = config.get("allocated_ports", {})
        
        if not tunnels:
            print("\n暂无隧道")
            input("按 Enter 继续...")
            return
        
        print("\n现有隧道:")
        for name in tunnels:
            print(f"  - {name}")
        
        target = input("\n选择要编辑的隧道: ").strip()
        
        if target not in tunnels:
            input("未找到，按 Enter 返回...")
            return
        
        info = tunnels[target]
        print(f"\n当前配置:")
        print(f"  IP: {info['target_ip']}")
        print(f"  端口: {info['target_port']}")
        print(f"  用户: {info['target_user']}")
        print(f"  平台: {info['platform']}")
        
        print("\n输入新值（留空保持不变）:")
        new_ip = input(f"IP [{info['target_ip']}]: ").strip()
        new_port = input(f"端口 [{info['target_port']}]: ").strip()
        new_user = input(f"用户 [{info['target_user']}]: ").strip()
        
        if new_ip:
            info['target_ip'] = new_ip
        if new_port:
            info['target_port'] = int(new_port)
        if new_user:
            info['target_user'] = new_user
        
        info['updated_at'] = time.strftime("%Y-%m-%dT%H:%M:%SZ")
        
        self._save_config(config)
        print("\n✓ 已更新")
        input("按 Enter 继续...")
    
    def delete_tunnel(self):
        """删除隧道"""
        self.clear()
        print("=" * 60)
        print("   删除隧道")
        print("=" * 60)
        
        config = self._load_config()
        tunnels = config.get("allocated_ports", {})
        
        if not tunnels:
            print("\n暂无隧道")
            input("按 Enter 继续...")
            return
        
        print("\n现有隧道:")
        for name in tunnels:
            print(f"  - {name} (端口 {tunnels[name]['port']})")
        
        target = input("\n选择要删除的隧道: ").strip()
        
        if target not in tunnels:
            input("未找到，按 Enter 返回...")
            return
        
        confirm = input(f"确认删除 {target}? [y/N]: ").strip().lower()
        
        if confirm == 'y':
            port = tunnels[target]['port']
            del tunnels[target]
            self._save_config(config)
            print(f"\n✓ 已删除: {target} (端口 {port})")
        else:
            print("\n已取消")
        
        input("按 Enter 继续...")
    
    def test_tunnel(self):
        """测试隧道"""
        self.clear()
        print("=" * 60)
        print("   测试隧道连接")
        print("=" * 60)
        
        config = self._load_config()
        tunnels = config.get("allocated_ports", {})
        
        if not tunnels:
            print("\n暂无隧道")
            input("按 Enter 继续...")
            return
        
        print("\n现有隧道:")
        for name, info in tunnels.items():
            print(f"  - {name} (端口 {info['port']})")
        
        target = input("\n选择要测试的隧道: ").strip()
        
        if target not in tunnels:
            input("未找到，按 Enter 返回...")
            return
        
        info = tunnels[target]
        jump_ip = config.get('jump_ip', 'unknown')
        
        print(f"\n测试命令:")
        print(f"  ssh -p {info['port']} {info['target_user']}@{jump_ip}")
        
        input("\n按 Enter 继续...")
    
    def manage_keys(self):
        """密钥管理"""
        self.clear()
        print("=" * 60)
        print("   密钥管理")
        print("=" * 60)
        
        print("\n操作:")
        print("  [1] 生成新密钥")
        print("  [2] 列出密钥")
        print("  [3] 部署公钥")
        print("  [4] 显示公钥")
        print("  [q] 返回")
        
        choice = input("\n选择: ").strip().lower()
        
        if choice == '1':
            name = input("密钥名称: ").strip()
            if name:
                import subprocess
                key_file = Path.home() / ".ssh" / f"id_{name}"
                subprocess.run([
                    "ssh-keygen", "-t", "ed25519",
                    "-f", str(key_file),
                    "-N", "",
                    "-C", f"{name}@tunnel"
                ])
                print(f"\n✓ 密钥已生成: {key_file}")
        
        elif choice == '2':
            ssh_dir = Path.home() / ".ssh"
            print("\n现有密钥:")
            for f in ssh_dir.glob("id_*"):
                if f.suffix != ".pub":
                    print(f"  - {f.stem}")
        
        elif choice == '3':
            key_name = input("密钥名称: ").strip()
            target = input("目标服务器: ").strip()
            if key_name and target:
                pub_file = Path.home() / ".ssh" / f"id_{key_name}.pub"
                if pub_file.exists():
                    print(f"\n手动部署命令:")
                    print(f"ssh-copy-id -i {pub_file} {target}")
        
        input("\n按 Enter 继续...")
    
    def export_config(self):
        """导出配置"""
        self.clear()
        print("=" * 60)
        print("   导出配置")
        print("=" * 60)
        
        config = self._load_config()
        
        print("\n导出格式:")
        print("  [1] JSON")
        print("  [2] YAML")
        print("  [3] SSH Config")
        
        choice = input("\n选择: ").strip()
        
        if choice == '1':
            print(json.dumps(config, indent=2))
        elif choice == '2':
            import yaml
            print(yaml.dump(config, default_flow_style=False))
        elif choice == '3':
            jump_ip = config.get('jump_ip', 'unknown')
            for name, info in config.get('allocated_ports', {}).items():
                print(f"Host {name}")
                print(f"    HostName {jump_ip}")
                print(f"    Port {info['port']}")
                print(f"    User {info['target_user']}")
                print()
        
        input("\n按 Enter 继续...")
    
    def _allocate_port(self, name: str, ip: str, port: int, 
                       user: str, platform: str) -> int:
        """分配端口"""
        config = self._load_config()
        
        if "allocated_ports" not in config:
            config["allocated_ports"] = {}
        
        # 查找空闲端口
        used = {v["port"] for v in config["allocated_ports"].values()}
        
        for p in range(2201, 2300):
            if p not in used:
                config["allocated_ports"][name] = {
                    "port": p,
                    "target_ip": ip,
                    "target_port": port,
                    "target_user": user,
                    "platform": platform,
                    "status": "pending",
                    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
                }
                self._save_config(config)
                return p
        
        return 2201
    
    def _load_config(self) -> Dict:
        """加载配置"""
        if self.ports_file.exists():
            with open(self.ports_file) as f:
                return json.load(f)
        return {}
    
    def _save_config(self, config: Dict):
        """保存配置"""
        with open(self.ports_file, 'w') as f:
            json.dump(config, f, indent=2)


def main():
    manager = TunnelManagerInteractive()
    manager.run()


if __name__ == "__main__":
    main()