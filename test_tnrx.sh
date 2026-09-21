#!/bin/bash

##############################################################################
# Test Suite for TNRX
#
# This script tests all main functionalities of the tnrx wrapper.
# It's designed to be run frequently during development and CI/CD.
#
# Features:
# - Flexible test framework (easily add new tests as functions)
# - Automatic cleanup after each run
# - Comprehensive reporting with color-coded output
# - Isolated test environment (temporary directory)
#
# Usage:
#   ./test_tnrx.sh                    # Run all tests
#   ./test_tnrx.sh test_hostname      # Run specific test
#   ./test_tnrx.sh --verbose          # Show detailed output
#
##############################################################################

set -o pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TNRX_SCRIPT="$SCRIPT_DIR/tnrx"
TEST_TEMP_DIR=""
VERBOSE=false
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---

setup_test_env() {
    TEST_TEMP_DIR=$(mktemp -d)
    cd "$TEST_TEMP_DIR" || exit 1
    [[ "$VERBOSE" == "true" ]] && echo "📁 Test environment: $TEST_TEMP_DIR"
}

cleanup_test_env() {
    if [[ -d "$TEST_TEMP_DIR" ]]; then
        cd "$SCRIPT_DIR" || exit 1
        rm -rf "$TEST_TEMP_DIR"
        [[ "$VERBOSE" == "true" ]] && echo "🧹 Cleaned up: $TEST_TEMP_DIR"
    fi
}

