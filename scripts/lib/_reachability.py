#!/usr/bin/env python3
"""
可达报告合并引擎 v2 — 多端口并行探测 + 端口切换推荐 + ProxyJump 识别
用法: python3 _reachability.py merge <report1.json> [report2.json ...]
      python3 _reachability.py deploy-guide <report1.json> [report2.json ...]
"""
import json
import sys
from collections import defaultdict


def load_report(path):
    try:
        with open(path) as f:
            try:
                return json.load(f)
            except json.JSONDecodeError as e:
                print(f"❌ 无效的报告文件: {path} — {e}", file=sys.stderr)
                sys.exit(1)
    except FileNotFoundError:
        print(f"❌ 文件不存在: {path}", file=sys.stderr)
        sys.exit(1)


def merge_reports(reports):
    """合并多份可达报告（兼容 v1 单端口、v2 多端口、v3 SSH 探测格式），返回:
    - matrix:        {(from, to): {port_str: reachable_bool}}
    - node_ips:      {name: ip}
    - node_ports:    {name: default_port}
    - nodes:         sorted list of all node names
    - probed_ports:  sorted list of all probed port numbers
    - ssh_reachable: {(from, to): bool}  # v3: SSH 可达性
    """
    matrix = {}
    node_ips = {}
    node_ports = {}
    all_probed_ports = set()
    ssh_reachable = {}

    for i, r in enumerate(reports):
        if "from" not in r:
            print(f"❌ 报告 #{i+1} 缺少 'from' 字段，请确认传入的是单机可达报告（非合并后的矩阵）", file=sys.stderr)
            sys.exit(1)
        frm = r["from"]
        if frm not in node_ips:
            node_ips[frm] = r.get("from_ip", "?")
        all_probed_ports.update(r.get("probed_ports", [22]))

        for res in r.get("results", []):
            to = res["target"]
            if to not in node_ips:
                node_ips[to] = res.get("ip", "?")
            if to not in node_ports:
                node_ports[to] = res.get("default_port", res.get("port", 22))

            key = (frm, to)
            if key not in matrix:
                matrix[key] = {}

            # v3: SSH 可达性
            if "ssh_reachable" in res:
                ssh_reachable[key] = res["ssh_reachable"]

            # v2 格式: "ports" dict
            if "ports" in res:
                for port_str, info in res["ports"].items():
                    matrix[key][port_str] = info.get("reachable", False)
            # v1 格式: 单端口
            else:
                port = str(res.get("port", 22))
                matrix[key][port] = res.get("reachable", False)

    nodes = sorted(set(node_ips.keys()))
    probed_ports = sorted(all_probed_ports)
    return matrix, nodes, node_ips, node_ports, probed_ports, ssh_reachable


def is_pair_reachable(matrix, a, b, ports, ssh_reachable=None):
    """判断 a→b 在任何 probed port 上是否可达。返回 (reachable, open_ports, blocked_ports)
    ssh_reachable: {(from, to): bool} — v3 SSH 可达性数据，优先于 TCP 探测"""
    pair_ports = matrix.get((a, b), {})
    open_ports = [p for p in ports if str(p) in pair_ports and pair_ports[str(p)]]
    blocked_ports = [p for p in ports if str(p) in pair_ports and not pair_ports[str(p)]]

    # SSH 可达优先：即使 TCP 端口全不通，SSH 通也算可达
    ssh_ok = False
    if ssh_reachable:
        ssh_ok = ssh_reachable.get((a, b), False)
    if ssh_ok:
        return (True, open_ports, blocked_ports)

    unreachable = all(not pair_ports.get(str(p), False) for p in ports)
    return (not unreachable, open_ports, blocked_ports)


def find_port_switch_recommendation(matrix, a, b, ports, default_port=22):
    """如果 A→B 在默认端口不通但在其他端口通，建议端口切换。
    返回 (recommended_ports, suggestion_text)"""
    pair_ports = matrix.get((a, b), {})
    default_reachable = pair_ports.get(str(default_port), False)
    alt_ports = [p for p in ports if p != default_port and pair_ports.get(str(p), False)]

    if not default_reachable and alt_ports:
        return alt_ports, f"{a} → {b} 端口 {default_port} 不通，但端口 {alt_ports} 可达，建议 ssh -p {alt_ports[0]} {b}"
    return [], ""


