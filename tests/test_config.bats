#!/usr/bin/env bats
# 输入验证函数测试 — validate_node_name / validate_ip

setup() {
    load helpers
    source "$BATS_TEST_DIRNAME/../scripts/lib/config.sh"
}

# ── validate_node_name ──

@test "validate_node_name: 有效名称通过" {
    run validate_node_name "node3"
    [ "$status" -eq 0 ]
}

@test "validate_node_name: 含空格拒绝" {
    run validate_node_name "bad name"
    [ "$status" -eq 1 ]
}

@test "validate_node_name: 含 / 拒绝" {
    run validate_node_name "bad/name"
    [ "$status" -eq 1 ]
}

@test "validate_node_name: 含 → 拒绝" {
    run validate_node_name "a→b"
    [ "$status" -eq 1 ]
}

@test "validate_node_name: 空字符串拒绝" {
    run validate_node_name ""
    [ "$status" -eq 1 ]
}

# ── validate_ip ──

@test "validate_ip: 有效 IPv4 通过" {
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_ip: 有效公网 IPv4 通过" {
    run validate_ip "8.131.61.234"
    [ "$status" -eq 0 ]
}

@test "validate_ip: 域名拒绝（只接受纯 IP）" {
    run validate_ip "example.com"
    [ "$status" -eq 1 ]
}

@test "validate_ip: 空字符串通过（允许跳过）" {
    run validate_ip ""
    [ "$status" -eq 0 ]
}

@test "validate_ip: 带端口的 IP 拒绝" {
    run validate_ip "192.168.1.1:22"
    [ "$status" -eq 1 ]
}
