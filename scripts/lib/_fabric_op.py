#!/usr/bin/env python3
"""
Fabric 操作引擎 — fabric.json 的增删改查
物理连接层：hops、transit_nodes、maintainers、external_maintainers
所有用户数据通过 argv 传入，永不拼入代码字符串
"""
import fcntl
import json
import os
import sys
from pathlib import Path

FABRIC_DIR = Path.home() / ".tunnel-mesh"
FABRIC_FILE = FABRIC_DIR / "fabric.json"
LOCK_FILE = FABRIC_DIR / "fabric.json.lock"


def load():
    if FABRIC_FILE.exists():
        with open(FABRIC_FILE) as f:
            return json.load(f)
    return {"fabrics": {}}


def save(d):
    FABRIC_DIR.mkdir(parents=True, exist_ok=True)
    # 文件锁保护（超时 10 秒，防并发写入损坏数据）
    lock_fd = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        # 非阻塞失败，退化为阻塞等待（最多 10 秒）
        import time
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                time.sleep(0.1)
        else:
            print("❌ 无法获取 fabric.json 锁", file=sys.stderr)
            lock_fd.close()
            sys.exit(1)
    try:
        # 原子写入：先写 .tmp 再 os.replace（防中途崩溃损坏数据）
        import datetime
        tmp_file = FABRIC_DIR / "fabric.json.tmp"
        with open(tmp_file, "w") as f:
            json.dump(d, f, indent=2)
        # 备份当前文件（保留最近 5 个）
        if FABRIC_FILE.exists():
            ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            bak = FABRIC_DIR / f"fabric.json.bak.{ts}"
            FABRIC_FILE.rename(bak)
            # 清理超过 5 个的旧备份
            baks = sorted(FABRIC_DIR.glob("fabric.json.bak.*"))
            for old in baks[:-5]:
                old.unlink(missing_ok=True)
        tmp_file.rename(FABRIC_FILE)
        print(json.dumps(d, indent=2))
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()


def emit(d):
    print(json.dumps(d, indent=2))


# ---- fabric_create <id> <logical_edge> <port> ----
def cmd_fabric_create():
    d = load()
    fid = sys.argv[2]
    edge = sys.argv[3] if len(sys.argv) > 3 else ""
    port = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4].isdigit() else 0
    d["fabrics"][fid] = {
        "id": fid,
        "logical_edge": edge,
        "port": port,
        "hops": [],
        "transit_nodes": {},
        "maintainers": [],
        "external_maintainers": [],
        "status": "active",
        "created": os.environ.get("_NOW", ""),
    }
    save(d)


# ---- fabric_add_hop <fabric_id> <seq> <from> <to> <type> <port> <cmd> <runner> <target_ip> <target_port> ----
def cmd_fabric_add_hop():
    d = load()
    fid = sys.argv[2]
    if fid not in d["fabrics"]:
        emit({"error": f"fabric {fid} not found"})
        sys.exit(1)
    hop = {
        "seq": int(sys.argv[3]) if len(sys.argv) > 3 else 0,
        "from": sys.argv[4] if len(sys.argv) > 4 else "?",
        "to": sys.argv[5] if len(sys.argv) > 5 else "?",
        "type": sys.argv[6] if len(sys.argv) > 6 else "?",
        "port": int(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7].lstrip("-").isdigit() else 0,
        "cmd": sys.argv[8] if len(sys.argv) > 8 else "",
        "runner": sys.argv[9] if len(sys.argv) > 9 else "",
        "target_ip": sys.argv[10] if len(sys.argv) > 10 else "",
        "target_port": int(sys.argv[11]) if len(sys.argv) > 11 and sys.argv[11].isdigit() else 22,
    }
    d["fabrics"][fid]["hops"].append(hop)
    save(d)


# ---- fabric_add_transit <fabric_id> <name> <ip> <port> <user> <pubkey> ----
def cmd_fabric_add_transit():
    d = load()
    fid = sys.argv[2]
    if fid not in d["fabrics"]:
        emit({"error": f"fabric {fid} not found"})
        sys.exit(1)
    name = sys.argv[3]
    d["fabrics"][fid]["transit_nodes"][name] = {
        "ip": sys.argv[4] if len(sys.argv) > 4 else "?",
        "port": int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5].isdigit() else 22,
        "user": sys.argv[6] if len(sys.argv) > 6 else "root",
        "pubkey": sys.argv[7] if len(sys.argv) > 7 else "",
    }
    save(d)


# ---- fabric_add_maintainer <fabric_id> <node> <role> <cmd> <persist> ----
def cmd_fabric_add_maintainer():
    d = load()
    fid = sys.argv[2]
    if fid not in d["fabrics"]:
        emit({"error": f"fabric {fid} not found"})
        sys.exit(1)
    maint = {
        "node": sys.argv[3] if len(sys.argv) > 3 else "?",
        "role": sys.argv[4] if len(sys.argv) > 4 else "runner",
        "cmd": sys.argv[5] if len(sys.argv) > 5 else "",
        "persist": sys.argv[6] if len(sys.argv) > 6 else "manual",
    }
    # deduplicate by (node, role)
    existing = [m for m in d["fabrics"][fid]["maintainers"] if not (m["node"] == maint["node"] and m["role"] == maint["role"])]
    existing.append(maint)
    d["fabrics"][fid]["maintainers"] = existing
    save(d)


