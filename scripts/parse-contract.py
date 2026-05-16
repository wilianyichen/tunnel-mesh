#!/usr/bin/env python3
"""
契约文书解析脚本 - Windows 端
解析对方发来的契约文书，自动建立连接配置

支持两种契约类型：
- CONTRACT_TYPE=1: 平等契约（双向直连）
- CONTRACT_TYPE=2: 主仆契约（单向，需中转服务器）
"""

import sys
import os
import json
from pathlib import Path


def parse_contract(contract_text: str) -> dict:
    """解析契约文书"""
    
    config = {}
    
    lines = contract_text.strip().split('\n')
    
    for line in lines:
        line = line.strip()
        
        if line.startswith('===') or not line:
            continue
        
        if '=' in line:
            key, value = line.split('=', 1)
            config[key.strip()] = value.strip()
    
    return config


def main():
    if len(sys.argv) < 2:
        print("[错误] 请粘贴完整的契约文书")
        sys.exit(1)
    
    contract_text = sys.argv[1]
    config = parse_contract(contract_text)
    
    # 验证契约类型
    contract_type = config.get('CONTRACT_TYPE', '2')
    
    if contract_type == '1':
        print("契约类型: 平等契约（双向直连）")
    else:
        print("契约类型: 主仆契约（单向连接）")
    
    # 验证必要字段
    required = ['SERVER_NAME', 'SERVER_IP', 'SERVER_PORT']
    for field in required:
        if field not in config:
            print(f"[错误] 缺少字段: {field}")
            sys.exit(1)
    
    # 如果是主仆契约，需要中转服务器信息
    if contract_type != '1':
        if 'RELAY_IP' not in config:
            print("[错误] 主仆契约需要中转服务器信息（RELAY_IP）")
            sys.exit(1)
    
    # 保存配置
    config_dir = Path("C:/tunnel-mesh/config")
    config_dir.mkdir(parents=True, exist_ok=True)
    
    config_file = config_dir / "tunnels.json"
    if config_file.exists():
        with open(config_file, encoding='utf-8') as f:
            tunnels_config = json.load(f)
    else:
        tunnels_config = {"relay": {}, "tunnels": {}}
    
    server_name = config['SERVER_NAME']
    
    if contract_type == '1':
        # 平等契约：直连
        tunnels_config["tunnels"][server_name] = {
            "type": "direct",
            "target_ip": config['SERVER_IP'],
            "target_port": int(config['SERVER_PORT']),
            "contract_type": "equal",
            "status": "pending"
        }
        
        # 生成直连 SSH config
        ssh_config = (
            f"\n# 平等契约 - {server_name}\n"
            f"Host {server_name}\n"
            f"    HostName {config['SERVER_IP']}\n"
            f"    Port {config['SERVER_PORT']}\n"
            f"    StrictHostKeyChecking no\n"
        )
        
        ssh_config_path = Path.home() / ".ssh" / "config"
        if not ssh_config_path.exists():
            ssh_config_path.touch()
        
        # 检查是否已存在
        existing = ssh_config_path.read_text(encoding='utf-8')
        if f"Host {server_name}" not in existing:
            with open(ssh_config_path, 'a', encoding='utf-8') as f:
                f.write(ssh_config)
            print(f"[提示] SSH config 已更新")
        
        print("")
        print("   平等契约缔结完成！")
        print(f"   对方: {config['SERVER_IP']}:{config['SERVER_PORT']}")
        print("")
        print("   [连接命令]")
        print(f"   ssh {server_name}")
        
    else:
        # 主仆契约：需要中转服务器
        tunnels_config["relay"] = {
            "name": config.get('RELAY_NAME', 'aliyun'),
            "ip": config['RELAY_IP'],
            "port": int(config.get('RELAY_PORT', 22)),
            "user": config.get('RELAY_USER', 'root')
        }
        
        # 自动分配端口
        used_ports = {v.get("port", 0) for v in tunnels_config["tunnels"].values()}
        port = 2201
        while port in used_ports:
            port += 1
        
        tunnels_config["tunnels"][server_name] = {
            "type": "reverse_tunnel",
            "target_ip": config['SERVER_IP'],
            "target_port": int(config['SERVER_PORT']),
            "port": port,
            "contract_type": "master_servant",
            "status": "pending"
        }
        
        # 保存公钥
        if 'PUB_KEY' in config and config['PUB_KEY']:
            pub_key_file = config_dir / f"{server_name}.pub"
            with open(pub_key_file, 'w', encoding='utf-8') as f:
                f.write(config['PUB_KEY'])
            print(f"[提示] 公钥已保存: {pub_key_file}")
        
        # 生成 SSH config
        relay_ip = config['RELAY_IP']
        ssh_config = (
            f"\n# 主仆契约 - {server_name}（通过契约之塔 {config.get('RELAY_NAME', 'aliyun')}）\n"
            f"Host {server_name}\n"
            f"    HostName {relay_ip}\n"
            f"    Port {port}\n"
            f"    StrictHostKeyChecking no\n"
        )
        
        ssh_config_path = Path.home() / ".ssh" / "config"
        if not ssh_config_path.exists():
            ssh_config_path.touch()
        
        existing = ssh_config_path.read_text(encoding='utf-8')
        if f"Host {server_name}" not in existing:
            with open(ssh_config_path, 'a', encoding='utf-8') as f:
                f.write(ssh_config)
        
        print("")
        print("   主仆契约缔结完成！")
        print(f"   仆端: {config['SERVER_IP']}:{config['SERVER_PORT']}")
        print(f"   契约之塔: {config['RELAY_IP']} (端口 {port})")
        print("")
        print("   [连接命令]")
        print(f"   ssh {server_name}")
    
    # 保存配置
    with open(config_file, 'w', encoding='utf-8') as f:
        json.dump(tunnels_config, f, indent=2, ensure_ascii=False)
    
    print("")
    print("[下一步] 选择「契约之仪」启动连接")


if __name__ == "__main__":
    main()
