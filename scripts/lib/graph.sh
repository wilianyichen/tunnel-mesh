#!/bin/bash
# ========================================
# 图管理 - 从 config.json 读图 + 路径搜索
# ========================================

# 从 config 构建邻接表
graph_from_config() {
    CONFIG=$(config_load)
    echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for e in d.get('edges',[]):
    print(f\"{e['from']} {e['to']} {e.get('type','?')} {e.get('tunnel_port',0)}\")
"
}

# Dijkstra 最短路径
# 用法: graph_path <from> <to>
graph_path() {
    local from=$1 to=$2
    CONFIG=$(config_load)
    python3 -c "
import json,sys,heapq
d=json.load(sys.stdin)
edges=d.get('edges',[])

# 构建图
adj={}
for e in edges:
    u,v=e['from'],e['to']
    adj.setdefault(u,[]).append((v,1.5 if e.get('type')=='reverse' else 1.0))

# Dijkstra
dist={'$from':0}
prev={'$from':None}
pq=[(0,'$from')]
while pq:
    du,u=heapq.heappop(pq)
    if u=='$to':break
    for v,w in adj.get(u,[]):
        if du+w<dist.get(v,float('inf')):
            dist[v]=du+w;prev[v]=u;heapq.heappush(pq,(du+w,v))

# 回溯路径
if '$to' not in prev:
    print(json.dumps({'ok':False}))
else:
    path=[];cur='$to'
    while cur:path.append(cur);cur=prev[cur]
    path.reverse()
    print(json.dumps({'ok':True,'path':path,'hops':len(path)-1}))
" 2>/dev/null
}

# 生成 ProxyJump 命令
proxyjump_cmd() {
    local result
    result=$(graph_path "$1" "$2")
    local ok hops path_str jumps
    ok=$(echo "$result" | python3 -c "import json,sys;print(json.load(sys.stdin).get('ok',False))" 2>/dev/null)

    if [ "$ok" != "True" ]; then
        echo "不可达"
        return 1
    fi

    path_str=$(echo "$result" | python3 -c "import json,sys;print(' → '.join(json.load(sys.stdin)['path']))" 2>/dev/null)
    hops=$(echo "$result" | python3 -c "import json,sys;print(json.load(sys.stdin)['hops'])" 2>/dev/null)

    if [ "$hops" -gt 1 ]; then
        jumps=$(echo "$result" | python3 -c "import json,sys;p=json.load(sys.stdin)['path'];print(','.join(p[1:-1]))" 2>/dev/null)
        echo "ssh -J $jumps $2"
    else
        echo "ssh $2"
    fi
    echo "  路径: $path_str ($hops 跳)"
}
