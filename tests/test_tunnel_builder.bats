#!/usr/bin/env bats
# 隧道命令生成测试 — gen_forward_tunnel_cmd / gen_reverse_tunnel_cmd

setup() {
    load helpers
    setup_config_env
    source "$BATS_TEST_DIRNAME/../scripts/lib/tunnel-builder.sh"
}

teardown() {
    teardown_config_env
}

# ── gen_forward_tunnel_cmd ──

@test "gen_forward_tunnel_cmd: 基本 ssh -L 格式" {
    run gen_forward_tunnel_cmd "node3" "aliyun" 2224 "8.131.61.234" 22 "root"
    [ "$status" -eq 0 ]
    [[ "$output" == "ssh -L 2224:8.131.61.234:22 root@8.131.61.234 -p 22" ]]
}

@test "gen_forward_tunnel_cmd: 自定义端口" {
    run gen_forward_tunnel_cmd "a" "b" 3333 "10.0.0.2" 5122 "user"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3333"* ]]
    [[ "$output" == *"5122"* ]]
}

@test "gen_forward_tunnel_cmd: 自定义用户" {
    run gen_forward_tunnel_cmd "a" "b" 2224 "10.0.0.2" 22 "admin"
    [ "$status" -eq 0 ]
    [[ "$output" == *"admin@"* ]]
}

# ── gen_reverse_tunnel_cmd ──

@test "gen_reverse_tunnel_cmd: 基本 ssh -R 格式" {
    run gen_reverse_tunnel_cmd "biolab" "aliyun" 2225 "10.16.82.202" 5122 "root"
    [ "$status" -eq 0 ]
    [[ "$output" == "ssh -R 2225:localhost:22 root@10.16.82.202 -p 5122" ]]
}

@test "gen_reverse_tunnel_cmd: 自定义端口" {
    run gen_reverse_tunnel_cmd "a" "b" 5555 "10.0.0.1" 2222 "user"
    [ "$status" -eq 0 ]
    [[ "$output" == *"5555"* ]]
    [[ "$output" == *"2222"* ]]
}

@test "gen_reverse_tunnel_cmd: 包含 gateway 端口（prev_port）" {
    run gen_reverse_tunnel_cmd "a" "b" 2225 "10.0.0.1" 5122 "root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-p 5122"* ]]
}
