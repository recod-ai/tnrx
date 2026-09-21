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

    printf "meuhost\nn\n/home/user/meuprojeto\n" | "$TNRX_CONNECT" init > /dev/null 2>&1

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

# --- Modo mount: fakes de ssh/rclone/fusermount3 (sem rede, sem FUSE de verdade) ---

FAKES_DIR=""
ORIG_PATH="$PATH"
ORIG_HOME="$HOME"

make_fakes() {
    FAKES_DIR=$(mktemp -d)

    cat > "$FAKES_DIR/ssh" <<'EOF'
#!/bin/bash
# ssh falso: simula o ControlMaster com um arquivo marcador; -t "abre a sessão"
# (dorme FAKE_SSH_SESSION_SECS e sai); qualquer outro comando roda localmente.
ctrl=""; mode=""; args=("$@")
for ((i=0;i<${#args[@]};i++)); do
  case "${args[$i]}" in
    -O) mode="${args[$((i+1))]}";;
    -o) o="${args[$((i+1))]}"; [[ "$o" == ControlPath=* ]] && ctrl="${o#ControlPath=}";;
  esac
done
[ "$mode" == check ] && { [ -f "$ctrl" ] && exit 0 || exit 1; }
[ "$mode" == exit ] && { rm -f "$ctrl"; exit 0; }
for a in "${args[@]}"; do [ "$a" == "-fN" ] && { touch "$ctrl"; exit 0; }; done
for a in "${args[@]}"; do [ "$a" == "-t" ] && { sleep "${FAKE_SSH_SESSION_SECS:-0}"; exit 0; }; done
export HOME="${FAKE_REMOTE_HOME:-$HOME}"; bash -c "${args[-1]}"
EOF

    cat > "$FAKES_DIR/rclone" <<'EOF'
#!/bin/bash
# rclone falso: registra argumentos/ambiente e "monta" adicionando uma linha na
# tabela de montagens (TNRX_MOUNTS_FILE); sai quando recebe TERM.
[ "$1" == mount ] || exit 0
dir="$3"; esc="${dir// /\\040}"
printf '%s\n' "$*" > "$FAKE_STATE/rclone.args"
printf '%s\n' "$RCLONE_SFTP_SSH" > "$FAKE_STATE/rclone.env"
echo $$ > "$FAKE_STATE/rclone.pid"
printf 'rclone %s fuse.rclone rw 0 0\n' "$esc" >> "$TNRX_MOUNTS_FILE"
bye() { grep -vF "rclone $esc " "$TNRX_MOUNTS_FILE" > "$TNRX_MOUNTS_FILE.n"; mv "$TNRX_MOUNTS_FILE.n" "$TNRX_MOUNTS_FILE"; exit 0; }
trap bye TERM INT
while true; do sleep 0.2; done
EOF

    cat > "$FAKES_DIR/fusermount3" <<'EOF'
#!/bin/bash
# fusermount3 falso: falha se existir $FAKE_STATE/busy; senão remove a linha da
# tabela de montagens e encerra o rclone falso.
[ -e "$FAKE_STATE/busy" ] && { echo "busy" >&2; exit 1; }
dir="${@: -1}"; esc="${dir// /\\040}"
grep -vF "rclone $esc " "$TNRX_MOUNTS_FILE" > "$TNRX_MOUNTS_FILE.n"; mv "$TNRX_MOUNTS_FILE.n" "$TNRX_MOUNTS_FILE"
[ -f "$FAKE_STATE/rclone.pid" ] && kill "$(cat "$FAKE_STATE/rclone.pid")" 2>/dev/null
exit 0
EOF
    chmod +x "$FAKES_DIR"/ssh "$FAKES_DIR"/rclone "$FAKES_DIR"/fusermount3
}

setup_mount_env() {
    setup_test_env
    MT="$TEST_TEMP_DIR"
    mkdir -p "$MT/state" "$MT/home" "$MT/work/proj"
    : > "$MT/mounts"
    export PATH="$FAKES_DIR:$ORIG_PATH" HOME="$MT/home" FAKE_STATE="$MT/state" \
        TNRX_MOUNTS_FILE="$MT/mounts" TNRX_MOUNT_WAIT_SECS=5 TNRX_UNMOUNT_RETRIES=2 \
        TNRX_UNMOUNT_SLEEP=0 TNRX_RCLONE_EXIT_WAIT_SECS=3
    unset XDG_CONFIG_HOME XDG_DATA_HOME
    cd "$MT/work/proj" || exit 1
}

cleanup_mount_env() {
    export PATH="$ORIG_PATH" HOME="$ORIG_HOME"
    unset FAKE_STATE TNRX_MOUNTS_FILE TNRX_MOUNT_WAIT_SECS TNRX_UNMOUNT_RETRIES \
        TNRX_UNMOUNT_SLEEP TNRX_RCLONE_EXIT_WAIT_SECS FAKE_SSH_SESSION_SECS
    cleanup_test_env
}

mount_count() { grep -c "rclone" "$MT/mounts"; }
lock_count() { find "$HOME/.local/share/tnrx-connect/locks" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }
conf_count() { find "$HOME/.config/tnrx-connect" -name '*.conf' 2>/dev/null | wc -l | tr -d ' '; }

test_mount_first_run() {
    log_test "mount: primeira execução cria o .conf, monta com as flags certas e limpa tudo ao sair"
    setup_mount_env

    local out
    out=$(printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" 2>&1)

    local conf="$HOME/.config/tnrx-connect/user@srv_proj.conf"
    [[ -f "$conf" ]] && pass_test "conf nomeado <host>_<pasta>.conf" || fail_test "conf user@srv_proj.conf não criado" "$(ls "$HOME/.config/tnrx-connect" 2>&1)"
    local content
    content=$(cat "$conf" 2>/dev/null)
    assert_contains "$content" "LOCAL_DIR=" "conf guarda a pasta local"
    assert_contains "$content" "REMOTE_PATH=/data/proj" "conf guarda a pasta remota"

    local args env
    args=$(cat "$FAKE_STATE/rclone.args" 2>/dev/null)
    env=$(cat "$FAKE_STATE/rclone.env" 2>/dev/null)
    assert_contains "$args" ":sftp:/data/proj" "rclone monta a pasta remota escolhida"
    assert_contains "$args" "--vfs-cache-mode full" "cache full"
    assert_contains "$args" "--vfs-cache-max-age 8760h" "cache não expira em 1h"
    assert_contains "$args" "--exclude .venv/**" "esconde .venv"
    assert_contains "$env" "ControlPath=" "rclone usa a conexão mestra (ControlPath)"
    assert_contains "$env" "user@srv" "rclone usa o host informado"

    [[ "$(mount_count)" == "0" ]] && pass_test "desmontou ao sair" || fail_test "ainda montado após sair"
    [[ "$(lock_count)" == "0" ]] && pass_test "lock liberado ao sair" || fail_test "lock ficou para trás"
    ls -d "$HOME/.local/share/tnrx-connect/user@srv_proj/vfs-"* >/dev/null 2>&1 \
        && pass_test "cache persistente preservado após sair" || fail_test "cache foi apagado"
    assert_contains "$out" "cd '$MT/work/proj' && claude" "mostra como usar em outra aba"

    cleanup_mount_env
}

test_mount_second_run_uses_saved_defaults() {
    log_test "mount: segunda execução só com Enter reaproveita host e pasta"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" >/dev/null 2>&1
    local out
    out=$(printf '\n\n' | "$TNRX_CONNECT" 2>&1)

    assert_contains "$out" "Montando user@srv:/data/proj" "Enter aceita host e pasta anteriores"
    [[ "$(conf_count)" == "1" ]] && pass_test "continua um único .conf" || fail_test "criou .conf duplicado"

    cleanup_mount_env
}

test_mount_refuses_same_folder_twice() {
    log_test "mount: recusa segunda sessão na mesma pasta"
    setup_mount_env

    ( printf 'user@srv\n/data/proj\n' | FAKE_SSH_SESSION_SECS=3 "$TNRX_CONNECT" >/dev/null 2>&1 ) &
    sleep 1.5
    local out
    out=$(printf '\n' | "$TNRX_CONNECT" 2>&1)
    wait

    assert_contains "$out" "Já existe uma sessão do tnrx-connect ativa nesta pasta" "segunda sessão recusada"
    assert_not_contains "$out" "Pasta remota" "recusa antes de perguntar qualquer coisa"
    [[ "$(mount_count)" == "0" ]] && pass_test "tudo limpo depois da primeira sessão" || fail_test "sobrou mount"

    cleanup_mount_env
}

test_mount_refuses_non_empty_folder() {
    log_test "mount: recusa pasta não vazia"
    setup_mount_env

    touch arquivo.txt
    local out
    out=$(printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" 2>&1)
    assert_contains "$out" "não está vazia" "pasta com arquivo é recusada"
    assert_contains "$out" "arquivo.txt" "lista o que encontrou na pasta local"
    assert_contains "$out" "pasta LOCAL" "explica que só a pasta local precisa estar vazia"
    assert_not_contains "$out" "Autenticando" "recusa antes de pedir senha/2FA"
    assert_not_contains "$out" "Reaproveitando" "recusa antes de tocar na conexão SSH"
    [[ "$(conf_count)" == "0" ]] && pass_test "não grava .conf de uma execução recusada" || fail_test "gravou .conf"
    [[ "$(mount_count)" == "0" && "$(lock_count)" == "0" ]] && pass_test "nada montado nem travado" || fail_test "sobrou estado"

    cleanup_mount_env
}

test_mount_rejects_relative_remote_path() {
    log_test "mount: pasta remota relativa é rejeitada"
    setup_mount_env

    local out
    out=$(printf 'user@srv\nrelativo/x\n' | "$TNRX_CONNECT" 2>&1)
    assert_contains "$out" "caminho absoluto" "erro de caminho absoluto"
    [[ "$(conf_count)" == "0" ]] && pass_test "não grava .conf inválido" || fail_test "gravou .conf inválido"

    cleanup_mount_env
}

test_mount_refuses_home_dir() {
    log_test "mount: recusa rodar na home"
    setup_mount_env

    cd "$HOME" || exit 1
    local out
    out=$(printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" 2>&1)
    assert_contains "$out" "pasta de projeto dedicada" "home é recusada"

    cleanup_mount_env
}

test_mount_recovers_after_killed_session() {
    log_test "mount: sessão morta (kill -9) é recuperada na execução seguinte"
    setup_mount_env

    # SNAPSHOT_INTERVAL=1 pra o loop de snapshot órfão notar rápido que o pai morreu
    mkdir -p "$HOME/.config/tnrx-connect"
    printf 'HOST=user@srv\nREMOTE_PATH=/data/proj\nLOCAL_DIR=%s\nLAST_USED=1\nSNAPSHOT_INTERVAL=1\n' "$(pwd -P)" \
        > "$HOME/.config/tnrx-connect/user@srv_proj.conf"

    ( printf '\n\n' | FAKE_SSH_SESSION_SECS=6 "$TNRX_CONNECT" >/dev/null 2>&1 ) &
    sleep 1.5
    local pid
    pid=$(sed -n 's/^PID=//p' "$HOME"/.local/share/tnrx-connect/locks/*/info | head -1)
    kill -9 "$pid" 2>/dev/null
    sleep 0.5
    [[ "$(mount_count)" == "1" ]] && pass_test "mount órfão ficou pendurado (cenário reproduzido)" || fail_test "não reproduziu o mount órfão"

    local out
    out=$(printf '\n\n' | "$TNRX_CONNECT" 2>&1)
    assert_contains "$out" "sessão anterior" "detecta e recupera a sessão anterior"
    assert_contains "$out" "Montando user@srv:/data/proj" "remonta normalmente"
    [[ "$(mount_count)" == "0" && "$(lock_count)" == "0" ]] && pass_test "limpo ao final" || fail_test "sobrou estado"

    sleep 2.5
    # padrão ancorado no início da linha: só casa com "bash <caminho>/tnrx-connect ..."
    local orphan_re="^(/[A-Za-z0-9_./-]*/)?bash $TNRX_CONNECT( |\$)"
    [[ -z "$(pgrep -f "$orphan_re")" ]] \
        && pass_test "o loop de snapshot da sessão morta não ficou órfão" \
        || fail_test "sobrou processo tnrx-connect órfão" "$(pgrep -af "$orphan_re")"

    cleanup_mount_env
}

test_mount_busy_unmount_keeps_state() {
    log_test "mount: desmontagem ocupada mantém o mount/lock e 'unmount' resolve depois"
    setup_mount_env

    touch "$FAKE_STATE/busy"
    local out
    out=$(printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" 2>&1)
    assert_contains "$out" "A montagem continua ativa" "avisa que a montagem continua"
    [[ "$(mount_count)" == "1" ]] && pass_test "continua montado (nada de dados perdidos)" || fail_test "desmontou à força"
    [[ "$(lock_count)" == "1" ]] && pass_test "lock mantido" || fail_test "lock perdido"

    rm -f "$FAKE_STATE/busy"
    out=$("$TNRX_CONNECT" unmount 2>&1)
    assert_contains "$out" "desmontada" "unmount desmonta"
    [[ "$(mount_count)" == "0" && "$(lock_count)" == "0" ]] && pass_test "estado limpo após unmount" || fail_test "sobrou estado"

    cleanup_mount_env
}

test_mount_conf_name_collision() {
    log_test "mount: mesmo nome de pasta em caminhos diferentes não colide"
    setup_mount_env

    mkdir -p "$MT/work/a/proj" "$MT/work/b/proj"
    ( cd "$MT/work/a/proj" && printf 'user@srv\n/data/a\n' | "$TNRX_CONNECT" >/dev/null 2>&1 )
    ( cd "$MT/work/b/proj" && printf 'user@srv\n/data/b\n' | "$TNRX_CONNECT" >/dev/null 2>&1 )

    [[ "$(conf_count)" == "2" ]] && pass_test "dois .conf distintos" || fail_test "colisão de .conf" "$(ls "$HOME/.config/tnrx-connect")"
    ls "$HOME/.config/tnrx-connect" | grep -q 'user@srv_proj-[0-9]*\.conf' \
        && pass_test "o segundo ganhou sufixo de hash" || fail_test "sem sufixo de hash"

    cleanup_mount_env
}

test_mount_multiple_confs_same_folder() {
    log_test "mount: pasta usada com dois hosts pergunta qual usar (mais recente primeiro)"
    setup_mount_env

    printf 'user@um\n/data/x\n' | "$TNRX_CONNECT" >/dev/null 2>&1
    sleep 1
    printf 'user@dois\n/data/y\n' | "$TNRX_CONNECT" >/dev/null 2>&1

    local out
    out=$(printf '\n\n\n' | "$TNRX_CONNECT" 2>&1)
    assert_contains "$out" "mais de uma configuração" "lista as configurações da pasta"
    assert_contains "$out" "Montando user@dois:/data/y" "o padrão é o mais recente"

    cleanup_mount_env
}

test_mount_snapshot_history_restore() {
    log_test "mount: snapshots, history e restore (git sombra fora do projeto)"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" >/dev/null 2>&1
    printf 'rclone %s fuse.rclone rw 0 0\n' "$PWD" >> "$MT/mounts"

    echo "v1" > a.py; echo "dado" > b.txt
    "$TNRX_CONNECT" snapshot >/dev/null 2>&1
    echo "v2" > a.py
    "$TNRX_CONNECT" snapshot >/dev/null 2>&1
    echo "v3-ruim" > a.py

    local hist first
    hist=$("$TNRX_CONNECT" history)
    [[ "$(echo "$hist" | wc -l | tr -d ' ')" == "2" ]] && pass_test "history lista os 2 snapshots" || fail_test "history inesperado" "$hist"

    first=$(echo "$hist" | tail -1 | cut -d' ' -f1)
    "$TNRX_CONNECT" restore "$first" a.py >/dev/null 2>&1
    [[ "$(cat a.py)" == "v1" ]] && pass_test "restore de um arquivo volta a versão do snapshot" || fail_test "a.py não restaurado" "$(cat a.py)"
    "$TNRX_CONNECT" history | grep -q "antes de restaurar" \
        && pass_test "restore tira um snapshot de segurança antes" || fail_test "sem snapshot de segurança"

    echo "lixo" > b.txt
    "$TNRX_CONNECT" restore "$first" >/dev/null 2>&1
    [[ "$(cat b.txt)" == "dado" ]] && pass_test "restore sem caminho restaura a árvore toda" || fail_test "b.txt não restaurado" "$(cat b.txt)"

    [[ ! -e "$PWD/.git" ]] && pass_test "não cria .git dentro do projeto" || fail_test ".git apareceu no projeto"
    local status_out
    status_out=$("$TNRX_CONNECT" status)
    assert_contains "$status_out" "Servidor:  user@srv:/data/proj" "status mostra o servidor"
    assert_contains "$status_out" "Sessão:    inativa" "status mostra sessão inativa"

    cleanup_mount_env
}

test_mount_snapshot_skips_big_files() {
    log_test "mount: snapshot ignora arquivos acima do limite de tamanho"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" >/dev/null 2>&1
    printf 'rclone %s fuse.rclone rw 0 0\n' "$PWD" >> "$MT/mounts"
    echo "ok" > pequeno.txt
    head -c 6000000 /dev/zero > grande.bin
    "$TNRX_CONNECT" snapshot >/dev/null 2>&1

    local tracked
    tracked=$(git --git-dir="$HOME/.local/share/tnrx-connect/user@srv_proj/shadow.git" ls-tree -r --name-only HEAD 2>&1)
    assert_contains "$tracked" "pequeno.txt" "arquivo pequeno entra no snapshot"
    assert_not_contains "$tracked" "grande.bin" "arquivo de 6MB fica de fora (limite 5MB)"

    cleanup_mount_env
}

test_mount_snapshot_requires_mount() {
    log_test "mount: sem montagem não tira snapshot nem restaura (evita gravar 'tudo apagado')"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" >/dev/null 2>&1
    local out
    out=$("$TNRX_CONNECT" snapshot 2>&1)
    assert_contains "$out" "Não foi possível tirar o snapshot" "snapshot recusado sem mount"
    out=$("$TNRX_CONNECT" restore abc123 2>&1)
    assert_contains "$out" "não está montada" "restore recusado sem mount"

    cleanup_mount_env
}

test_mount_refresh_sends_hup() {
    log_test "mount: refresh manda SIGHUP ao rclone da sessão ativa"
    setup_mount_env

    local dir hash owner mpid
    dir=$(pwd -P)
    mkdir -p "$HOME/.config/tnrx-connect"
    printf 'HOST=user@srv\nREMOTE_PATH=/data/proj\nLOCAL_DIR=%s\nLAST_USED=1\n' "$dir" \
        > "$HOME/.config/tnrx-connect/user@srv_proj.conf"

    bash -c 'exec -a tnrx-connect sleep 20' &
    owner=$!
    bash -c "trap 'touch \"$MT/got_hup\"' HUP; while true; do sleep 0.1; done" &
    mpid=$!
    hash=$(printf '%s' "$dir" | cksum | awk '{print $1}')
    mkdir -p "$HOME/.local/share/tnrx-connect/locks/$hash.d"
    printf 'PID=%s\nHOST=user@srv\nREMOTE_PATH=/data/proj\nLOCAL_DIR=%s\nID=user@srv_proj\nSTART=1\nMOUNT_PID=%s\n' \
        "$owner" "$dir" "$mpid" > "$HOME/.local/share/tnrx-connect/locks/$hash.d/info"

    local out
    out=$("$TNRX_CONNECT" refresh 2>&1)
    sleep 0.5
    assert_contains "$out" "Cache de diretórios limpo" "refresh confirma"
    [[ -f "$MT/got_hup" ]] && pass_test "o processo do rclone recebeu SIGHUP" || fail_test "SIGHUP não chegou"

    kill "$owner" "$mpid" 2>/dev/null
    wait "$owner" "$mpid" 2>/dev/null
    cleanup_mount_env
}

test_usage_lists_both_modes() {
    log_test "uso lista o modo mount e o modo rsync"
    setup_test_env

    local output
    output=$("$TNRX_CONNECT" invalido 2>&1)
    assert_contains "$output" "Modo mount" "menciona o modo mount"
    assert_contains "$output" "Modo rsync" "menciona o modo rsync"

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

    # Modo mount (com ssh/rclone/fusermount3 falsos)
    make_fakes
    test_usage_lists_both_modes
    test_mount_first_run
    test_mount_second_run_uses_saved_defaults
    test_mount_refuses_same_folder_twice
    test_mount_refuses_non_empty_folder
    test_mount_rejects_relative_remote_path
    test_mount_refuses_home_dir
    test_mount_recovers_after_killed_session
    test_mount_busy_unmount_keeps_state
    test_mount_conf_name_collision
    test_mount_multiple_confs_same_folder
    test_mount_snapshot_history_restore
    test_mount_snapshot_skips_big_files
    test_mount_snapshot_requires_mount
    test_mount_refresh_sends_hup
    rm -rf "$FAKES_DIR"

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
