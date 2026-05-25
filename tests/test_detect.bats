#!/usr/bin/env bats
# 身份卡解析测试 — parse_identity_card

setup() {
    source "$BATS_TEST_DIRNAME/../scripts/lib/detect.sh"
}

# 辅助函数：用临时文件喂入身份卡，避免 subshell 丢失 _ID_* 变量
run_card() {
    local tmp
    tmp=$(mktemp)
    cat > "$tmp"
    parse_identity_card < "$tmp" 2>/dev/null
    local ret=$?
    rm -f "$tmp"
    return $ret
}

@test "parse_identity_card: 有效身份卡（旧格式无 CHECKSUM）" {
    run_card <<'CARD'
NAME=test-node
IP=192.168.1.100
PORT=22
USER=root
PUBKEY=ssh-ed25519 AAAA
CARD
    [ "$?" -eq 0 ]
    [ "$_ID_NAME" = "test-node" ]
    [ "$_ID_IP" = "192.168.1.100" ]
    [ "$_ID_PORT" = "22" ]
    [ "$_ID_USER" = "root" ]
}

@test "parse_identity_card: 校验和不匹配" {
    run parse_identity_card <<'CARD'
NAME=test
IP=1.1.1.1
PORT=22
USER=root
PUBKEY=ssh-ed25519 AAAA
CHECKSUM=sha256:0000000000000000000000000000000000000000000000000000000000000000
CARD
    [ "$status" -ne 0 ]
}

@test "parse_identity_card: 缺少 NAME 行" {
    run parse_identity_card <<'CARD'
IP=1.1.1.1
PUBKEY=ssh-ed25519 AAAA
CARD
    [ "$status" -ne 0 ]
}

@test "parse_identity_card: 旧格式正常解析" {
    run_card <<'CARD'
NAME=old-node
IP=10.0.0.5
PORT=5122
USER=admin
PUBKEY=ssh-rsa AAAAB3
CARD
    [ "$?" -eq 0 ]
    [ "$_ID_NAME" = "old-node" ]
    [ "$_ID_PORT" = "5122" ]
}

@test "parse_identity_card: 空输入" {
    run parse_identity_card <<< ""
    [ "$status" -ne 0 ]
}

@test "parse_identity_card: 默认端口/用户" {
    run_card <<'CARD'
NAME=minimal
IP=10.0.0.99
PUBKEY=ssh-ed25519 BBBB
CARD
    [ "$?" -eq 0 ]
    [ "$_ID_PORT" = "22" ]
    [ "$_ID_USER" = "root" ]
}
