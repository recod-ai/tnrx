#!/bin/bash

##############################################################################
# Test Suite for TNRX-CONNECT
#
# Testa parsing/validação/erros do tnrx-connect sem depender de rede real
# (sem SSH, sem rsync de verdade) — mesmo espírito do test_tnrx.sh: usa
# `--debug` para inspecionar o comando montado em vez de executá-lo.
#
# Usage:
#   ./test_tnrx_connect.sh
#
##############################################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TNRX_CONNECT="$SCRIPT_DIR/tnrx-connect"
TEST_TEMP_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

setup_test_env() {
    TEST_TEMP_DIR=$(mktemp -d)
    cd "$TEST_TEMP_DIR" || exit 1
}

cleanup_test_env() {
    if [[ -d "$TEST_TEMP_DIR" ]]; then
        cd "$SCRIPT_DIR" || exit 1
        rm -rf "$TEST_TEMP_DIR"
    fi
}

log_test() {
    echo -e "${BLUE}🧪 Test: $1${NC}"
}

pass_test() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✅ PASS: $1${NC}"
}

fail_test() {
    local name=$1
    local message=${2:-""}
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$name")
    echo -e "${RED}❌ FAIL: $name${NC}"
    [[ -n "$message" ]] && echo "   $message"
}

assert_contains() {
    local string=$1 substring=$2 test_name=$3
    if [[ "$string" == *"$substring"* ]]; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Output does not contain: '$substring'"
    fi
}

assert_not_contains() {
    local string=$1 substring=$2 test_name=$3
    if [[ "$string" != *"$substring"* ]]; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Output should not contain: '$substring'"
    fi
}

# --- Tests ---

test_script_exists_and_executable() {
    log_test "tnrx-connect exists and is executable"
    if [[ -f "$TNRX_CONNECT" && -x "$TNRX_CONNECT" ]]; then
        pass_test "tnrx-connect found and executable"
    else
        fail_test "tnrx-connect missing or not executable"
    fi
}

test_syntax_check() {
    log_test "tnrx-connect bash syntax"
    if bash -n "$TNRX_CONNECT" 2>/dev/null; then
        pass_test "tnrx-connect has valid bash syntax"
    else
        fail_test "tnrx-connect has syntax errors" "$(bash -n "$TNRX_CONNECT" 2>&1)"
    fi
}

test_missing_config_error() {
    log_test "Missing .tnrx_connect error handling"
    setup_test_env

    local output
    output=$("$TNRX_CONNECT" sync 2>&1)
    local exit_code=$?

    assert_contains "$output" ".tnrx_connect não encontrado" "Error message for missing config"
    [[ $exit_code -ne 0 ]] && pass_test "Exits non-zero when config is missing" || fail_test "Should exit non-zero when config is missing"

    cleanup_test_env
}

test_invalid_remote_path() {
    log_test "REMOTE_PATH relativo é rejeitado"
    setup_test_env

    cat > .tnrx_connect <<'EOF'
HOST=abaporu
REMOTE_PATH=projetos/foo
EOF

    local output
    output=$("$TNRX_CONNECT" sync 2>&1)
    assert_contains "$output" "caminho absoluto" "Error message for relative REMOTE_PATH"

    cleanup_test_env
}

test_missing_host() {
    log_test "HOST ausente é rejeitado"
    setup_test_env

    cat > .tnrx_connect <<'EOF'
REMOTE_PATH=/home/user/projeto
EOF

    local output
    output=$("$TNRX_CONNECT" sync 2>&1)
    assert_contains "$output" "HOST não definido" "Error message for missing HOST"

    cleanup_test_env
}

test_sync_command_uses_gitignore_and_delete_by_default() {
    log_test "sync monta rsync com --filter gitignore e --delete por padrão"
    setup_test_env

    cat > .tnrx_connect <<'EOF'
HOST=abaporu
REMOTE_PATH=/home/user/projeto
EOF

    local output
    output=$("$TNRX_CONNECT" --debug sync 2>&1)

    assert_contains "$output" "rsync" "Debug output mentions rsync"
    assert_contains "$output" "--delete" "SYNC_DELETE default is true"
    assert_contains "$output" ".gitignore" "Uses .gitignore as exclude filter"
    assert_contains "$output" "abaporu:/home/user/projeto" "Uses HOST:REMOTE_PATH as rsync destination"

    cleanup_test_env
}

