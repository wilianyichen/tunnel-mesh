#!/usr/bin/env python3
"""
SSH 密钥管理
支持生成、分发、配置
"""

import argparse
import subprocess
import os
from pathlib import Path
from typing import List, Optional
import json


class KeyManager:
    """SSH 密钥管理"""
    
    def __init__(self):
        self.ssh_dir = Path.home() / ".ssh"
        self.ssh_dir.mkdir(mode=0o700, exist_ok=True)
        
        self.config_dir = Path.home() / ".hermes" / "topology"
        self.keys_file = self.config_dir / "keys.json"
        self.config_dir.mkdir(parents=True, exist_ok=True)
    
    def generate(self, name: str, key_type: str = "ed25519", 
                 comment: str = None, passphrase: str = ""):
        """生成密钥"""
        
        key_file = self.ssh_dir / f"id_{name}"
        
        if key_file.exists():
            print(f"密钥已存在: {name}")
            return str(key_file)
        
        # 构建命令
        cmd = [
            "ssh-keygen",
            "-t", key_type,
            "-f", str(key_file),
            "-N", passphrase
        ]
        
        if comment:
            cmd.extend(["-C", comment])
        else:
            cmd.extend(["-C", f"{name}@tunnel"])
        
        print(f"生成密钥: {name}")
        subprocess.run(cmd, check=True)
        
        # 记录密钥
        self._register_key(name, str(key_file), key_type)
        
        print(f"✓ 密钥已生成: {key_file}")
        return str(key_file)
    
    def list_keys(self):
        """列出所有密钥"""
        keys = self._load_keys()
        
        print("SSH 密钥列表:")
        print("=" * 60)
        
        # 扫描 .ssh 目录
        for f in self.ssh_dir.glob("id_*"):
            if f.suffix == ".pub":
                continue
            
            pub_file = f.with_suffix(".pub")
            if pub_file.exists():
                name = f.stem
                key_info = keys.get(name, {})
                
                print(f"  {name}")
                print(f"    文件: {f}")
                if key_info.get("deployed_to"):
                    print(f"    已部署到: {', '.join(key_info['deployed_to'])}")
                print()
        
        print("=" * 60)
    
    def deploy(self, key_name: str, target: str, target_user: str = "root",
               method: str = "ssh-copy-id"):
        """部署公钥到目标服务器"""
        
        key_file = self.ssh_dir / f"id_{key_name}"
        pub_file = key_file.with_suffix(".pub")
        
        if not pub_file.exists():
            print(f"公钥不存在: {key_name}")
            return False
        
        pub_key = pub_file.read_text().strip()
        
        print(f"部署公钥: {key_name} → {target}")
        
        if method == "ssh-copy-id":
            # 使用 ssh-copy-id
            cmd = [
                "ssh-copy-id",
                "-i", str(pub_file),
                f"{target_user}@{target}"
            ]
            
            result = subprocess.run(cmd)
            
            if result.returncode == 0:
                self._mark_deployed(key_name, target)
                print(f"✓ 公钥已部署")
                return True
            else:
                print(f"✗ 部署失败")
                return False
        
        elif method == "manual":
            # 手动方式
            print("\n请手动执行以下命令:")
            print(f"ssh {target_user}@{target} 'echo \"{pub_key}\" >> ~/.ssh/authorized_keys'")
            return True
        
        return False
    
    def show_pubkey(self, key_name: str):
        """显示公钥"""
        pub_file = self.ssh_dir / f"id_{key_name}.pub"
        
        if not pub_file.exists():
            print(f"公钥不存在: {key_name}")
            return
        
        print(f"公钥: {key_name}")
        print("-" * 60)
        print(pub_file.read_text())
        print("-" * 60)
    
    def show_fingerprint(self, key_name: str):
        """显示指纹"""
        key_file = self.ssh_dir / f"id_{key_name}"
        
        if not key_file.exists():
            print(f"密钥不存在: {key_name}")
            return
        
        result = subprocess.run(
            ["ssh-keygen", "-lf", str(key_file)],
            capture_output=True, text=True
        )
        
        print(f"指纹: {key_name}")
        print("-" * 60)
        print(result.stdout)
    
    def remove(self, key_name: str):
        """删除密钥"""
        key_file = self.ssh_dir / f"id_{key_name}"
        pub_file = key_file.with_suffix(".pub")
        
        if not key_file.exists():
            print(f"密钥不存在: {key_name}")
            return
        
        confirm = input(f"确认删除 {key_name}? [y/N]: ").strip().lower()
        
        if confirm == 'y':
            key_file.unlink()
            if pub_file.exists():
                pub_file.unlink()
            
            self._unregister_key(key_name)
            print(f"✓ 已删除: {key_name}")
        else:
            print("已取消")
    
    def _register_key(self, name: str, path: str, key_type: str):
        """注册密钥"""
        keys = self._load_keys()
        keys[name] = {
            "path": path,
            "type": key_type,
            "created_at": __import__('time').strftime("%Y-%m-%dT%H:%M:%SZ"),
            "deployed_to": []
        }
        self._save_keys(keys)
    
    def _unregister_key(self, name: str):
        """注销密钥"""
        keys = self._load_keys()
        if name in keys:
            del keys[name]
        self._save_keys(keys)
    
    def _mark_deployed(self, key_name: str, target: str):
        """标记已部署"""
        keys = self._load_keys()
        if key_name in keys:
            if "deployed_to" not in keys[key_name]:
                keys[key_name]["deployed_to"] = []
            if target not in keys[key_name]["deployed_to"]:
                keys[key_name]["deployed_to"].append(target)
        self._save_keys(keys)
    
    def _load_keys(self) -> dict:
        """加载密钥记录"""
        if self.keys_file.exists():
            with open(self.keys_file) as f:
                return json.load(f)
        return {}
    
    def _save_keys(self, keys: dict):
        """保存密钥记录"""
        with open(self.keys_file, 'w') as f:
            json.dump(keys, f, indent=2)