def _build_reachability_graph(matrix, ports, nodes, ssh_reachable=None):
    """构建可达有向图。边 (a→b) 存在当且仅当 TCP 或 SSH 可达。返回 adjacency dict: {node: set(neighbors)}"""
    from collections import defaultdict
    graph = defaultdict(set)
    for a in nodes:
        for b in nodes:
            if a == b:
                continue
            pair_ports = matrix.get((a, b), {})
            tcp_ok = any(pair_ports.get(str(p), False) for p in ports)
            ssh_ok = ssh_reachable.get((a, b), False) if ssh_reachable else False
            if tcp_ok or ssh_ok:
                graph[a].add(b)
    return graph


def find_proxyjump_candidates(matrix, a, b, ports, nodes=None, ssh_reachable=None):
    """BFS 搜索 A→B 的最短传递路径（最大深度 2 跳中转）。
    返回 [(via_nodes_list, description)]
    如: (["node3"], "biolab → node3 → aliyun")"""
    # 收集所有节点
    all_nodes = set()
    for (frm, to) in matrix:
        all_nodes.update([frm, to])
    if nodes:
        all_nodes.update(nodes)

    graph = _build_reachability_graph(matrix, ports, list(all_nodes), ssh_reachable)

    from collections import deque
    max_depth = 3  # total path length (source + 2 intermediates + target)
    queue = deque([[a]])
    visited = {a}
    candidates = []

    while queue:
        path = queue.popleft()
        if len(path) > max_depth:
            continue
        current = path[-1]
        for neighbor in sorted(graph.get(current, set())):
            if neighbor == b:
                via = path[1:]  # exclude source
                desc = " → ".join(path + [b])
                label = f"{desc}（ProxyJump {'→'.join(via)}）"
                candidates.append((via, label))
                if len(candidates) >= 3:
                    return candidates
            elif neighbor not in visited and len(path) < max_depth:
                visited.add(neighbor)
                queue.append(path + [neighbor])

    return candidates


def find_bridge_v2(matrix, a, b, ports, all_nodes, ssh_reachable=None):
    """找一个公共可达节点作为桥（兼容单端口场景的降级）"""
    for c in sorted(all_nodes):
        if c == a or c == b:
            continue
        # A→C 或 C→A 任方向可达
        a_c = is_pair_reachable(matrix, a, c, ports, ssh_reachable)[0] or is_pair_reachable(matrix, c, a, ports, ssh_reachable)[0]
        b_c = is_pair_reachable(matrix, b, c, ports, ssh_reachable)[0] or is_pair_reachable(matrix, c, b, ports, ssh_reachable)[0]
        if a_c and b_c:
            return c
    return None


