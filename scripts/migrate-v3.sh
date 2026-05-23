#!/usr/bin/env python3
"""
数据迁移 v2 → v3（双层架构）
v2: config.json edges 无 fabric_id，中间节点混在 servers 里
v3: 每条逻辑边有 fabric_id 引用 → 物理跳在 fabric.json
安全：先备份再迁移，幂等可重复运行
"""
import json
import os
import sys
from datetime import datetime
from pathlib import Path

CONFIG_DIR = Path.home() / ".tunnel-mesh"
CONFIG_FILE = CONFIG_DIR / "config.json"
FABRIC_FILE = CONFIG_DIR / "fabric.json"


def backup(path: Path):
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    bak = path.with_suffix(f"{path.suffix}.bak.before-migrate-{ts}")
    with open(path) as f:
        data = f.read()
    with open(bak, "w") as f:
        f.write(data)
    print(f"  ✓ 备份: {bak}")
    return bak


def load_json(path: Path):
    if path.exists():
        with open(path) as f:
            return json.load(f)
    return {}


def save_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def needs_migration(config):
    """检查是否需要迁移：任一条边缺少 fabric_id"""
    for edge in config.get("edges", []):
        if "fabric_id" not in edge:
            return True
    return False


def migrate():
    print("=" * 50)
    print("  Tunnel Mesh 数据迁移 v2 → v3")
    print("=" * 50)
    print()

    if not CONFIG_FILE.exists():
        print("  config.json 不存在，无需迁移")
        return

    config = load_json(CONFIG_FILE)
    fabric = load_json(FABRIC_FILE)

    if not needs_migration(config):
        print("  ✓ config.json 已是 v3 格式，无需迁移")
        return

    # 备份
    print("备份旧文件...")
    backup(CONFIG_FILE)
    if FABRIC_FILE.exists():
        backup(FABRIC_FILE)
    print()

    # 初始化 fabric 结构
    if "fabrics" not in fabric:
        fabric["fabrics"] = {}
    if not FABRIC_FILE.exists():
        save_json(FABRIC_FILE, fabric)

    edges = config.get("edges", [])
    migrated_count = 0

    for edge in edges:
        if "fabric_id" in edge:
            continue

        eid = edge.get("id", f"{edge.get('from','?')}→{edge.get('to','?')}")
        typ = edge.get("type", "forward")
        port = edge.get("tunnel_port", 0)
        cmd = edge.get("tunnel_cmd", "")
        maintainer = edge.get("maintainer", "")

        # 生成 fabric_id
        ts = datetime.now().strftime("%Y%m%d%H%M%S")
        fid = f"fab-{ts}-{migrated_count}"

        # 映射 edge type → hop type
        if typ == "forward" and port == 0:
            hop_type = "forward_direct"
            weight = 1.0
        elif typ == "forward":
            hop_type = "forward_tunnel"
            weight = 1.0
        elif typ == "reverse":
            hop_type = "reverse_tunnel"
            weight = 1.5
        else:
            hop_type = "forward_direct"
            weight = 1.0

        # 创建 fabric
        fabric_data = {
            "id": fid,
            "logical_edge": eid,
            "port": port,
            "hops": [
                {
                    "seq": 0,
                    "from": edge.get("from", "?"),
                    "to": edge.get("to", "?"),
                    "type": hop_type,
                    "port": port,
                    "cmd": cmd,
                    "runner": edge.get("to", "?") if hop_type == "reverse_tunnel" else edge.get("from", "?"),
                    "target_ip": "",
                    "target_port": 22,
                }
            ],
            "transit_nodes": {},
            "maintainers": [],
            "external_maintainers": [],
            "status": "active",
            "created": edge.get("created", datetime.now().isoformat()),
        }

        # 如果有维持者标记，添加 maintainer
        if cmd:
            runner = edge.get("to", "?") if hop_type == "reverse_tunnel" else edge.get("from", "?")
            fabric_data["maintainers"].append({
                "node": runner,
                "role": "runner",
                "cmd": cmd,
                "persist": "manual",
            })

        fabric["fabrics"][fid] = fabric_data

        # 更新 edge
        edge["fabric_id"] = fid
        edge["weight"] = weight

        migrated_count += 1
        print(f"  ✓ {eid} → {fid} ({hop_type}, weight={weight})")

    # 写入
    save_json(FABRIC_FILE, fabric)
    save_json(CONFIG_FILE, config)

    print()
    print(f"✓ 迁移完成: {migrated_count} 条边 → {migrated_count} 个 Fabric")
    print(f"  config.json: {CONFIG_FILE}")
    print(f"  fabric.json: {FABRIC_FILE}")
    print()
    print("备份文件在:", CONFIG_DIR)
    for bak in sorted(CONFIG_DIR.glob("*.bak.before-migrate-*")):
        print(f"  {bak.name}")


if __name__ == "__main__":
    try:
        migrate()
    except Exception as e:
        print(f"❌ 迁移失败: {e}", file=sys.stderr)
        sys.exit(1)