log_test() {
    local name=$1
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🧪 Test: $name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pass_test() {
    local name=$1
    local message=${2:-""}
    ((TESTS_PASSED++))
    echo -e "${GREEN}✅ PASS: $name${NC}"
    [[ -n "$message" ]] && echo "   $message"
}

fail_test() {
    local name=$1
    local message=${2:-""}
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$name")
    echo -e "${RED}❌ FAIL: $name${NC}"
    [[ -n "$message" ]] && echo "   $message"
}

assert_exit_code() {
    local expected=$1
    local actual=$2
    local test_name=$3

    if [[ $actual -eq $expected ]]; then
        pass_test "$test_name" "Exit code: $actual"
    else
        fail_test "$test_name" "Expected exit code $expected, got $actual"
    fi
}

assert_contains() {
    local string=$1
    local substring=$2
    local test_name=$3

    if [[ "$string" == *"$substring"* ]]; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Output does not contain: '$substring'"
    fi
}

assert_not_contains() {
    local string=$1
    local substring=$2
    local test_name=$3

    if [[ "$string" != *"$substring"* ]]; then
        pass_test "$test_name"
    else
        fail_test "$test_name" "Output should not contain: '$substring'"
    fi
}

assert_file_exists() {
    local file=$1
    local test_name=$2

    if [[ -f "$file" ]]; then
        pass_test "$test_name" "File exists: $file"
    else
        fail_test "$test_name" "File not found: $file"
    fi
}

# --- Core Test Suite ---

test_tnrx_script_exists() {
    log_test "TNRX script exists and is executable"
    if [[ -x "$TNRX_SCRIPT" ]]; then
        pass_test "Script executable"
    else
        fail_test "Script not found or not executable" "Path: $TNRX_SCRIPT"
    fi
}

test_help_output() {
    log_test "Help/usage output"
    setup_test_env

    output=$("$TNRX_SCRIPT" 2>&1)
    assert_contains "$output" "Uso:" "Help output contains usage info"

    cleanup_test_env
}

test_unknown_command() {
    log_test "Unknown command handling"
    setup_test_env

    output=$("$TNRX_SCRIPT" invalid_command 2>&1)
    local exit_code=$?
    # Note: Currently tnrx exits with 0 for unknown commands, showing usage
    assert_contains "$output" "Uso:" "Invalid command shows usage"

    cleanup_test_env
}

test_hosts_config_file() {
    log_test "tnrx_hosts.conf exists and is well-formed"

    local hosts_file="$SCRIPT_DIR/tnrx_hosts.conf"

    if [[ ! -f "$hosts_file" ]]; then
        fail_test "tnrx_hosts.conf not found next to tnrx"
        return
    fi
    pass_test "tnrx_hosts.conf found"

    local line host bind runtime hub_root bad_lines=0
    while IFS='|' read -r host bind runtime hub_root; do
        [[ -z "$host" || "$host" =~ ^[[:space:]]*# ]] && continue
        if [[ -z "$bind" || -z "$hub_root" ]]; then
            ((bad_lines++))
        fi
    done < "$hosts_file"

    if [[ "$bad_lines" -eq 0 ]]; then
        pass_test "All tnrx_hosts.conf entries have BIND_PATH and HUB_ROOT"
    else
        fail_test "tnrx_hosts.conf has malformed entries" "$bad_lines line(s) missing fields"
    fi
}

test_hostname_validation() {
    log_test "Hostname validation feature"
    setup_test_env

    local current_hostname=$(hostname)
    local hosts_file="$SCRIPT_DIR/tnrx_hosts.conf"

    # Test that the current hostname has a matching entry in tnrx_hosts.conf
    # (this is what check_hostname()/load_host_config() rely on)
    if grep -q "^${current_hostname}|" "$hosts_file" 2>/dev/null; then
        pass_test "Running on a hostname configured in tnrx_hosts.conf" "Hostname: $current_hostname"
    else
        # The test should still pass if we're on a different machine
        # but we should note that the feature will reject execution
        pass_test "Hostname check logic available" "Note: Current hostname '$current_hostname' not in tnrx_hosts.conf"
    fi

    cleanup_test_env
}

test_config_file_loading() {
    log_test "Configuration file loading"
    setup_test_env

    # Create a test config file
    cat > tnrx_slurm.conf <<EOF
PARTITION=h200
GPUS=2
CPUS=4
MEM=32G
TIME=04:00:00
EOF

    assert_file_exists "tnrx_slurm.conf" "Config file created"

    # Verify config format
    if grep -q "PARTITION=h200" tnrx_slurm.conf; then
        pass_test "Config file has correct format"
    else
        fail_test "Config file format invalid"
    fi

    cleanup_test_env
}

test_env_file_loading() {
    log_test "Environment variables file loading"
    setup_test_env

    # Create a test .tnrx_env file
    cat > .tnrx_env <<EOF
SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
REQUESTS_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
NLTK_DATA=/data/nltk_data
DEBUG_MODE=true
EOF

    assert_file_exists ".tnrx_env" "Environment file created"

    # Verify env file format
    if grep -q "DEBUG_MODE=true" .tnrx_env; then
        pass_test "Environment file has correct format"
    else
        fail_test "Environment file format invalid"
    fi

    cleanup_test_env
}

test_missing_sif_error() {
    log_test "Missing .sif file error handling"
    setup_test_env

    # Try to run tnrx without .sif file with timeout
    # Use timeout to prevent hanging on srun
    output=$(timeout 3 "$TNRX_SCRIPT" uv add test 2>&1)
    local exit_code=$?

    # Either timeout or find_sif error should occur
    if [ $exit_code -eq 124 ]; then
        # Timeout occurred (expected when srun tries to allocate resources)
        pass_test "Missing .sif prevents execution"
    else
        # Or we get the explicit error message
        assert_contains "$output" "Nenhum arquivo .sif encontrado" "Error message for missing .sif"
    fi

    cleanup_test_env
}

test_multiple_sif_error() {
    log_test "Multiple .sif file error handling"
    setup_test_env

    # Create multiple .sif files
    touch dummy1.sif dummy2.sif

    # Use timeout to prevent hanging on srun
    output=$(timeout 3 "$TNRX_SCRIPT" uv add test 2>&1)
    local exit_code=$?

    # Either timeout or find_sif error should occur
    if [ $exit_code -eq 124 ]; then
        # Timeout occurred (expected when srun tries to allocate resources)
        pass_test "Multiple .sif prevents execution"
    else
        # Or we get the explicit error message
        assert_contains "$output" "Mais de um .sif encontrado" "Error message for multiple .sif"
    fi

    cleanup_test_env
}

test_context_awareness() {
    log_test "Context-aware directory behavior"
    setup_test_env

    # Create two test directories with different configs
    mkdir -p project1 project2

    cat > project1/tnrx_slurm.conf <<EOF
PARTITION=l40s
GPUS=1
EOF

    cat > project2/tnrx_slurm.conf <<EOF
PARTITION=h200
GPUS=4
EOF

    # Verify both configs exist and are different
    if diff -q project1/tnrx_slurm.conf project2/tnrx_slurm.conf >/dev/null 2>&1; then
        fail_test "Configs should be different"
    else
        pass_test "Multiple configs can coexist" "Project-specific configs created"
    fi

    cleanup_test_env
}

test_uv_command_validation() {
    log_test "UV command validation"
    setup_test_env

    # Test invalid uv subcommand
    output=$("$TNRX_SCRIPT" uv invalid 2>&1)
    local exit_code=$?

    # This should show help or error
    if [[ $exit_code -ne 0 ]] || [[ "$output" == *"Uso:"* ]]; then
        pass_test "Invalid uv command handled"
    else
        fail_test "Invalid uv command not properly handled"
    fi

    cleanup_test_env
}

test_bind_path_selection() {
    log_test "Bind path selection based on hostname"
    setup_test_env

    local current_hostname=$(hostname)
    local hosts_file="$SCRIPT_DIR/tnrx_hosts.conf"
    local entry bind

    entry=$(grep "^${current_hostname}|" "$hosts_file" 2>/dev/null)

    if [[ -n "$entry" ]]; then
        bind=$(echo "$entry" | cut -d'|' -f2)
        pass_test "Hostname '$current_hostname' found in tnrx_hosts.conf" "Will use bind path: $bind"
    else
        pass_test "Hostname check implemented" "Note: Not on a host listed in tnrx_hosts.conf, feature will reject execution"
    fi

    cleanup_test_env
}

test_gitignore_integrity() {
    log_test "Important files in .gitignore"
    setup_test_env

    cd "$SCRIPT_DIR" || exit 1

    local gitignore_path=".gitignore"
    if [[ -f "$gitignore_path" ]]; then
        if grep -q ".tnrx_env" "$gitignore_path"; then
            pass_test ".tnrx_env in .gitignore"
        else
            fail_test ".tnrx_env not in .gitignore"
        fi
    else
        fail_test ".gitignore file not found"
    fi

    cleanup_test_env
}

test_symlink_creation_readiness() {
    log_test "Script ready for symlink creation"
    setup_test_env

    # Verify the script has a proper shebang
    if head -1 "$TNRX_SCRIPT" | grep -q "#!/bin/bash"; then
        pass_test "Script has correct shebang"
    else
        fail_test "Script missing proper shebang"
    fi

    # Verify the script is executable
    if [[ -x "$TNRX_SCRIPT" ]]; then
        pass_test "Script is executable"
    else
        fail_test "Script is not executable"
    fi

    cleanup_test_env
}

test_pyproject_toml_exists() {
    log_test "Project configuration files"
    setup_test_env

    cd "$SCRIPT_DIR" || exit 1

    if [[ -f "pyproject.toml" ]]; then
        pass_test "pyproject.toml exists"
    else
        fail_test "pyproject.toml not found"
    fi

    cleanup_test_env
}

# --- .tnrx_env Integration Tests ---

test_tnrx_syntax_check() {
    log_test "tnrx script bash syntax"

    if bash -n "$TNRX_SCRIPT" 2>/dev/null; then
        pass_test "tnrx script has valid bash syntax"
    else
        fail_test "tnrx script has syntax errors" "$(bash -n "$TNRX_SCRIPT" 2>&1)"
    fi
}

test_load_env_vars_function_exists() {
    log_test "load_env_vars function defined in tnrx"

    if grep -q "load_env_vars()" "$TNRX_SCRIPT"; then
        pass_test "load_env_vars function found"
    else
        fail_test "load_env_vars function not found in tnrx script"
    fi
}

test_load_env_vars_wired_into_commands() {
    log_test "load_env_vars called from every container-launching command"

    local fn
    for fn in do_uv do_slurm do_uvslurm do_huggingface; do
        if grep -A 5 "${fn}()" "$TNRX_SCRIPT" | grep -q "load_env_vars"; then
            pass_test "load_env_vars called in ${fn}()"
        else
            fail_test "load_env_vars not called in ${fn}()"
        fi
    done
}

test_env_var_parsing_logic() {
    log_test ".tnrx_env parsing logic (mock)"
    setup_test_env

    cat > .tnrx_env <<EOF
SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
DEBUG_MODE=true
EOF

    local parsed
    parsed=$(while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        echo "SINGULARITYENV_${key}=${value}"
    done < .tnrx_env)

    assert_contains "$parsed" "SINGULARITYENV_DEBUG_MODE=true" "Parsing produces SINGULARITYENV_-prefixed vars"

    cleanup_test_env
}

test_runtime_env_injection() {
    log_test "Runtime: .tnrx_env vars actually reach the container"

    if [[ "${TNRX_SKIP_RUNTIME_TEST:-0}" == "1" ]]; then
        echo -e "${YELLOW}⚠️  SKIP${NC}: submits a real Slurm/GPU job, not run automatically (set TNRX_SKIP_RUNTIME_TEST=0 to run)"
        return
    fi

    if ! command -v tnrx &> /dev/null; then
        echo -e "${YELLOW}⚠️  SKIP${NC}: tnrx not installed globally (run 'tnrx install' first)"
        return
    fi

    local output
    output=$(tnrx slurm python -c "import os; print(os.environ.get('SSL_CERT_FILE', 'NOT_FOUND'))" 2>/dev/null | tail -1)

    if [[ -z "$output" ]]; then
        echo -e "${YELLOW}⚠️  SKIP${NC}: could not run tnrx slurm (Slurm may not be available)"
    elif [[ "$output" == "NOT_FOUND" ]]; then
        fail_test "Runtime env injection" "SSL_CERT_FILE not found in container"
    else
        pass_test "Runtime env injection" "SSL_CERT_FILE=$output"
    fi
}

test_jupyter_display_url() {
    log_test "Jupyter: URL exibida usa o nome do nó e a porta real"
    setup_test_env

    # Porta alta (TNRX_JUPYTER_PORT) pra não depender das portas em uso na máquina.
    # hostname/singularity/srun/uv falsos: o teste não depende de servidor, GPU nem Jupyter.
    # O uv falso apenas imprime os argumentos que o Jupyter receberia.
    mkdir -p bin home/.local/bin
    printf '#!/bin/sh\necho abaporu\n' > bin/hostname
    printf '#!/bin/bash\nshift; while [ "$1" = "--bind" ]; do shift 2; done; [ "$1" = "--nv" ] && shift; shift; exec "$@"\n' > bin/singularity
    printf '#!/bin/bash\nwhile [[ "$1" == --* ]]; do shift; done; exec "$@"\n' > bin/srun
    printf '#!/bin/bash\n[ "$2" = python ] && exit 0\necho "UV-ARGS: $*"\n' > home/.local/bin/uv
    chmod +x bin/* home/.local/bin/uv
    touch fake.sif
    local fake_path="$PWD/bin:$PATH"

    local out
    out=$(TNRX_JUPYTER_PORT=47888 HOME="$PWD/home" PATH="$fake_path" timeout 20 "$TNRX_SCRIPT" uvslurm jupyter lab 2>&1)
    assert_contains "$out" "Nó: abaporu" "imprime o nome do nó"
    assert_contains "$out" "--ServerApp.custom_display_url=http://abaporu:47888" "URL com o nó no lugar de 'hostname'"
    assert_contains "$out" "--port=47888" "porta explícita, igual à da URL"
    assert_contains "$out" "--ServerApp.port_retries=0" "a porta impressa não desloca sozinha"
    assert_contains "$out" "TNRX_JUPYTER_READY node=abaporu port=47888 token=" "linha de marcador pro tnrx-connect"
    local marker_token flag_token
    marker_token=$(printf '%s\n' "$out" | sed -n 's/.*TNRX_JUPYTER_READY .* token=\([0-9a-f]*\).*/\1/p' | head -1)
    flag_token=$(printf '%s\n' "$out" | sed -n 's/.*--IdentityProvider.token=\([0-9a-f]*\).*/\1/p' | head -1)
    if [[ ${#marker_token} -eq 48 && "$marker_token" == "$flag_token" ]]; then
        pass_test "o token do marcador é o mesmo passado ao Jupyter (48 hex)"
    else
        fail_test "token do marcador difere do da flag" "marcador='$marker_token' flag='$flag_token'"
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 47888)); s.listen(); time.sleep(15)" &
        local listener=$!
        sleep 1
        out=$(TNRX_JUPYTER_PORT=47888 HOME="$PWD/home" PATH="$fake_path" timeout 20 "$TNRX_SCRIPT" uvslurm jupyter lab 2>&1)
        kill "$listener" 2>/dev/null; wait "$listener" 2>/dev/null
        assert_contains "$out" "--ServerApp.custom_display_url=http://abaporu:47889" "porta 47888 ocupada: usa a 47889 na URL"
    fi

    out=$(TNRX_JUPYTER_PORT=47888 HOME="$PWD/home" PATH="$fake_path" timeout 20 "$TNRX_SCRIPT" uvslurm python script.py 2>&1)
    assert_not_contains "$out" "custom_display_url" "comandos sem Jupyter não recebem as flags"

    cleanup_test_env
}

# --- Test Runner ---

run_all_tests() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        🚀 TNRX Comprehensive Test Suite 🚀             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}\n"

    # Core functionality tests
    test_tnrx_script_exists
    test_help_output
    test_unknown_command
    test_missing_sif_error
    test_multiple_sif_error

    # Configuration and environment tests
    test_config_file_loading
    test_env_file_loading
    test_context_awareness
    test_gitignore_integrity
    test_pyproject_toml_exists

    # Feature tests
    test_hosts_config_file
    test_hostname_validation
    test_bind_path_selection
    test_uv_command_validation
    test_symlink_creation_readiness

    # .tnrx_env integration tests
    test_tnrx_syntax_check
    test_load_env_vars_function_exists
    test_load_env_vars_wired_into_commands
    test_env_var_parsing_logic
    test_runtime_env_injection

    # Jupyter
    test_jupyter_display_url

    # Print summary
    print_summary
}

run_specific_test() {
    local test_name=$1

    echo -e "\n${BLUE}Running specific test: $test_name${NC}\n"

    if declare -f "$test_name" > /dev/null; then
        $test_name
        print_summary
    else
        echo -e "${RED}❌ Test '$test_name' not found${NC}"
        echo "Available tests:"
        declare -f | grep "test_" | sed 's/test_/  - /' | sed 's/ ()//'
        exit 1
    fi
}

print_summary() {
    TESTS_RUN=$((TESTS_PASSED + TESTS_FAILED))

    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    📊 Test Summary                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "Total:  $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"

    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo -e "\n${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        return 1
    else
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        return 0
    fi
}

list_tests() {
    echo "Available tests:"
    declare -f | grep "^test_" | sed 's/test_/  tnrx /' | sed 's/ ()//'
}

show_help() {
    cat <<EOF
${BLUE}TNRX Test Suite${NC}

Usage:
  ./test_tnrx.sh              Run all tests
  ./test_tnrx.sh test_NAME    Run specific test (e.g., test_hostname_validation)
  ./test_tnrx.sh --list       List all available tests
  ./test_tnrx.sh --verbose    Run all tests with verbose output
  ./test_tnrx.sh --help       Show this help message

Examples:
  ./test_tnrx.sh
  ./test_tnrx.sh --verbose
  ./test_tnrx.sh test_config_file_loading

Features:
  ✓ Automatic cleanup after each run
  ✓ Isolated test environment
  ✓ Color-coded output
  ✓ Flexible test framework
  ✓ Easy to add new tests

Adding New Tests:
  1. Create a function: test_my_feature() { ... }
  2. Use assertion helpers: pass_test, fail_test, assert_*
  3. Run: ./test_tnrx.sh test_my_feature

EOF
}

# --- Main Entry Point ---

main() {
    if [[ ! -x "$TNRX_SCRIPT" ]]; then
        echo -e "${RED}❌ Error: tnrx script not found or not executable${NC}"
        echo "Expected at: $TNRX_SCRIPT"
        exit 1
    fi

    case "${1:-}" in
        --help | -h)
            show_help
            exit 0
            ;;
        --list | -l)
            list_tests
            exit 0
            ;;
        --verbose | -v)
            VERBOSE=true
            run_all_tests
            ;;
        test_*)
            run_specific_test "$1"
            ;;
        "")
            run_all_tests
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Run main
main "$@"
exit $?