def recommend_edges_v2(matrix, nodes, ports, node_ips, ssh_reachable=None):
    """根据多端口可达矩阵推荐边类型，含端口切换和 ProxyJump 建议"""
    edges = []
    all_nodes_set = set()
    for (frm, to) in matrix:
        all_nodes_set.update([frm, to])

    for a in nodes:
        for b in nodes:
            if a >= b:
                continue
            a_to_b, a_open, a_blocked = is_pair_reachable(matrix, a, b, ports, ssh_reachable)
            b_to_a, b_open, b_blocked = is_pair_reachable(matrix, b, a, ports, ssh_reachable)

            if a_to_b and b_to_a:
                edges.append({"from": a, "to": b, "type": "forward",
                              "reason": f"{a} ⇄ {b} 双向直连",
                              "open_ports": {"a→b": a_open, "b→a": b_open}})
                edges.append({"from": b, "to": a, "type": "forward",
                              "reason": f"{b} ⇄ {a} 双向直连",
                              "open_ports": {"b→a": b_open, "a→b": a_open}})
            elif a_to_b:
                edges.append({"from": a, "to": b, "type": "forward",
                              "reason": f"{a} → {b} 可达",
                              "open_ports": {"a→b": a_open}})
                # B→A 方向：先检查端口切换，再检查 ProxyJump，最后才是反向隧道
                b_to_a_switched_ports, switch_msg = find_port_switch_recommendation(matrix, b, a, ports)
                if b_to_a_switched_ports:
                    edges.append({"from": b, "to": a, "type": "port-switch",
                                  "reason": switch_msg,
                                  "recommended_ports": b_to_a_switched_ports})
                else:
                    proxyjump = find_proxyjump_candidates(matrix, b, a, ports, nodes=nodes, ssh_reachable=ssh_reachable)
                    if proxyjump:
                        edges.append({"from": b, "to": a, "type": "proxyjump",
                                      "reason": f"{b} → {a} 不通但可通过中转",
                                      "proxyjump_candidates": [{"via": c, "desc": d} for c, d in proxyjump]})
                    else:
                        edges.append({"from": b, "to": a, "type": "reverse",
                                      "reason": f"{b} 不可达 {a}。{a} 可主动在 {b} 上开 ssh -R",
                                      "tunnel_runner": a, "tunnel_on": b})
            elif b_to_a:
                edges.append({"from": b, "to": a, "type": "forward",
                              "reason": f"{b} → {a} 可达",
                              "open_ports": {"b→a": b_open}})
                a_to_b_switched_ports, switch_msg = find_port_switch_recommendation(matrix, a, b, ports)
                if a_to_b_switched_ports:
                    edges.append({"from": a, "to": b, "type": "port-switch",
                                  "reason": switch_msg,
                                  "recommended_ports": a_to_b_switched_ports})
                else:
                    proxyjump = find_proxyjump_candidates(matrix, a, b, ports, nodes=nodes, ssh_reachable=ssh_reachable)
                    if proxyjump:
                        edges.append({"from": a, "to": b, "type": "proxyjump",
                                      "reason": f"{a} → {b} 不通但可通过中转",
                                      "proxyjump_candidates": [{"via": c, "desc": d} for c, d in proxyjump]})
                    else:
                        edges.append({"from": a, "to": b, "type": "reverse",
                                      "reason": f"{a} 不可达 {b}。{b} 可主动在 {a} 上开 ssh -R",
                                      "tunnel_runner": b, "tunnel_on": a})
            else:
                # 双方都不通：先找 ProxyJump，再找桥
                proxyjump_a = find_proxyjump_candidates(matrix, a, b, ports, nodes=nodes, ssh_reachable=ssh_reachable)
                proxyjump_b = find_proxyjump_candidates(matrix, b, a, ports, nodes=nodes, ssh_reachable=ssh_reachable)
                if proxyjump_a:
                    edges.append({"from": a, "to": b, "type": "proxyjump",
                                  "reason": f"双方不通，通过 ProxyJump",
                                  "proxyjump_candidates": [{"via": c, "desc": d} for c, d in proxyjump_a]})
                    edges.append({"from": b, "to": a, "type": "proxyjump",
                                  "reason": f"双方不通，通过 ProxyJump",
                                  "proxyjump_candidates": [{"via": c, "desc": d} for c, d in proxyjump_b] if proxyjump_b else []})
                else:
                    bridge = find_bridge_v2(matrix, a, b, ports, all_nodes_set, ssh_reachable)
                    if bridge:
                        edges.append({"from": a, "to": b, "type": "chained",
                                      "reason": f"双方不通，借 {bridge} 链式跳转", "bridge": bridge})
                        edges.append({"from": b, "to": a, "type": "chained",
                                      "reason": f"双方不通，借 {bridge} 链式跳转", "bridge": bridge})
                    else:
                        edges.append({"from": a, "to": b, "type": "unreachable",
                                      "reason": "无可用路径，需引入新中转节点"})
                        edges.append({"from": b, "to": a, "type": "unreachable",
                                      "reason": "无可用路径，需引入新中转节点"})
    return edges


def format_matrix_v2(matrix, nodes, ports, node_ips):
    """格式化 N×N 可达矩阵（含多端口信息）"""
    col_w = max(max(len(n) for n in nodes), 8) + 3
    header = "".ljust(col_w) + "".join(n.ljust(col_w) for n in nodes)
    lines = [header, "-" * len(header)]

    for a in nodes:
        row = a.ljust(col_w)
        for b in nodes:
            if a == b:
                row += "-".ljust(col_w)
            else:
                pair_ports = matrix.get((a, b), {})
                open_count = sum(1 for p in ports if pair_ports.get(str(p), False))
                total = len(ports)
                if open_count == total:
                    row += "✓".ljust(col_w)
                elif open_count > 0:
                    row += f"~{open_count}/{total}".ljust(col_w)
                elif all(str(p) in pair_ports for p in ports):
                    row += "✗".ljust(col_w)
                else:
                    row += "?".ljust(col_w)
        lines.append(row)
    return "\n".join(lines)


# ═══════════════════════════════════════════════════════════
# CLI 命令
# ═══════════════════════════════════════════════════════════

