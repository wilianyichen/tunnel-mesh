#!/usr/bin/env python3
"""
配置解析脚本 - Windows 端
解析从服务器导出的配置文本
"""

import sys
import os
import json
from pathlib import Path

def parse_config(config_text: str) -> dict:
    """解析配置文本"""
    
    config = {}
    
    lines = config_text.strip().split('\n')
    
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
        print("用法: python parse-config.py <配置文本>")
        sys.exit(1)
    
    config_text = sys.argv[1]
    config = parse_config(config_text)
    
    # 验证必要字段
    required = ['SERVER_NAME', 'SERVER_IP', 'SERVER_PORT', 'RELAY_IP']
    for field in required:
        if field not in config:
            print(f"[错误] 缺少字段: {field}")
            sys.exit(1)
    
    # 保存配置
    config_dir = Path("C:/tunnel-mesh/config")
    config_dir.mkdir(parents=True, exist_ok=True)
    
    # 加载现有配置
    config_file = config_dir / "tunnels.json"
    if config_file.exists():
        with open(config_file, encoding='utf-8') as f:
            tunnels_config = json.load(f)
    else:
        tunnels_config = {"relay": {}, "tunnels": {}}
    
    # 更新中转服务器配置
    tunnels_config["relay"] = {
        "name": config.get('RELAY_NAME', 'aliyun'),
        "ip": config['RELAY_IP'],
        "port": int(config.get('RELAY_PORT', 22)),
        "user": config.get('RELAY_USER', 'root')
    }
    
    # 添加隧道
    server_name = config['SERVER_NAME']
    tunnels_config["tunnels"][server_name] = {
        "target_ip": config['SERVER_IP'],
        "target_port": int(config['SERVER_PORT']),
        "port": 2201 + len(tunnels_config["tunnels"]),
        "platform": "linux",
        "status": "pending"
    }
    
    # 保存公钥（如果有）
    if 'PUB_KEY' in config and config['PUB_KEY']:
        pub_key_file = config_dir / f"{server_name}.pub"
        with open(pub_key_file, 'w') as f:
            f.write(config['PUB_KEY'])
        print(f"[提示] 公钥已保存: {pub_key_file}")
    
    # 保存配置
    with open(config_file, 'w', encoding='utf-8') as f:
        json.dump(tunnels_config, f, indent=2, ensure_ascii=False)
    
    print(f"[成功] 隧道配置已添加: {server_name}")
    print(f"       目标: {config['SERVER_IP']}:{config['SERVER_PORT']}")
    print(f"       端口: {tunnels_config['tunnels'][server_name]['port']}")
    print("")
    print("[下一步] 选择 [3] 启动所有隧道")

if __name__ == "__main__":
    main()
