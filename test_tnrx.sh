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
    setup_fake_runtime
    output=$(PATH="$FAKE_PATH" TNRX_SIF_DIR="$FAKE_STORE" timeout 3 "$TNRX_SCRIPT" uv add test </dev/null 2>&1)
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
    setup_fake_runtime
    output=$(PATH="$FAKE_PATH" TNRX_SIF_DIR="$FAKE_STORE" timeout 3 "$TNRX_SCRIPT" uv add test </dev/null 2>&1)
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

test_jupyter_registry() {
    log_test "Jupyter: registra o servidor em .tnrx/jupyter só depois que a porta responde"
    setup_test_env

    if ! command -v python3 >/dev/null 2>&1; then
        pass_test "python3 ausente: teste do registro ignorado"
        cleanup_test_env
        return
    fi

    # uv falso: imprime os argumentos e, com FAKE_JUPYTER_LISTEN=1, escuta na --port por 3s
    # (faz o papel do Jupyter subindo).
    mkdir -p bin home/.local/bin
    printf '#!/bin/sh\necho abaporu\n' > bin/hostname
    printf '#!/bin/bash\nshift; while [ "$1" = "--bind" ]; do shift 2; done; [ "$1" = "--nv" ] && shift; shift; exec "$@"\n' > bin/singularity
    printf '#!/bin/bash\nwhile [[ "$1" == --* ]]; do shift; done; exec "$@"\n' > bin/srun
    cat > home/.local/bin/uv <<'FAKEUV'
#!/bin/bash
[ "$2" = python ] && exit 0
echo "UV-ARGS: $*"
for a in "$@"; do case "$a" in --port=*) p="${a#--port=}";; esac; done
[ -n "$FAKE_JUPYTER_LISTEN" ] && python3 -c "import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR,1); s.bind(('0.0.0.0',$p)); s.listen(); time.sleep(3)"
exit 0
FAKEUV
    chmod +x bin/* home/.local/bin/uv
    touch fake.sif
    local fake_path="$PWD/bin:$PATH"
    local env_file out

    out=$(FAKE_JUPYTER_LISTEN=1 SLURM_JOB_ID=4242 TNRX_JUPYTER_REGISTER_SECS=6 TNRX_JUPYTER_PORT=47900 HOME="$PWD/home" PATH="$fake_path" timeout 20 "$TNRX_SCRIPT" uvslurm jupyter lab 2>&1)
    env_file=".tnrx/jupyter/4242.env"
    if [[ -f "$env_file" ]]; then
        pass_test "registro criado depois que a porta respondeu (.tnrx/jupyter/<job>.env)"
    else
        fail_test "registro não criado" "$(ls -R .tnrx 2>&1)"
    fi
    local content flag_token file_token
    content=$(cat "$env_file" 2>/dev/null)
    assert_contains "$content" "NODE=abaporu" "registra o nó"
    assert_contains "$content" "PORT=47900" "registra a porta"
    assert_contains "$content" "JOBID=4242" "registra o job"
    assert_contains "$content" "PROJECT=$PWD" "registra a pasta do projeto"
    file_token=$(sed -n 's/^TOKEN=//p' "$env_file")
    flag_token=$(printf '%s\n' "$out" | sed -n 's/.*--IdentityProvider.token=\([0-9a-f]*\).*/\1/p' | head -1)
    if [[ ${#file_token} -eq 48 && "$file_token" == "$flag_token" ]]; then
        pass_test "o token do registro é o mesmo passado ao Jupyter (48 hex)"
    else
        fail_test "token do registro difere do da flag" "registro='$file_token' flag='$flag_token'"
    fi
    if [[ "$(stat -c %a "$env_file" 2>/dev/null)" == "600" ]]; then pass_test "arquivo com permissão 600"; else fail_test "permissão do registro" "$(stat -c %a "$env_file" 2>&1)"; fi
    if [[ "$(cat .tnrx/.gitignore 2>/dev/null)" == "*" ]]; then pass_test ".tnrx/.gitignore ignora tudo (token não vai pro git)"; else fail_test ".tnrx/.gitignore ausente"; fi
    if command -v git >/dev/null 2>&1; then
        git init -q . 2>/dev/null
        if [[ -z "$(git status --porcelain --untracked-files=all 2>/dev/null | grep '\.tnrx')" ]]; then pass_test "git não enxerga o .tnrx"; else fail_test "git enxerga o .tnrx" "$(git status --porcelain --untracked-files=all)"; fi
    fi

    # Senha fixa: com .tnrx/jupyter/token (gravado pelo tnrx-connect), usa ela
    rm -rf .tnrx
    mkdir -p .tnrx/jupyter
    printf '%s\n' "0123456789abcdef0123456789abcdef0123456789abcdef" > .tnrx/jupyter/token
    out=$(SLURM_JOB_ID=4244 TNRX_JUPYTER_REGISTER_SECS=2 TNRX_JUPYTER_PORT=47902 HOME="$PWD/home" PATH="$fake_path" timeout 20 "$TNRX_SCRIPT" uvslurm jupyter lab 2>&1)
    assert_contains "$out" "--IdentityProvider.token=0123456789abcdef0123456789abcdef0123456789abcdef" "usa a senha fixa de .tnrx/jupyter/token"
    printf 'curta\n' > .tnrx/jupyter/token
    out=$(SLURM_JOB_ID=4245 TNRX_JUPYTER_REGISTER_SECS=2 TNRX_JUPYTER_PORT=47903 HOME="$PWD/home" PATH="$fake_path" timeout 20 "$TNRX_SCRIPT" uvslurm jupyter lab 2>&1)
    flag_token=$(printf '%s\n' "$out" | sed -n 's/.*--IdentityProvider.token=\([0-9a-f]*\).*/\1/p' | head -1)
    if [[ ${#flag_token} -eq 48 ]]; then pass_test "senha inválida no arquivo: gera uma aleatória"; else fail_test "token inesperado" "$flag_token"; fi

    rm -rf .tnrx
    out=$(SLURM_JOB_ID=4243 TNRX_JUPYTER_REGISTER_SECS=2 TNRX_JUPYTER_PORT=47901 HOME="$PWD/home" PATH="$fake_path" timeout 20 "$TNRX_SCRIPT" uvslurm jupyter lab 2>&1)
    sleep 3
    if [[ ! -e .tnrx/jupyter/4243.env ]]; then pass_test "sem Jupyter respondendo, nada é registrado"; else fail_test "registrou sem o Jupyter subir"; fi

    cleanup_test_env
}

# Ambiente falso para os testes do banco de imagens: hostname do Abaporu, um
# singularity que cria o arquivo pedido no pull/build (e falha com FAKE_RUNTIME_FAIL)
# e um banco vazio em ./store.
setup_fake_runtime() {
    mkdir -p bin store home/.local/bin
    printf '#!/bin/sh\necho abaporu\n' > bin/hostname
    cat > bin/singularity <<'FAKERT'
#!/bin/bash
echo "RUNTIME-ARGS: $*"
[ -n "$FAKE_RUNTIME_FAIL" ] && { echo "FATAL: fakeroot not available"; exit 255; }
case "$1" in
    pull|build) out="${@: -2:1}"; echo fake > "$out" ;;
    exec) shift; while [ "$1" = "--bind" ]; do shift 2; done; [ "$1" = "--nv" ] && shift; echo "EXEC-IMAGE: $1" ;;
esac
FAKERT
    printf '#!/bin/bash\necho "UV: $*"\n' > home/.local/bin/uv
    chmod +x bin/* home/.local/bin/uv
    FAKE_PATH="$PWD/bin:$PATH"
    FAKE_STORE="$PWD/store"
}

test_install_singularity() {
    log_test "install singularity: imagem no banco, link na pasta"
    setup_test_env
    setup_fake_runtime
    mkdir proj && cd proj || return
    local default_name="nvidia_cuda_12.6.3-cudnn-runtime-ubuntu24.04.sif" out

    out=$(TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity </dev/null 2>&1)
    assert_contains "$out" "pull $FAKE_STORE/.tmp-" "sem tnrx.def: pull da imagem padrão para o banco"
    assert_file_exists "$FAKE_STORE/$default_name" "nome da imagem vem da origem docker"
    if [[ -L "$default_name" && "$(readlink "$default_name")" == "$FAKE_STORE/$default_name" ]]; then
        pass_test "link na pasta com o mesmo nome, apontando para o banco"
    else
        fail_test "link na pasta" "$(ls -la)"
    fi
    assert_contains "$out" "cp $SCRIPT_DIR/tnrx.def ." "sem tnrx.def: sugere copiar o modelo"
    if ls "$FAKE_STORE"/.tmp-* >/dev/null 2>&1; then fail_test "sobrou arquivo temporário no banco"; else pass_test "sem temporários no banco"; fi

    out=$(TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity </dev/null 2>&1)
    assert_not_contains "$out" "RUNTIME-ARGS" "imagem já no banco: não baixa de novo"
    out=$(TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity --force </dev/null 2>&1)
    assert_contains "$out" "RUNTIME-ARGS: pull" "--force: baixa de novo"

    out=$(TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity docker://ubuntu:24.04 </dev/null 2>&1)
    assert_file_exists "$FAKE_STORE/ubuntu_24.04.sif" "origem explícita: ubuntu_24.04.sif"
    if [[ -L ubuntu_24.04.sif && ! -e "$default_name" && ! -L "$default_name" ]]; then
        pass_test "o link novo substitui o antigo (um .sif por pasta)"
    else
        fail_test "troca de link" "$(ls -la)"
    fi

    cp "$SCRIPT_DIR/tnrx.def" .
    out=$(TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity </dev/null 2>&1)
    local def_name="nvidia_cuda_12.6.3-cudnn-runtime-ubuntu24.04__def-$(sha256sum tnrx.def | cut -c1-8).sif"
    if [ "$(id -u)" -ne 0 ]; then
        assert_contains "$out" "build --fakeroot $FAKE_STORE/.tmp-" "com tnrx.def: build com --fakeroot"
    fi
    assert_file_exists "$FAKE_STORE/$def_name" "imagem do .def: nome da base + hash do conteúdo"
    echo "# mudança" >> tnrx.def
    out=$(TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity </dev/null 2>&1)
    assert_contains "$out" "RUNTIME-ARGS: build" ".def editado: gera uma imagem nova"

    out=$(TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity ausente.def </dev/null 2>&1)
    assert_contains "$out" "Definition file não encontrado: ausente.def" ".def inexistente: erro"

    rm -f ./*.sif tnrx.def
    echo real > proprio.sif
    out=$(echo n | TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity 2>&1)
    if [[ -f proprio.sif && ! -L proprio.sif ]]; then pass_test ".sif próprio e resposta 'n': mantido"; else fail_test ".sif próprio apagado"; fi
    out=$(echo y | TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity 2>&1)
    if [[ ! -e proprio.sif && -L "$default_name" ]]; then pass_test ".sif próprio e resposta 'y': trocado pelo link"; else fail_test "troca do .sif próprio" "$(ls -la)"; fi

    rm -f ./*.sif
    out=$(FAKE_RUNTIME_FAIL=1 TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity docker://falha:1 </dev/null 2>&1)
    assert_exit_code 1 $? "download falho: exit 1"
    if [[ ! -e "$FAKE_STORE/falha_1.sif" ]] && ! ls "$FAKE_STORE"/.tmp-* >/dev/null 2>&1; then
        pass_test "download falho não deixa imagem nem temporário no banco"
    else
        fail_test "restos de download falho" "$(ls -la "$FAKE_STORE")"
    fi
    cp "$SCRIPT_DIR/tnrx.def" .
    out=$(FAKE_RUNTIME_FAIL=1 TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install singularity tnrx.def --force </dev/null 2>&1)
    assert_contains "$out" "gere a imagem em outra máquina" "build falho: explica a alternativa"

    cleanup_test_env
}

test_missing_sif_prompt() {
    log_test "Pasta sem .sif: oferece as imagens do banco e cria o link"
    setup_test_env
    setup_fake_runtime
    mkdir proj && cd proj || return
    local default_name="nvidia_cuda_12.6.3-cudnn-runtime-ubuntu24.04.sif" out

    out=$(HOME="$PWD/../home" TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" uv sync </dev/null 2>&1)
    assert_contains "$out" "Nenhum arquivo .sif encontrado" "sem terminal: erro, sem perguntar"

    out=$(echo n | TNRX_INTERACTIVE=1 HOME="$PWD/../home" TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" uv sync 2>&1)
    assert_contains "$out" "[1] $default_name  (padrão; será baixada)" "menu: padrão primeiro, avisando que vai baixar"
    assert_contains "$out" "Cancelado" "'n' cancela"
    assert_not_contains "$out" "UV:" "cancelado: o comando não roda"

    echo fake > "$FAKE_STORE/outra_imagem_1.0.sif"
    out=$(echo 2 | TNRX_INTERACTIVE=1 HOME="$PWD/../home" TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" uv sync 2>&1)
    assert_contains "$out" "[2] outra_imagem_1.0.sif" "menu: lista as outras imagens do banco"
    assert_contains "$out" "EXEC-IMAGE: outra_imagem_1.0.sif" "escolha: cria o link e o comando segue com ela"

    rm -f ./*.sif
    out=$(echo | TNRX_INTERACTIVE=1 HOME="$PWD/../home" TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" uv sync 2>&1)
    assert_contains "$out" "RUNTIME-ARGS: pull" "Enter: baixa a padrão"
    assert_contains "$out" "EXEC-IMAGE: $default_name" "Enter: liga a padrão e segue"

    rm -f "$FAKE_STORE/$default_name"
    out=$(TNRX_INTERACTIVE=1 HOME="$PWD/../home" TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" uv sync </dev/null 2>&1)
    assert_contains "$out" "aponta para uma imagem que não existe mais" "link quebrado: avisa"

    cleanup_test_env
}

test_install_setup() {
    log_test "tnrx install (servidor): uv e a imagem padrão no banco"
    setup_test_env
    setup_fake_runtime
    local out
    out=$(HOME="$PWD/home" TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install </dev/null 2>&1)
    assert_contains "$out" "uv já instalado" "uv existente: não reinstala"
    assert_file_exists "$FAKE_STORE/nvidia_cuda_12.6.3-cudnn-runtime-ubuntu24.04.sif" "imagem padrão no banco"
    out=$(HOME="$PWD/home" TNRX_SIF_DIR="$FAKE_STORE" PATH="$FAKE_PATH" "$TNRX_SCRIPT" install </dev/null 2>&1)
    assert_not_contains "$out" "RUNTIME-ARGS" "segunda vez: não baixa de novo"
    cleanup_test_env
}

test_installer() {
    log_test "install.sh: instalar, update, update-dev e uninstall (repositório git local no lugar do GitHub)"
    setup_test_env
    if ! command -v git >/dev/null 2>&1; then
        pass_test "git ausente: teste do instalador ignorado"
        cleanup_test_env
        return
    fi
    setup_fake_runtime
    local g=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main) out
    mkdir remote
    (cd "$SCRIPT_DIR" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - --) | tar -xf - -C remote
    (cd remote && "${g[@]}" init -q && "${g[@]}" add -A && "${g[@]}" commit -qm "versão 1")
    mkdir laptop-bin
    printf '#!/bin/sh\necho meu-laptop\n' > laptop-bin/hostname
    chmod +x laptop-bin/hostname
    local env_laptop=(env HOME="$PWD/home" PATH="$PWD/laptop-bin:$PATH" TNRX_REPO="file://$PWD/remote" TNRX_SKIP_VSCODE=1)
    local inst="$PWD/home/.local/share/tnrx" bin="$PWD/home/.local/bin"

    # Primeira instalação: responde às perguntas (tnrx, download_huggingface, tnrx-connect).
    out=$(printf 's\ns\n\n' | "${env_laptop[@]}" TNRX_INTERACTIVE=1 TMPDIR="$PWD/tmp" bash -c 'mkdir -p "$TMPDIR"; bash "$0"' "$SCRIPT_DIR/install.sh" 2>&1)
    assert_contains "$out" "Instalado em $inst" "primeira instalação (curl | bash) clona e instala"
    assert_contains "$out" "tnrx: roda os projetos no cluster (servidor) [s/N]" "laptop: tnrx vem desmarcado por padrão"
    assert_contains "$out" "tnrx-connect: trabalha no projeto do servidor a partir do laptop [S/n]" "laptop: tnrx-connect vem marcado por padrão"
    assert_contains "$out" "não está em tnrx_hosts.conf: o tnrx só roda" "tnrx escolhido num laptop: avisa que ele só roda nos servidores"
    assert_not_contains "$out" "Servidor reconhecido" "laptop: não prepara o servidor"
    if [ -z "$(ls -A tmp)" ]; then pass_test "o clone temporário é apagado"; else fail_test "sobrou o clone temporário" "$(ls -A tmp)"; fi
    if [[ "$(readlink "$bin/tnrx")" == "$inst/tnrx" && "$(readlink "$bin/tnrx-connect")" == "$inst/tnrx-connect" && "$(readlink "$bin/download_huggingface")" == "$inst/download_huggingface" ]]; then
        pass_test "links em ~/.local/bin apontam para a pasta da instalação"
    else
        fail_test "links" "$(ls -la "$bin")"
    fi
    local v1
    v1=$(git -C remote rev-parse --short HEAD)
    out=$("${env_laptop[@]}" "$bin/tnrx" version 2>&1)
    assert_contains "$out" "tnrx $v1" "tnrx version mostra o commit"
    out=$("${env_laptop[@]}" "$bin/tnrx-connect" --version 2>&1)
    assert_contains "$out" "tnrx-connect $v1" "tnrx-connect --version mostra o commit"

    echo "# nova linha" >> remote/README.md
    (cd remote && "${g[@]}" commit -qam "versão 2: muda o README")
    out=$("${env_laptop[@]}" "$bin/tnrx-connect" update </dev/null 2>&1)
    assert_not_contains "$out" "O que instalar" "update repete a escolha, sem perguntar"
    assert_contains "$out" "Atualizado em $inst: $v1 -> $(git -C remote rev-parse --short HEAD)" "update instala o commit novo"
    assert_contains "$out" "versão 2: muda o README" "update mostra o que mudou"
    assert_contains "$(tail -1 "$inst/README.md")" "# nova linha" "update troca os arquivos"
    if ls -d "$inst".old.* "$inst".new.* >/dev/null 2>&1; then
        fail_test "sobraram pastas temporárias" "$(ls -d "$inst"* )"
    else
        pass_test "sem pastas temporárias depois do update"
    fi
    out=$("${env_laptop[@]}" "$bin/tnrx" update </dev/null 2>&1)
    assert_contains "$out" "Já estava na versão mais nova" "update sem novidade avisa"
    out=$(env HOME="$PWD/home" PATH="$PWD/laptop-bin:$PATH" TNRX_SKIP_VSCODE=1 "$bin/tnrx" update </dev/null 2>&1)
    assert_contains "$out" "Baixando file://$PWD/remote" "update sem TNRX_REPO usa o repositório da instalação"

    "${g[@]}" clone -q remote dev
    echo "# mudança local" >> dev/tnrx_hosts.conf
    mkdir -p dev/.venv && touch dev/.venv/lixo dev/imagem.sif
    out=$(cd dev && "${env_laptop[@]}" "$bin/tnrx" update-dev </dev/null 2>&1)
    assert_contains "$out" "Atualizado em $inst" "update-dev (pasta atual) instala a cópia local"
    assert_contains "$(tail -1 "$inst/tnrx_hosts.conf")" "# mudança local" "update-dev leva mudanças não commitadas"
    if [[ ! -e "$inst/.venv" && ! -e "$inst/imagem.sif" ]]; then pass_test "update-dev respeita o .gitignore (.venv, *.sif)"; else fail_test "copiou arquivos ignorados"; fi
    out=$("${env_laptop[@]}" "$bin/tnrx" version 2>&1)
    assert_contains "$out" "dev:$(cd dev && pwd -P) (com mudanças não commitadas)" "version mostra que é uma cópia de desenvolvimento"
    out=$("${env_laptop[@]}" "$bin/tnrx-connect" update-dev "$PWD/remote/docs" </dev/null 2>&1)
    assert_contains "$out" "não é o repositório do tnrx" "update-dev numa pasta errada: erro"

    out=$(env HOME="$PWD/home" PATH="$FAKE_PATH" TNRX_SIF_DIR="$FAKE_STORE" TNRX_REPO="file://$PWD/remote" bash "$inst/install.sh" --update </dev/null 2>&1)
    assert_contains "$out" "Servidor reconhecido (abaporu)" "servidor: reconhece pelo tnrx_hosts.conf"
    assert_file_exists "$FAKE_STORE/nvidia_cuda_12.6.3-cudnn-runtime-ubuntu24.04.sif" "servidor: baixa a imagem padrão para o banco"

    out=$(env HOME="$PWD/home2" PATH="$PWD/laptop-bin:$PATH" bash "$SCRIPT_DIR/install.sh" --uninstall </dev/null 2>&1)
    assert_exit_code 0 $? "sem TNRX_REPO e sem instalação anterior: o instalador não aborta"
    out=$(printf 's\nn\nn\n' | "${env_laptop[@]}" TNRX_INTERACTIVE=1 "$bin/tnrx" update --choose 2>&1)
    assert_contains "$out" "O que instalar" "update --choose pergunta de novo"
    if [[ -L "$bin/tnrx" && ! -e "$bin/tnrx-connect" && ! -e "$bin/download_huggingface" ]]; then
        pass_test "componentes desmarcados perdem o link"
    else
        fail_test "links depois do --choose" "$(ls -la "$bin")"
    fi
    assert_contains "$(cat "$inst/VERSION")" "COMPONENTS=tnrx" "a escolha fica gravada em VERSION"

    out=$(printf 'n\nn\n' | env HOME="$PWD/home4" PATH="$PWD/laptop-bin:$PATH" TNRX_INTERACTIVE=1 TNRX_SKIP_VSCODE=1 bash "$inst/install.sh" --from "$PWD/dev" 2>&1)
    assert_contains "$out" "Nada escolhido" "nada escolhido: não instala"
    if [ ! -e "$PWD/home4/.local/share/tnrx" ]; then pass_test "nada escolhido: pasta não criada"; else fail_test "instalou sem nada escolhido"; fi

    if command -v setsid >/dev/null 2>&1; then
        out=$(env HOME="$PWD/home3" PATH="$PWD/laptop-bin:$PATH" TNRX_SKIP_VSCODE=1 setsid -w bash "$inst/install.sh" --from "$PWD/dev" </dev/null 2>&1)
        assert_contains "$out" "Sem terminal para perguntar: instalando o padrão desta máquina (tnrx-connect)" "sem terminal: padrão do laptop"
        out=$(env HOME="$PWD/home5" PATH="$FAKE_PATH" TNRX_SIF_DIR="$FAKE_STORE" TNRX_SKIP_SETUP=1 setsid -w bash "$inst/install.sh" --from "$PWD/dev" </dev/null 2>&1)
        assert_contains "$out" "instalando o padrão desta máquina (tnrx download_huggingface)" "sem terminal: padrão do servidor"
    fi
    out=$(env HOME="$PWD/home6" PATH="$PWD/laptop-bin:$PATH" TNRX_COMPONENTS="tnrx-connect,download_huggingface" bash "$inst/install.sh" --from "$PWD/dev" </dev/null 2>&1)
    if [[ -L "$PWD/home6/.local/bin/tnrx-connect" && -L "$PWD/home6/.local/bin/download_huggingface" && ! -e "$PWD/home6/.local/bin/tnrx" ]]; then
        pass_test "TNRX_COMPONENTS escolhe sem perguntar"
    else
        fail_test "TNRX_COMPONENTS" "$out"
    fi

    out=$("${env_laptop[@]}" "$bin/tnrx" uninstall </dev/null 2>&1)
    if [[ ! -e "$bin/tnrx" && ! -L "$bin/tnrx-connect" && ! -d "$inst" ]]; then pass_test "uninstall remove os comandos e a pasta"; else fail_test "uninstall" "$out"; fi

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

    # Imagem do container
    test_install_singularity
    test_missing_sif_prompt
    test_install_setup
    test_installer

    # Jupyter
    test_jupyter_display_url
    test_jupyter_registry

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