test_sync_delete_can_be_disabled() {
    log_test "SYNC_DELETE=false remove --delete do comando"
    setup_test_env

    cat > .tnrx_connect <<'EOF'
HOST=abaporu
REMOTE_PATH=/home/user/projeto
SYNC_DELETE=false
EOF

    local output
    output=$("$TNRX_CONNECT" --debug sync 2>&1)
    assert_not_contains "$output" "--delete" "SYNC_DELETE=false disables --delete"

    cleanup_test_env
}

test_pull_never_uses_delete() {
    log_test "pull nunca usa --delete (só puxa, não apaga local)"
    setup_test_env

    cat > .tnrx_connect <<'EOF'
HOST=abaporu
REMOTE_PATH=/home/user/projeto
EOF

    local output
    output=$("$TNRX_CONNECT" --debug pull 2>&1)
    assert_not_contains "$output" "--delete" "pull command has no --delete"
    assert_contains "$output" "abaporu:/home/user/projeto" "pull reads from HOST:REMOTE_PATH"

    cleanup_test_env
}

test_sync_falls_back_to_interactive_ssh_without_master() {
    log_test "sync sem conexão mestra ativa usa ssh interativo (permite senha/2FA)"
    setup_test_env

    cat > .tnrx_connect <<'EOF'
HOST=abaporu
REMOTE_PATH=/home/user/projeto
EOF

    local output
    output=$("$TNRX_CONNECT" --debug sync 2>&1)
    assert_contains "$output" "-e ssh " "sync falls back to plain ssh (no BatchMode) when no master is alive"
    assert_not_contains "$output" "BatchMode" "no BatchMode forced on a standalone foreground sync"

    cleanup_test_env
}

test_init_creates_config() {
    log_test "init cria .tnrx_connect a partir das respostas"
    setup_test_env

    printf "meuhost\n/home/user/meuprojeto\n" | "$TNRX_CONNECT" init > /dev/null 2>&1

    if [[ -f .tnrx_connect ]]; then
        pass_test ".tnrx_connect created by init"
        local content
        content=$(cat .tnrx_connect)
        assert_contains "$content" "HOST=meuhost" "init writes HOST correctly"
        assert_contains "$content" "REMOTE_PATH=/home/user/meuprojeto" "init writes REMOTE_PATH correctly"
    else
        fail_test ".tnrx_connect not created by init"
    fi

    cleanup_test_env
}

test_init_does_not_overwrite_without_confirmation() {
    log_test "init não sobrescreve config existente sem confirmação"
    setup_test_env

    cat > .tnrx_connect <<'EOF'
HOST=original
REMOTE_PATH=/home/user/original
EOF

    printf "n\n" | "$TNRX_CONNECT" init > /dev/null 2>&1

    local content
    content=$(cat .tnrx_connect)
    assert_contains "$content" "HOST=original" "Existing config preserved when user declines overwrite"

    cleanup_test_env
}

test_usage_output() {
    log_test "Comando desconhecido mostra uso"
    setup_test_env

    local output
    output=$("$TNRX_CONNECT" invalido 2>&1)
    assert_contains "$output" "Uso:" "Unknown command shows usage"

    cleanup_test_env
}

test_uninstall_no_symlink() {
    log_test "uninstall sem symlink não falha"
    setup_test_env

    local output
    output=$("$TNRX_CONNECT" uninstall 2>&1)
    local exit_code=$?

    [[ $exit_code -eq 0 ]] && pass_test "uninstall exits 0 with no symlink present" || fail_test "uninstall should exit 0 even with nothing to remove"

    cleanup_test_env
}

# --- Test Runner ---

run_all_tests() {
    echo -e "\n${BLUE}🚀 TNRX-CONNECT Test Suite${NC}\n"

    test_script_exists_and_executable
    test_syntax_check
    test_missing_config_error
    test_invalid_remote_path
    test_missing_host
    test_sync_command_uses_gitignore_and_delete_by_default
    test_sync_delete_can_be_disabled
    test_pull_never_uses_delete
    test_sync_falls_back_to_interactive_ssh_without_master
    test_init_creates_config
    test_init_does_not_overwrite_without_confirmation
    test_usage_output
    test_uninstall_no_symlink

    echo -e "\n${BLUE}📊 Total: $((TESTS_PASSED + TESTS_FAILED))  Passed: ${GREEN}$TESTS_PASSED${NC}  Failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed tests:${NC}"
        for t in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $t"
        done
        exit 1
    fi
    exit 0
}

run_all_tests
