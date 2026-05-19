#!/bin/bash
# recover.sh - 从 config.json 重建 SSH config
do_recover() {
    CONFIG=$(config_load)
    echo ""; echo "════════════════════════════════════════"; echo "  重新生成 SSH config"; echo "════════════════════════════════════════"
    config_json_get "
import json,sys,os;d=json.load(sys.stdin)
for c in d.get('contracts',[]):
    n=c['servant'];t=c.get('type','?')
    s=d['servers'].get(n,{})
    if t=='direct':print(f'Host {n}\\n    HostName {s.get(\"ip\",\"?\")}\\n    Port {s.get(\"port\",22)}\\n    User {s.get(\"user\",\"root\")}\\n    StrictHostKeyChecking no\\n')
    elif t=='reverse':print(f'Host {n}\\n    HostName localhost\\n    Port {c[\"tunnel_port\"]}\\n    User {s.get(\"user\",\"root\")}\\n    StrictHostKeyChecking no\\n    HostKeyAlias {n}\\n')
"
    read -p "是否自动添加到 ~/.ssh/config？[y/N]: " A
    [ "$A" != "y" ] && [ "$A" != "Y" ] && return
    cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null
    config_json_get "
import json,sys,os;d=json.load(sys.stdin)
with open(os.path.expanduser('~/.ssh/config'),'a') as f:
    f.write('\\n# Tunnel Mesh - 恢复\\n')
    for c in d.get('contracts',[]):
        n=c['servant'];t=c.get('type','?');s=d['servers'].get(n,{})
        if t=='direct':f.write(f'Host {n}\\n    HostName {s.get(\"ip\",\"?\")}\\n    Port {s.get(\"port\",22)}\\n    User {s.get(\"user\",\"root\")}\\n    StrictHostKeyChecking no\\n')
        elif t=='reverse':f.write(f'Host {n}\\n    HostName localhost\\n    Port {c[\"tunnel_port\"]}\\n    User {s.get(\"user\",\"root\")}\\n    StrictHostKeyChecking no\\n    HostKeyAlias {n}\\n')
"
    chmod 600 ~/.ssh/config 2>/dev/null; echo "✓ SSH config 已恢复"
}