def main():
    parser = argparse.ArgumentParser(description="SSH 密钥管理")
    subparsers = parser.add_subparsers(dest="command")
    
    # generate
    gen_parser = subparsers.add_parser("generate", help="生成密钥")
    gen_parser.add_argument("--name", required=True, help="密钥名称")
    gen_parser.add_argument("--type", default="ed25519", help="密钥类型")
    gen_parser.add_argument("--comment", help="注释")
    
    # list
    subparsers.add_parser("list", help="列出密钥")
    
    # deploy
    deploy_parser = subparsers.add_parser("deploy", help="部署公钥")
    deploy_parser.add_argument("--key", required=True, help="密钥名称")
    deploy_parser.add_argument("--target", required=True, help="目标服务器")
    deploy_parser.add_argument("--user", default="root", help="目标用户")
    deploy_parser.add_argument("--method", default="ssh-copy-id", 
                                choices=["ssh-copy-id", "manual"])
    
    # show
    show_parser = subparsers.add_parser("show", help="显示密钥")
    show_parser.add_argument("--key", required=True)
    show_parser.add_argument("--type", default="pubkey", 
                              choices=["pubkey", "fingerprint"])
    
    # remove
    remove_parser = subparsers.add_parser("remove", help="删除密钥")
    remove_parser.add_argument("--key", required=True)
    
    args = parser.parse_args()
    
    manager = KeyManager()
    
    if args.command == "generate":
        manager.generate(args.name, args.type, args.comment)
    elif args.command == "list":
        manager.list_keys()
    elif args.command == "deploy":
        manager.deploy(args.key, args.target, args.user, args.method)
    elif args.command == "show":
        if args.type == "pubkey":
            manager.show_pubkey(args.key)
        else:
            manager.show_fingerprint(args.key)
    elif args.command == "remove":
        manager.remove(args.key)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()