def cmd_merge():
    if len(sys.argv) < 3:
        print("用法: python3 _reachability.py merge <report1.json> [report2.json ...]", file=sys.stderr)
        sys.exit(1)

    reports = [load_report(p) for p in sys.argv[2:]]
    matrix, nodes, node_ips, node_ports, ports, ssh_reachable = merge_reports(reports)
    edges = recommend_edges_v2(matrix, nodes, ports, node_ips, ssh_reachable)

    # 输出
    print("# 网络可达矩阵 (v3)\n")
    print(f"探测端口: {ports}\n")
    print("```")
    print(format_matrix_v2(matrix, nodes, ports, node_ips))
    print("```\n")

    print("## 节点信息\n")
    for n in nodes:
        print(f"- **{n}**: {node_ips.get(n, '?')}:{node_ports.get(n, 22)}")

    print("\n## 推荐边\n")

    # 端口切换推荐（最高优先级）
    port_switch = [e for e in edges if e["type"] == "port-switch"]
    if port_switch:
        print("### 端口切换推荐")
        for e in port_switch:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")
            if "recommended_ports" in e:
                print(f"  建议: `ssh -p {e['recommended_ports'][0]} {e['to']}`")

    forward_edges = [e for e in edges if e["type"] == "forward"]
    reverse_edges = [e for e in edges if e["type"] == "reverse"]
    proxyjump_edges = [e for e in edges if e["type"] == "proxyjump"]
    chained_edges = [e for e in edges if e["type"] == "chained"]
    unreachable = [e for e in edges if e["type"] == "unreachable"]

    if forward_edges:
        print("\n### 正向直连")
        for e in forward_edges:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")

    if reverse_edges:
        print("\n### 反向隧道")
        for e in reverse_edges:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")
            runner = e.get("tunnel_runner", "")
            tun_on = e.get("tunnel_on", "")
            if runner and tun_on:
                print(f"  维持者: **{runner}** 运行 `ssh -R <port>:localhost:22 {tun_on}`")

    if proxyjump_edges:
        print("\n### ProxyJump（中转推荐）")
        for e in proxyjump_edges:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")
            for c in e.get("proxyjump_candidates", []):
                via = c["via"]
                if isinstance(via, list):
                    j_arg = ",".join(via)
                    print(f"  跳板: `ssh -J {j_arg} {e['to']}`（{len(via)} 跳）")
                else:
                    print(f"  跳板: `ssh -J {via} {e['to']}`")

    if chained_edges:
        print("\n### 链式跳转（借桥）")
        for e in chained_edges:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")

    if unreachable:
        print("\n### 不可达")
        for e in unreachable:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")

    # JSON 输出供程序消费
    print("\n---\n")
    result = {
        "nodes": {n: {"ip": node_ips.get(n, "?"), "port": node_ports.get(n, 22)} for n in nodes},
        "probed_ports": ports,
        "ssh_reachable": {f"{a}->{b}": ok for (a, b), ok in ssh_reachable.items() if ok},
        "matrix": {f"{a}->{b}": {p: matrix.get((a, b), {}).get(str(p), None) for p in ports if str(p) in matrix.get((a, b), {})}
                   for a in nodes for b in nodes if a != b},
        "edges": edges,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))