# ---- fabric_add_external <fabric_id> <name> <cmd> <platform> ----
def cmd_fabric_add_external():
    d = load()
    fid = sys.argv[2]
    if fid not in d["fabrics"]:
        emit({"error": f"fabric {fid} not found"})
        sys.exit(1)
    ext = {
        "name": sys.argv[3] if len(sys.argv) > 3 else "?",
        "cmd": sys.argv[4] if len(sys.argv) > 4 else "",
        "platform": sys.argv[5] if len(sys.argv) > 5 else "linux",
    }
    d["fabrics"][fid]["external_maintainers"].append(ext)
    save(d)


# ---- fabric_get <fabric_id> ----
def cmd_fabric_get():
    d = load()
    fid = sys.argv[2] if len(sys.argv) > 2 else ""
    if fid in d["fabrics"]:
        emit(d["fabrics"][fid])
    else:
        emit({"error": f"fabric {fid} not found"})
        sys.exit(1)


# ---- fabric_list ----
def cmd_fabric_list():
    d = load()
    for fid, f in d.get("fabrics", {}).items():
        hops = len(f.get("hops", []))
        transits = len(f.get("transit_nodes", {}))
        print(f"  {fid:<15} {f.get('logical_edge','?'):<25} 跳:{hops} 中转:{transits} [{f.get('status','?')}]")


# ---- fabric_remove <fabric_id> ----
def cmd_fabric_remove():
    d = load()
    fid = sys.argv[2] if len(sys.argv) > 2 else ""
    if fid in d["fabrics"]:
        del d["fabrics"][fid]
    save(d)


# ---- fabric_cmds ----
def cmd_fabric_cmds():
    d = load()
    for fid, f in d.get("fabrics", {}).items():
        print(f"## {fid}: {f.get('logical_edge','?')}")
        for m in f.get("maintainers", []):
            if m.get("cmd"):
                print(f"  [{m.get('node','?')}] {m['cmd']}  (persist: {m.get('persist','?')})")
        for e in f.get("external_maintainers", []):
            if e.get("cmd"):
                print(f"  [{e.get('name','?')} @ {e.get('platform','?')}] {e['cmd']}")
        print()


# ---- fabric_health <fabric_id> ----
def cmd_fabric_health():
    import subprocess, shlex
    d = load()
    fid = sys.argv[2] if len(sys.argv) > 2 else ""
    if fid not in d["fabrics"]:
        emit({"error": f"fabric {fid} not found"})
        sys.exit(1)
    f = d["fabrics"][fid]
    result = {"id": fid, "status": f.get("status", "?"), "hops": []}
    for h in f.get("hops", []):
        hop_status = {"from": h["from"], "to": h["to"], "type": h["type"], "status": "unknown"}
        if h["type"] == "forward_direct":
            tip = h.get("target_ip", "")
            tp = h.get("target_port", 22)
            hop_status["test"] = f"ssh -o ConnectTimeout=3 -o BatchMode=yes {tip} -p {tp}"
            if tip:
                try:
                    r = subprocess.run(
                        ["timeout", "3", "ssh", "-o", "ConnectTimeout=3", "-o", "BatchMode=yes",
                         "-o", "StrictHostKeyChecking=accept-new", "-p", str(tp), tip, "echo", "ok"],
                        capture_output=True, timeout=5
                    )
                    hop_status["status"] = "reachable" if r.returncode == 0 else "unreachable"
                except Exception:
                    hop_status["status"] = "unreachable"
        elif h.get("port", 0) > 0:
            port = h["port"]
            hop_status["test"] = f"nc -z localhost {port}"
            try:
                r = subprocess.run(["nc", "-z", "localhost", str(port)], capture_output=True, timeout=3)
                hop_status["status"] = "reachable" if r.returncode == 0 else "unreachable"
            except Exception:
                hop_status["status"] = "unreachable"
        else:
            hop_status["status"] = "unverifiable"
        result["hops"].append(hop_status)
    emit(result)


# ---- fabric_viz ----
def cmd_fabric_viz():
    d = load()
    if not d.get("fabrics"):
        print("  (无 fabric)")
        return
    for fid, f in d.get("fabrics", {}).items():
        print(f"══════ {fid}: {f.get('logical_edge','?')}  ({f.get('status','?')}) ══════")
        # Nodes
        nodes = set()
        for h in f.get("hops", []):
            nodes.add(h["from"])
            nodes.add(h["to"])
        print("节点:")
        for n in nodes:
            if n in f.get("transit_nodes", {}):
                tn = f["transit_nodes"][n]
                print(f"  [{n}] {tn['ip']}:{tn['port']} (中转)")
            else:
                print(f"  {n} (登录目标)")
        # Hops
        print("物理跳:")
        for h in f.get("hops", []):
            arrow_map = {
                "forward_direct": "─直连→",
                "forward_tunnel": "─ssh-L→",
                "reverse_tunnel": "─ssh-R→",
            }
            arrow = arrow_map.get(h["type"], f"─{h['type']}→")
            extra = f" :{h['port']}" if h.get("port") else ""
            print(f"  {h['from']} {arrow} {h['to']}{extra}  (runner: {h.get('runner','?')})")
        # Maintainers
        if f.get("maintainers") or f.get("external_maintainers"):
            print("维持者:")
            for m in f.get("maintainers", []):
                print(f"  {m['node']} [{m.get('persist','?')}]: {m.get('cmd','?')}")
            for e in f.get("external_maintainers", []):
                print(f"  {e['name']} @{e.get('platform','?')}: {e.get('cmd','?')}")
        print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: _fabric_op.py <cmd> [args...]", file=sys.stderr)
        sys.exit(1)
    cmd = sys.argv[1]
    fn = globals().get(f"cmd_{cmd}")
    if not fn:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
    fn()