def cmd_deploy_guide():
    """读取多份报告，生成每台机器的部署指令"""
    if len(sys.argv) < 3:
        print("用法: python3 _reachability.py deploy-guide <report1.json> [report2.json ...]", file=sys.stderr)
        sys.exit(1)

    reports = [load_report(p) for p in sys.argv[2:]]
    matrix, node_list, node_ips, node_ports, ports, ssh_reachable = merge_reports(reports)
    edges = recommend_edges_v2(matrix, node_list, ports, node_ips, ssh_reachable)

    # 去重边
    seen = set()
    unique_edges = []
    for e in edges:
        key = (e["type"], e["from"], e["to"])
        if key not in seen:
            seen.add(key)
            unique_edges.append(e)

    # 每节点汇总任务
    node_tasks = {n: {"add_servers": set(), "run_tunnels": [], "ssh_config": [], "import_cards": set()} for n in node_list}

    for e in unique_edges:
        a, b = e["from"], e["to"]
        etype = e["type"]

        if etype == "forward":
            node_tasks[a]["add_servers"].add(b)
            node_tasks[b]["add_servers"].add(a)
            node_tasks[a]["ssh_config"].append({
                "host": b, "hostname": node_ips.get(b, "?"), "port": node_ports.get(b, 22), "direct": True
            })
            node_tasks[b]["ssh_config"].append({
                "host": a, "hostname": node_ips.get(a, "?"), "port": node_ports.get(a, 22), "direct": True
            })

        elif etype == "port-switch":
            # 端口切换：使用第一个推荐端口
            alt_ports = e.get("recommended_ports", [])
            alt_port = alt_ports[0] if alt_ports else 22
            for src, dst in [(a, b), (b, a)]:
                node_tasks[src]["ssh_config"].append({
                    "host": dst, "hostname": node_ips.get(dst, "?"),
                    "port": alt_port, "direct": True,
                    "note": f"端口 {alt_port} 替代默认 22"
                })

        elif etype == "reverse":
            runner = e.get("tunnel_runner", "")
            tun_on = e.get("tunnel_on", "")
            if runner and tun_on:
                cmd = f"ssh -R <port>:localhost:22 {tun_on}"
                node_tasks[runner]["run_tunnels"].append({
                    "target": b if runner == a else a,
                    "tunnel_on": tun_on, "cmd": cmd,
                    "note": f"在 {tun_on} 上打开反向端口"
                })
            for src, dst in [(a, b), (b, a)]:
                node_tasks[src]["ssh_config"].append({
                    "host": dst, "hostname": "localhost",
                    "port": "<分配端口>", "direct": False
                })

        elif etype == "proxyjump":
            candidates = e.get("proxyjump_candidates", [])
            if candidates:
                via = candidates[0]["via"]
                for src, dst in [(a, b), (b, a)]:
                    node_tasks[src]["ssh_config"].append({
                        "host": dst, "hostname": node_ips.get(dst, "?"),
                        "port": node_ports.get(dst, 22),
                        "proxyjump": via, "direct": False,
                        "note": f"通过 ProxyJump {via} 跳转"
                    })

        elif etype == "chained":
            bridge = e.get("bridge", "")
            for n in [a, b]:
                target = b if n == a else a
                node_tasks[n]["ssh_config"].append({
                    "host": target, "hostname": node_ips.get(bridge, bridge),
                    "port": node_ports.get(bridge, 22),
                    "proxyjump": bridge, "direct": False,
                    "note": f"通过 ProxyJump {bridge} 跳转"
                })

    # 输出
    for node_name in sorted(node_tasks.keys()):
        tasks = node_tasks[node_name]
        print(f"\n{'='*60}")
        print(f"## {node_name} ({node_ips.get(node_name, '?')}:{node_ports.get(node_name, 22)})")
        print(f"{'='*60}")

        if tasks["add_servers"]:
            print("\n### 1. 导入身份卡")
            for s in sorted(tasks["add_servers"]):
                print(f"   将 {s} 的身份卡导入 {node_name}:")
                print(f"     tunnel-mesh --cmd import << 'EOF'")
                print(f"     <粘贴 {s} 的身份卡>")
                print(f"     EOF")

        if tasks["run_tunnels"]:
            print("\n### 2. 维持隧道命令")
            for t in tasks["run_tunnels"]:
                print(f"   目标: {t['target']}")
                print(f"   命令: {t['cmd']}")
                print(f"   说明: {t['note']}")
                print(f"   持久化: autossh -M 0 -o ServerAliveInterval=30 {t['cmd']}")
                print()

        if tasks["ssh_config"]:
            print("\n### 3. SSH Config 条目")
            for c in tasks["ssh_config"]:
                note = c.get("note", "")
                if note:
                    print(f"   # {note}")
                print(f"   Host {c['host']}")
                print(f"       HostName {c['hostname']}")
                print(f"       Port {c['port']}")
                if "proxyjump" in c:
                    print(f"       ProxyJump {c['proxyjump']}")
                print()

    # 汇总
    print(f"\n{'='*60}")
    print("## 汇总：全局部署步骤")
    print(f"{'='*60}")
    print(f"""
1. 每台机器运行 tunnel-mesh --cmd reachability > <name>.json
2. 收集所有 JSON 到一台机器
3. 运行 tunnel-mesh --cmd reachability-merge *.json
4. 按各机器指南逐台执行
""")

    result = {
        "node_tasks": {
            n: {
                "add_servers": sorted(list(t["add_servers"])),
                "run_tunnels": t["run_tunnels"],
                "ssh_config": t["ssh_config"],
            }
            for n, t in node_tasks.items()
        }
    }
    print("\n---\n")
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        if len(sys.argv) < 2:
            print("usage: _reachability.py merge|deploy-guide <report...>", file=sys.stderr)
            sys.exit(1)
        cmd = sys.argv[1].replace("-", "_")
        fn = globals().get(f"cmd_{cmd}")
        if not fn:
            print(f"unknown command: {cmd}", file=sys.stderr)
            sys.exit(1)
        fn()
    except json.JSONDecodeError as e:
        print(f"❌ JSON 解析失败: {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError as e:
        print(f"❌ 文件不存在: {e}", file=sys.stderr)
        sys.exit(1)
    except (OSError, IOError) as e:
        print(f"❌ 文件/网络错误: {e}", file=sys.stderr)
        sys.exit(1)
