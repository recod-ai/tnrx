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
    log_test "uninstall: remove os comandos e a pasta da instalação (num HOME temporário)"
    setup_test_env

    # HOME temporário: o uninstall apaga ~/.local/bin/tnrx* e ~/.local/share/tnrx.
    local output exit_code
    output=$(HOME="$TEST_TEMP_DIR/home" "$TNRX_CONNECT" uninstall 2>&1)
    exit_code=$?
    [[ $exit_code -eq 0 ]] && pass_test "uninstall exits 0 with nothing installed" || fail_test "uninstall should exit 0 even with nothing to remove" "$output"

    mkdir -p home/.local/bin home/.local/share/tnrx
    ln -s "$TEST_TEMP_DIR/home/.local/share/tnrx/tnrx-connect" home/.local/bin/tnrx-connect
    output=$(HOME="$TEST_TEMP_DIR/home" "$TNRX_CONNECT" uninstall 2>&1)
    if [[ ! -L home/.local/bin/tnrx-connect && ! -d home/.local/share/tnrx ]]; then
        pass_test "uninstall remove o link e a pasta da instalação"
    else
        fail_test "uninstall deixou restos" "$output"
    fi

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
ctrl=""; mode=""; lspec=""; args=("$@")
for ((i=0;i<${#args[@]};i++)); do
  case "${args[$i]}" in
    -O) mode="${args[$((i+1))]}";;
    -L) lspec="${args[$((i+1))]}";;
    -o) o="${args[$((i+1))]}"; [[ "$o" == ControlPath=* ]] && ctrl="${o#ControlPath=}";;
  esac
done
[ "$mode" == check ] && { [ -f "$ctrl" ] && exit 0 || exit 1; }
[ "$mode" == exit ] && { rm -f "$ctrl"; exit 0; }
[ "$mode" == forward ] && {
  [ -f "$ctrl" ] || exit 255
  p=$(printf '%s' "$lspec" | cut -d: -f2)
  for b in $FAKE_BUSY_PORTS; do [ "$b" == "$p" ] && exit 255; done
  echo "forward $lspec" >> "$FAKE_STATE/ssh.fwd"; exit 0
}
[ "$mode" == cancel ] && { echo "cancel $lspec" >> "$FAKE_STATE/ssh.fwd"; exit 0; }
for a in "${args[@]}"; do [ "$a" == "-fN" ] && { touch "$ctrl"; exit 0; }; done
for a in "${args[@]}"; do [ "$a" == "-t" ] && { sleep "${FAKE_SSH_SESSION_SECS:-0}"; exit 0; }; done
export HOME="${FAKE_REMOTE_HOME:-$HOME}"; bash -c "${args[-1]}"
EOF

    cat > "$FAKES_DIR/rclone" <<'EOF'
#!/bin/bash
# rclone falso: registra argumentos/ambiente e "monta" adicionando uma linha na
# tabela de montagens (TNRX_MOUNTS_FILE); sai quando recebe TERM.
[ "$1" == mount ] || exit 0
[ -n "$FAKE_RCLONE_FAIL" ] && exit 1
dir="$3"; esc="${dir// /\\040}"
printf '%s\n' "$*" > "$FAKE_STATE/rclone.args"
printf '%s\n' "$RCLONE_SFTP_SSH" > "$FAKE_STATE/rclone.env"
echo $$ > "$FAKE_STATE/rclone.pid"
mkdir -p "$FAKE_STATE/pids"; echo $$ > "$FAKE_STATE/pids/$(printf '%s' "$dir" | cksum | cut -d' ' -f1)"
printf 'rclone %s fuse.rclone rw 0 0\n' "$esc" >> "$TNRX_MOUNTS_FILE"
bye() { grep -vF "rclone $esc " "$TNRX_MOUNTS_FILE" > "$TNRX_MOUNTS_FILE.n"; mv "$TNRX_MOUNTS_FILE.n" "$TNRX_MOUNTS_FILE"; exit 0; }
trap bye TERM INT
trap 'touch "$FAKE_STATE/got_hup"' HUP
while true; do sleep 0.2; done
EOF

    cat > "$FAKES_DIR/fusermount3" <<'EOF'
#!/bin/bash
# fusermount3 falso: com $FAKE_STATE/busy, "-u" simples falha (como um leitor ainda
# aberto travando um umount educado de verdade); "-uz" (lazy) sempre desanexa na hora,
# como o umount -l real faz, e mantém o processo fake do rclone vivo se ainda houver
# leitor (o teste só confere a desmontagem em si, não a demora do rclone morrer).
lazy=false; for a in "$@"; do [ "$a" == "-uz" ] && lazy=true; done
if [ -e "$FAKE_STATE/busy" ] && [ "$lazy" != "true" ]; then echo "busy" >&2; exit 1; fi
dir="${@: -1}"; esc="${dir// /\\040}"
grep -vF "rclone $esc " "$TNRX_MOUNTS_FILE" > "$TNRX_MOUNTS_FILE.n"; mv "$TNRX_MOUNTS_FILE.n" "$TNRX_MOUNTS_FILE"
if [ -e "$FAKE_STATE/busy" ] && [ "$lazy" == "true" ]; then exit 0; fi
pf="$FAKE_STATE/pids/$(printf '%s' "$dir" | cksum | cut -d' ' -f1)"
[ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null
exit 0
EOF
    cat > "$FAKES_DIR/tnrx" <<'EOF'
#!/bin/bash
# tnrx falso (servidor): "uvslurm jupyter lab" escreve no log como o srun, espera
# FAKE_TNRX_DELAY, escuta numa porta (o Jupyter) e registra .tnrx/jupyter/777.env com a
# senha de .tnrx/jupyter/token. TERM (cancelamento) derruba tudo e deixa um marcador.
[ "$1 $2" == "uvslurm jupyter" ] || exit 0
[ -n "$FAKE_TNRX_FAIL" ] && { echo "Erro: Nenhum arquivo .sif encontrado"; exit 1; }
echo "srun: job 777 queued and waiting for resources"
lp=""
trap 'touch "$FAKE_STATE/tnrx_cancelled"; [ -n "$lp" ] && kill "$lp"; exit 143' TERM
sleep "${FAKE_TNRX_DELAY:-1}" & wait $!
port="${FAKE_TNRX_PORT:-48990}"
python3 -c "
import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', $port)); s.listen(); time.sleep(20)" &
lp=$!
sleep 0.3
token=$(cat .tnrx/jupyter/token 2>/dev/null || echo ffff)
printf 'NODE=127.0.0.1\nPORT=%s\nTOKEN=%s\nJOBID=777\nSTARTED=%s\n' "$port" "$token" "$(date +%s)" > .tnrx/jupyter/777.env
wait "$lp"
EOF
    # Slurm falso (servidor): l40s com 4 nós (um em drain), a100 com 2 nós fora do ar.
    cat > "$FAKES_DIR/sinfo" <<'EOF'
#!/bin/bash
echo 'P|l40s*|up|7-00:00:00|2/1/0/3|gpu:l40s:2'
echo 'P|a100|up|2-00:00:00|0/0/1/1|gpu:a100:4'
echo 'P|l40s*|up|7-00:00:00|0/0/1/1|gpu:l40s:2'
echo 'P|a100|up|2-00:00:00|0/0/1/1|gpu:a100:4'
EOF
    cat > "$FAKES_DIR/scontrol" <<'EOF'
#!/bin/bash
echo 'NodeName=dl-01 Arch=x86_64 State=MIXED Partitions=l40s CfgTRES=cpu=32,mem=256G,billing=32,gres/gpu=2 AllocTRES=cpu=4,mem=16G,gres/gpu=1 OS=Linux 5.15 #1 SMP'
echo 'NodeName=dl-02 State=IDLE Partitions=l40s CfgTRES=cpu=32,gres/gpu=2 AllocTRES='
echo 'NodeName=dl-03 State=IDLE+DRAIN Partitions=l40s CfgTRES=cpu=32,gres/gpu=2 AllocTRES= Reason=Not responding [root@2026-10-01]'
echo 'NodeName=dl-04 State=ALLOCATED Partitions=l40s CfgTRES=cpu=32,gres/gpu=2,gres/gpu:l40s=2 AllocTRES=cpu=32,gres/gpu=2'
echo 'NodeName=a-01 State=DOWN* Partitions=a100 CfgTRES=cpu=64,gres/gpu=4 AllocTRES='
echo 'NodeName=a-02 State=DOWN* Partitions=a100 CfgTRES=cpu=64,gres/gpu=4 AllocTRES='
EOF
    cat > "$FAKES_DIR/squeue" <<'EOF'
#!/bin/bash
# "-o %i" (ids dos jobs vivos, usado na descoberta do Jupyter): só com $FAKE_STATE/squeue_ids;
# sem ele, falha (como um servidor sem squeue) e a descoberta usa só o teste da porta.
if [[ "$*" == *"-o %i"* ]]; then [ -f "$FAKE_STATE/squeue_ids" ] && cat "$FAKE_STATE/squeue_ids" && exit 0; exit 1; fi
echo 'J|95272|l40s|jupyter|RUNNING|3:01|2:00:00|dl-05|/data/proj'
echo 'J|95300|a100|train "x"|PENDING|0:00|1-00:00:00|(Resources)|/data/outro proj'
EOF
    cat > "$FAKES_DIR/scancel" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_STATE/scancel"
[ "$1" == 999 ] && { echo "scancel: error: Invalid job id specified" >&2; exit 1; }
pkill -TERM -f "$(dirname "$0")/tnrx uvslurm" 2>/dev/null
exit 0
EOF
    chmod +x "$FAKES_DIR"/ssh "$FAKES_DIR"/rclone "$FAKES_DIR"/fusermount3 "$FAKES_DIR"/tnrx \
        "$FAKES_DIR"/sinfo "$FAKES_DIR"/scontrol "$FAKES_DIR"/squeue "$FAKES_DIR"/scancel
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
    # Montagens que um teste deixou de pé: o rclone falso sai e o loop de snapshots junto.
    local pf
    for pf in "$FAKE_STATE"/pids/*; do [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null; done
    export PATH="$ORIG_PATH" HOME="$ORIG_HOME"
    unset FAKE_STATE TNRX_MOUNTS_FILE TNRX_MOUNT_WAIT_SECS TNRX_UNMOUNT_RETRIES \
        TNRX_UNMOUNT_SLEEP TNRX_RCLONE_EXIT_WAIT_SECS FAKE_SSH_SESSION_SECS
    cleanup_test_env
}

mount_count() { grep -c "rclone" "$MT/mounts"; }
lock_count() { find "$HOME/.local/share/tnrx-connect/locks" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }
conf_count() { find "$HOME/.config/tnrx-connect" -name '*.conf' 2>/dev/null | wc -l | tr -d ' '; }
ctrl_sock() { printf '%s/.cache/tnrx-connect/ssh-%s.sock' "$HOME" "$(printf '%s' "${1:-user@srv}" | cksum | awk '{print $1}')"; }
rclone_pid() { cat "$FAKE_STATE/rclone.pid" 2>/dev/null; }
snap_loops() { pgrep -f "__snapshot-loop $MT/" 2>/dev/null; }

test_mount_first_run() {
    log_test "mount: tnrx-connect monta, abre o SSH e a pasta CONTINUA montada ao sair; umount limpa"
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
    assert_contains "$out" "cd '$MT/work/proj' && claude" "mostra como usar em outra aba"
    assert_contains "$out" "Conectando em user@srv" "abre o terminal SSH"
    assert_contains "$out" "continua montada" "avisa que sair do terminal não desmonta"

    [[ "$(mount_count)" == "1" ]] && pass_test "continua montado depois que o terminal fechou" || fail_test "desmontou ao sair do terminal"
    kill -0 "$(rclone_pid)" 2>/dev/null && pass_test "rclone segue vivo sem o tnrx-connect" || fail_test "rclone morreu junto com o terminal"
    [[ -f "$(ctrl_sock)" ]] && pass_test "conexão mestra segue aberta (o rclone depende dela)" || fail_test "fechou a conexão mestra"
    [[ -n "$(snap_loops)" ]] && pass_test "loop de snapshots segue rodando" || fail_test "loop de snapshots morreu"

    out=$("$TNRX_CONNECT" umount 2>&1)
    assert_contains "$out" "desmontada" "umount desmonta"
    [[ "$(mount_count)" == "0" && "$(lock_count)" == "0" ]] && pass_test "umount libera mount e lock" || fail_test "sobrou estado" "$(cat "$MT/mounts")"
    [[ ! -f "$(ctrl_sock)" ]] && pass_test "umount fecha a conexão mestra sem uso" || fail_test "conexão mestra ficou aberta"
    sleep 1.5
    [[ -z "$(snap_loops)" ]] && pass_test "loop de snapshots terminou" || fail_test "loop de snapshots órfão" "$(pgrep -af "__snapshot-loop")"
    ls -d "$HOME/.local/share/tnrx-connect/user@srv_proj/vfs-"* >/dev/null 2>&1 \
        && pass_test "cache persistente preservado após umount" || fail_test "cache foi apagado"

    cleanup_mount_env
}

test_mount_command_returns_prompt() {
    log_test "mount: 'tnrx-connect mount' monta e devolve o prompt (sem abrir SSH)"
    setup_mount_env

    local out
    out=$(printf 'user@srv\n/data/proj\n' | FAKE_SSH_SESSION_SECS=30 timeout 10 "$TNRX_CONNECT" mount 2>&1)
    [[ $? -eq 0 ]] && pass_test "mount termina sozinho" || fail_test "mount não devolveu o prompt"
    assert_not_contains "$out" "Conectando em" "não abre terminal SSH"
    assert_contains "$out" "tnrx-connect ssh" "explica como abrir o terminal"
    assert_contains "$out" "tnrx-connect umount" "explica como desmontar"
    [[ "$(mount_count)" == "1" ]] && pass_test "montado" || fail_test "não montou"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    cleanup_mount_env
}

test_mount_is_idempotent() {
    log_test "mount: montar de novo a mesma pasta só confirma que já está montada"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    local first out
    first=$(rclone_pid)
    out=$("$TNRX_CONNECT" mount 2>&1 </dev/null)
    assert_contains "$out" "já está montada" "avisa que já está montada"
    assert_not_contains "$out" "Pasta remota" "não pergunta nada"
    [[ "$(rclone_pid)" == "$first" && "$(mount_count)" == "1" ]] && pass_test "não sobe outro rclone" || fail_test "montou de novo"

    out=$("$TNRX_CONNECT" 2>&1 </dev/null)
    assert_not_contains "$out" "Pasta remota" "tnrx-connect sem argumentos numa pasta montada não pergunta nada"
    assert_contains "$out" "Conectando em user@srv" "e só abre o terminal"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    cleanup_mount_env
}

test_mount_second_run_uses_saved_defaults() {
    log_test "mount: depois de desmontar, montar só com Enter reaproveita host e pasta"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    "$TNRX_CONNECT" umount >/dev/null 2>&1
    local out
    out=$(printf '\n\n' | "$TNRX_CONNECT" mount 2>&1)

    assert_contains "$out" "Montando user@srv:/data/proj" "Enter aceita host e pasta anteriores"
    [[ "$(conf_count)" == "1" ]] && pass_test "continua um único .conf" || fail_test "criou .conf duplicado"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    cleanup_mount_env
}

test_mount_refuses_non_empty_folder() {
    log_test "mount: recusa pasta não vazia"
    setup_mount_env

    touch arquivo.txt
    local out
    out=$(printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount 2>&1)
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
    out=$(printf 'user@srv\nrelativo/x\n' | "$TNRX_CONNECT" mount 2>&1)
    assert_contains "$out" "caminho absoluto" "erro de caminho absoluto"
    [[ "$(conf_count)" == "0" ]] && pass_test "não grava .conf inválido" || fail_test "gravou .conf inválido"

    cleanup_mount_env
}

test_mount_refuses_home_dir() {
    log_test "mount: recusa rodar na home"
    setup_mount_env

    cd "$HOME" || exit 1
    local out
    out=$(printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount 2>&1)
    assert_contains "$out" "pasta de projeto dedicada" "home é recusada"

    cleanup_mount_env
}

test_mount_failure_cleans_up() {
    log_test "mount: se o rclone falha, não sobra lock nem conexão mestra"
    setup_mount_env

    local out
    out=$(printf 'user@srv\n/data/proj\n' | FAKE_RCLONE_FAIL=1 "$TNRX_CONNECT" mount 2>&1)
    assert_contains "$out" "O rclone terminou antes de montar" "explica a falha"
    [[ "$(mount_count)" == "0" && "$(lock_count)" == "0" ]] && pass_test "sem mount nem lock" || fail_test "sobrou estado"
    [[ ! -f "$(ctrl_sock)" ]] && pass_test "fecha a conexão mestra que abriu" || fail_test "conexão mestra ficou aberta"

    cleanup_mount_env
}

test_ssh_requires_mount() {
    log_test "ssh: só abre o terminal se a pasta estiver montada"
    setup_mount_env

    local out
    out=$("$TNRX_CONNECT" ssh 2>&1)
    [[ $? -ne 0 ]] && pass_test "sem configuração: falha" || fail_test "deveria falhar"
    assert_contains "$out" "tnrx-connect mount" "sem configuração: manda montar"

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    "$TNRX_CONNECT" umount >/dev/null 2>&1
    out=$("$TNRX_CONNECT" ssh 2>&1)
    assert_contains "$out" "não está montada" "configurada mas desmontada: recusa"
    assert_not_contains "$out" "Conectando" "não conecta"
    assert_not_contains "$out" "Autenticando" "não pede senha/2FA"

    cleanup_mount_env
}

test_ssh_from_subfolder_and_master_lost() {
    log_test "ssh: de uma subpasta abre na pasta remota correspondente; com a conexão caída manda remontar"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    mkdir -p "sub dir/x"
    local out
    out=$(cd "sub dir/x" && "$TNRX_CONNECT" --debug ssh 2>&1)
    assert_contains "$out" "Conectando em user@srv (/data/proj/sub dir/x)" "abre na subpasta remota correspondente"
    assert_contains "$out" "cd\\ /data/proj/sub" "o comando remoto faz cd nela"
    assert_contains "$out" "continua montada" "sair do terminal não desmonta"
    [[ "$(mount_count)" == "1" ]] && pass_test "segue montado depois do ssh" || fail_test "ssh desmontou"

    rm -f "$(ctrl_sock)"
    out=$("$TNRX_CONNECT" ssh 2>&1)
    assert_contains "$out" "caiu" "detecta a conexão caída"
    assert_contains "$out" "tnrx-connect mount" "manda rodar mount"
    out=$("$TNRX_CONNECT" mount 2>&1 </dev/null)
    assert_contains "$out" "reautenticando" "mount numa pasta montada reautentica"
    [[ -f "$(ctrl_sock)" ]] && pass_test "conexão mestra de volta" || fail_test "não reconectou"
    out=$("$TNRX_CONNECT" status 2>&1)
    assert_contains "$out" "Conexão:   ativa" "status mostra a conexão ativa"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    cleanup_mount_env
}

test_mount_recovers_after_rclone_crash() {
    log_test "mount: rclone morto (kill -9) deixa a pasta pendurada; o próximo mount recupera"
    setup_mount_env

    mkdir -p "$HOME/.config/tnrx-connect"
    printf 'HOST=user@srv\nREMOTE_PATH=/data/proj\nLOCAL_DIR=%s\nLAST_USED=1\nSNAPSHOT_INTERVAL=1\n' "$(pwd -P)" \
        > "$HOME/.config/tnrx-connect/user@srv_proj.conf"

    printf '\n\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    kill -9 "$(rclone_pid)" 2>/dev/null
    sleep 0.3
    [[ "$(mount_count)" == "1" ]] && pass_test "mount órfão ficou pendurado (cenário reproduzido)" || fail_test "não reproduziu o mount órfão"
    local out
    out=$("$TNRX_CONNECT" status 2>&1)
    assert_contains "$out" "o rclone não está rodando" "status aponta o mount pendurado"

    out=$(printf '\n\n' | "$TNRX_CONNECT" mount 2>&1)
    assert_contains "$out" "sessão anterior" "detecta e recupera a montagem anterior"
    assert_contains "$out" "Montando user@srv:/data/proj" "remonta normalmente"
    [[ "$(mount_count)" == "1" ]] && pass_test "montado de novo" || fail_test "não remontou"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    [[ "$(mount_count)" == "0" && "$(lock_count)" == "0" ]] && pass_test "limpo ao final" || fail_test "sobrou estado"
    sleep 1.5
    local orphan_re="^(/[A-Za-z0-9_./-]*/)?bash $TNRX_CONNECT( |\$)"
    [[ -z "$(pgrep -f "$orphan_re")" ]] \
        && pass_test "nenhum loop de snapshot ficou órfão" \
        || fail_test "sobrou processo tnrx-connect órfão" "$(pgrep -af "$orphan_re")"

    cleanup_mount_env
}

test_mount_recovers_while_busy() {
    log_test "mount: recuperação resolve sozinha mesmo com algo ainda “usando” a montagem antiga, sem esperar por isso"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    local old
    old=$(rclone_pid)
    # A montagem foi desanexada (ex.: umount -l externo) mas algo segura um descritor
    # velho (Nautilus, outra aba): o rclone antigo não morre sozinho.
    touch "$FAKE_STATE/busy"
    fusermount3 -uz "$(pwd -P)"
    kill -0 "$old" 2>/dev/null && pass_test "rclone antigo segue vivo (cenário reproduzido)" || fail_test "não reproduziu"

    local out
    out=$(printf '\n\n' | TNRX_RECOVER_KILL_GRACE_SECS=1 "$TNRX_CONNECT" mount 2>&1)
    assert_contains "$out" "sessão anterior" "detecta a montagem anterior"
    assert_not_contains "$out" "Feche o que usa a pasta" "não pede pra caçar o que está aberto"
    assert_contains "$out" "encerrando o processo antigo" "encerra o processo órfão em vez de esperar"
    assert_contains "$out" "Montando user@srv:/data/proj" "remonta"
    [[ "$(mount_count)" == "1" ]] && pass_test "montado de novo (o leitor antigo não bloqueou nada)" || fail_test "não remontou"
    kill -0 "$old" 2>/dev/null && fail_test "rclone antigo ainda vivo" || pass_test "rclone antigo encerrado"

    rm -f "$FAKE_STATE/busy"
    "$TNRX_CONNECT" umount >/dev/null 2>&1
    [[ "$(mount_count)" == "0" && "$(lock_count)" == "0" ]] && pass_test "umount limpa normalmente" || fail_test "sobrou estado"

    cleanup_mount_env
}

test_mount_busy_unmount_keeps_state() {
    log_test "umount: pasta em uso mantém montagem, lock e snapshots; -f ou umount depois resolve"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    touch "$FAKE_STATE/busy"
    local out
    out=$("$TNRX_CONNECT" umount 2>&1)
    assert_contains "$out" "continua montada" "avisa que a montagem continua"
    assert_contains "$out" "umount . -f" "sugere o -f"
    [[ "$(mount_count)" == "1" ]] && pass_test "continua montado (nada de dados perdidos)" || fail_test "desmontou à força"
    [[ "$(lock_count)" == "1" ]] && pass_test "lock mantido" || fail_test "lock perdido"
    [[ -n "$(snap_loops)" ]] && pass_test "snapshots automáticos voltaram a rodar" || fail_test "loop de snapshots não voltou"
    [[ -f "$(ctrl_sock)" ]] && pass_test "conexão mestra mantida" || fail_test "fechou a conexão de um mount vivo"

    rm -f "$FAKE_STATE/busy"
    out=$("$TNRX_CONNECT" umount 2>&1)
    assert_contains "$out" "desmontada" "umount desmonta"
    [[ "$(mount_count)" == "0" && "$(lock_count)" == "0" ]] && pass_test "estado limpo após umount" || fail_test "sobrou estado"

    cleanup_mount_env
}

test_umount_from_subfolder() {
    log_test "umount: rodado numa subpasta desmonta a pasta montada acima"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    mkdir -p sub
    local out
    out=$(cd sub && "$TNRX_CONNECT" umount 2>&1)
    assert_contains "$out" "$MT/work/proj desmontada" "desmonta a raiz da montagem"
    [[ "$(mount_count)" == "0" ]] && pass_test "desmontado" || fail_test "continua montado"

    cleanup_mount_env
}

test_umount_keeps_master_used_elsewhere() {
    log_test "umount: não fecha a conexão mestra que outra montagem (ou um terminal ssh) ainda usa"
    setup_mount_env

    mkdir -p "$MT/work/a" "$MT/work/b"
    ( cd "$MT/work/a" && printf 'user@srv\n/data/a\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1 )
    ( cd "$MT/work/b" && printf 'user@srv\n/data/b\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1 )
    ( cd "$MT/work/a" && "$TNRX_CONNECT" umount >/dev/null 2>&1 )
    [[ -f "$(ctrl_sock)" ]] && pass_test "conexão mantida enquanto 'b' está montada" || fail_test "fechou a conexão de 'b'"
    grep -q "$MT/work/b " "$MT/mounts" && pass_test "'b' continua montada" || fail_test "'b' foi desmontada junto"

    ( cd "$MT/work/b" && FAKE_SSH_SESSION_SECS=3 "$TNRX_CONNECT" ssh >/dev/null 2>&1 ) &
    local spid=$!
    sleep 1
    ( cd "$MT/work/b" && "$TNRX_CONNECT" umount >/dev/null 2>&1 )
    [[ -f "$(ctrl_sock)" ]] && pass_test "conexão mantida enquanto há um terminal ssh aberto" || fail_test "derrubou o terminal ssh"
    wait "$spid"
    [[ ! -f "$(ctrl_sock)" ]] && pass_test "o ssh fecha a conexão ao sair quando nada mais a usa" || fail_test "conexão ficou aberta"

    cleanup_mount_env
}

test_mount_conf_name_collision() {
    log_test "mount: mesmo nome de pasta em caminhos diferentes não colide"
    setup_mount_env

    mkdir -p "$MT/work/a/proj" "$MT/work/b/proj"
    ( cd "$MT/work/a/proj" && printf 'user@srv\n/data/a\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1 )
    ( cd "$MT/work/b/proj" && printf 'user@srv\n/data/b\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1 )

    [[ "$(conf_count)" == "2" ]] && pass_test "dois .conf distintos" || fail_test "colisão de .conf" "$(ls "$HOME/.config/tnrx-connect")"
    ls "$HOME/.config/tnrx-connect" | grep -q 'user@srv_proj-[0-9]*\.conf' \
        && pass_test "o segundo ganhou sufixo de hash" || fail_test "sem sufixo de hash"
    [[ "$(mount_count)" == "2" ]] && pass_test "as duas montadas ao mesmo tempo" || fail_test "esperava 2 mounts"

    "$TNRX_CONNECT" umount "$MT/work/a/proj" >/dev/null 2>&1
    "$TNRX_CONNECT" umount "$MT/work/b/proj" >/dev/null 2>&1
    cleanup_mount_env
}

test_mount_multiple_confs_same_folder() {
    log_test "mount: pasta usada com dois hosts pergunta qual usar (mais recente primeiro)"
    setup_mount_env

    printf 'user@um\n/data/x\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    "$TNRX_CONNECT" umount >/dev/null 2>&1
    sleep 1
    printf 'user@dois\n/data/y\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    "$TNRX_CONNECT" umount >/dev/null 2>&1

    local out
    out=$(printf '\n\n\n' | "$TNRX_CONNECT" mount 2>&1)
    assert_contains "$out" "mais de uma configuração" "lista as configurações da pasta"
    assert_contains "$out" "Montando user@dois:/data/y" "o padrão é o mais recente"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    cleanup_mount_env
}

test_mount_snapshot_history_restore() {
    log_test "mount: snapshots, history e restore (git sombra fora do projeto)"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1

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
    assert_contains "$status_out" "Montada:   sim" "status mostra a montagem ativa"

    echo "v4" > a.py
    "$TNRX_CONNECT" umount >/dev/null 2>&1
    "$TNRX_CONNECT" history | grep -q "snapshot final" \
        && pass_test "umount tira o snapshot final" || fail_test "sem snapshot final"
    status_out=$("$TNRX_CONNECT" status)
    assert_contains "$status_out" "Montada:   não" "status depois do umount"

    cleanup_mount_env
}

test_mount_auto_snapshots_without_terminal() {
    log_test "mount: snapshots automáticos rodam com a pasta montada, sem nenhum terminal aberto"
    setup_mount_env

    mkdir -p "$HOME/.config/tnrx-connect"
    printf 'HOST=user@srv\nREMOTE_PATH=/data/proj\nLOCAL_DIR=%s\nLAST_USED=1\nSNAPSHOT_INTERVAL=1\n' "$(pwd -P)" \
        > "$HOME/.config/tnrx-connect/user@srv_proj.conf"
    printf '\n\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    echo "x" > auto.txt
    local i
    for i in $(seq 1 30); do
        "$TNRX_CONNECT" history 2>/dev/null | grep -q snapshot && break
        sleep 0.2
    done
    "$TNRX_CONNECT" history 2>/dev/null | grep -q snapshot \
        && pass_test "snapshot automático registrado" || fail_test "nenhum snapshot automático"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    cleanup_mount_env
}

test_mount_snapshot_skips_big_files() {
    log_test "mount: snapshot ignora arquivos acima do limite de tamanho"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    echo "ok" > pequeno.txt
    head -c 6000000 /dev/zero > grande.bin
    "$TNRX_CONNECT" snapshot >/dev/null 2>&1

    local tracked
    tracked=$(git --git-dir="$HOME/.local/share/tnrx-connect/user@srv_proj/shadow.git" ls-tree -r --name-only HEAD 2>&1)
    assert_contains "$tracked" "pequeno.txt" "arquivo pequeno entra no snapshot"
    assert_not_contains "$tracked" "grande.bin" "arquivo de 6MB fica de fora (limite 5MB)"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    cleanup_mount_env
}

test_mount_snapshot_requires_mount() {
    log_test "mount: sem montagem não tira snapshot nem restaura (evita gravar 'tudo apagado')"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    "$TNRX_CONNECT" umount >/dev/null 2>&1
    local out
    out=$("$TNRX_CONNECT" snapshot 2>&1)
    assert_contains "$out" "Não foi possível tirar o snapshot" "snapshot recusado sem mount"
    out=$("$TNRX_CONNECT" restore abc123 2>&1)
    assert_contains "$out" "não está montada" "restore recusado sem mount"
    out=$("$TNRX_CONNECT" refresh 2>&1)
    assert_contains "$out" "não está montada" "refresh recusado sem mount"

    cleanup_mount_env
}

test_mount_refresh_sends_hup() {
    log_test "mount: refresh manda SIGHUP ao rclone da montagem"
    setup_mount_env

    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    local out
    out=$("$TNRX_CONNECT" refresh 2>&1)
    sleep 0.5
    assert_contains "$out" "Cache de diretórios limpo" "refresh confirma"
    [[ -f "$FAKE_STATE/got_hup" ]] && pass_test "o processo do rclone recebeu SIGHUP" || fail_test "SIGHUP não chegou"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    cleanup_mount_env
}

run_jupyter_bg() {
    # $1 = stdin (formato printf %b), demais = argumentos. Sobe `tnrx-connect jupyter` em background.
    local input="$1"; shift
    printf '%b' "$input" | TNRX_JUPYTER_POLL_SECS=0.1 "$TNRX_CONNECT" jupyter "$@" > "$MT/jout" 2>&1 &
    JPID=$!
    local i
    for i in $(seq 1 60); do
        grep -q '^forward' "$FAKE_STATE/ssh.fwd" 2>/dev/null && grep -q 'Ctrl-C fecha' "$MT/jout" 2>/dev/null && return 0
        kill -0 "$JPID" 2>/dev/null || return 1
        sleep 0.1
    done
    return 1
}

stop_jupyter_bg() {
    kill -TERM "$JPID" 2>/dev/null
    wait "$JPID" 2>/dev/null
}

test_jupyter_tunnel_from_url() {
    log_test "jupyter: cola a URL do Jupyter e abre a ponte com o mesmo número de porta"
    setup_mount_env

    run_jupyter_bg 'user@srv\n' 'http://dl-02:48889/lab?token=abc' && pass_test "ponte aberta" || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    local out fwd
    out=$(cat "$MT/jout")
    fwd=$(cat "$FAKE_STATE/ssh.fwd" 2>/dev/null)
    assert_contains "$fwd" "forward localhost:48889:dl-02:48889" "encaminha localhost:48889 -> dl-02:48889"
    assert_contains "$out" "http://dl-02.srv.localhost:48889/lab?token=abc" "link com nó.host.localhost e o token"
    assert_contains "$out" "http://127.0.0.1:48889/lab?token=abc" "alternativa em 127.0.0.1"
    assert_not_contains "$out" "já estava em uso" "porta livre: sem aviso de mudança"

    stop_jupyter_bg
    fwd=$(cat "$FAKE_STATE/ssh.fwd" 2>/dev/null)
    assert_contains "$fwd" "cancel localhost:48889:dl-02:48889" "ao sair cancela a ponte"
    [[ ! -f "$HOME/.cache/tnrx-connect/ssh-$(printf '%s' user@srv | cksum | awk '{print $1}').sock" ]] \
        && pass_test "fecha a conexão mestra que ele mesmo abriu" || fail_test "conexão mestra ficou aberta"

    cleanup_mount_env
}

test_jupyter_local_port_busy_shifts() {
    log_test "jupyter: porta local ocupada -> usa a próxima livre e avisa"
    setup_mount_env

    FAKE_BUSY_PORTS="48889 48890" run_jupyter_bg 'user@srv\n' 'dl-02:48889' || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    local out fwd
    out=$(cat "$MT/jout"); fwd=$(cat "$FAKE_STATE/ssh.fwd" 2>/dev/null)
    assert_contains "$fwd" "forward localhost:48891:dl-02:48889" "local 48891 -> remoto 48889"
    assert_contains "$out" "já estava em uso; usando 48891" "avisa que mudou a porta local"
    assert_contains "$out" "http://dl-02.srv.localhost:48891/lab" "link usa a porta local"
    stop_jupyter_bg

    cleanup_mount_env
}

test_jupyter_input_formats() {
    log_test "jupyter: aceita 'nó porta', só o nó e URL com 127.0.0.1"
    setup_mount_env
    local fwd

    run_jupyter_bg 'user@srv\n' 'dl-02 48890' || fail_test "não abriu (nó porta)"
    stop_jupyter_bg
    fwd=$(cat "$FAKE_STATE/ssh.fwd" 2>/dev/null)
    assert_contains "$fwd" "forward localhost:48890:dl-02:48890" "'nó porta'"

    : > "$FAKE_STATE/ssh.fwd"
    run_jupyter_bg 'user@srv\n' 'dl-03' || fail_test "não abriu (só nó)"
    stop_jupyter_bg
    fwd=$(cat "$FAKE_STATE/ssh.fwd" 2>/dev/null)
    assert_contains "$fwd" ":dl-03:8888" "só o nó usa a porta remota 8888 (a local pode variar)"

    : > "$FAKE_STATE/ssh.fwd"
    run_jupyter_bg 'user@srv\ndl-04\n' 'http://127.0.0.1:48892/lab?token=t' || fail_test "não abriu (URL 127.0.0.1)" "$(cat "$MT/jout")"
    stop_jupyter_bg
    fwd=$(cat "$FAKE_STATE/ssh.fwd" 2>/dev/null)
    assert_contains "$fwd" "forward localhost:48892:dl-04:48892" "URL 127.0.0.1 pergunta o nó"

    cleanup_mount_env
}

test_jupyter_rejects_bad_input() {
    log_test "jupyter: rejeita nó/porta inválidos sem abrir ponte"
    setup_mount_env
    local out

    out=$(printf 'user@srv\n' | "$TNRX_CONNECT" jupyter 'http://a;rm:1/lab' 2>&1)
    assert_contains "$out" "Nome de nó inválido" "nó com caractere perigoso é rejeitado"
    out=$(printf 'user@srv\n' | "$TNRX_CONNECT" jupyter 'dl-02:99999' 2>&1)
    assert_contains "$out" "Porta inválida" "porta fora da faixa é rejeitada"
    [[ ! -s "$FAKE_STATE/ssh.fwd" ]] && pass_test "nenhuma ponte aberta" || fail_test "abriu ponte com entrada inválida"

    cleanup_mount_env
}

test_jupyter_keeps_master_it_did_not_open() {
    log_test "jupyter: não fecha a conexão mestra de uma sessão que já existia"
    setup_mount_env

    mkdir -p "$HOME/.cache/tnrx-connect"
    local sock="$HOME/.cache/tnrx-connect/ssh-$(printf '%s' user@srv | cksum | awk '{print $1}').sock"
    touch "$sock"
    run_jupyter_bg 'user@srv\n' 'dl-02:48889' || fail_test "não abriu" "$(cat "$MT/jout")"
    assert_contains "$(cat "$MT/jout")" "Reaproveitando conexão" "reaproveita a conexão existente"
    stop_jupyter_bg
    [[ -f "$sock" ]] && pass_test "conexão mestra preservada" || fail_test "fechou a conexão de outra sessão"

    cleanup_mount_env
}

test_jupyter_master_lost_ends_command() {
    log_test "jupyter: se a conexão mestra cair, o comando avisa e termina"
    setup_mount_env

    run_jupyter_bg 'user@srv\n' 'dl-02:48889' || fail_test "não abriu"
    rm -f "$HOME/.cache/tnrx-connect/ssh-$(printf '%s' user@srv | cksum | awk '{print $1}').sock"
    local i
    for i in $(seq 1 30); do kill -0 "$JPID" 2>/dev/null || break; sleep 0.2; done
    kill -0 "$JPID" 2>/dev/null && { fail_test "comando não terminou"; stop_jupyter_bg; } || pass_test "terminou sozinho"
    wait "$JPID" 2>/dev/null
    assert_contains "$(cat "$MT/jout")" "a ponte caiu" "avisa que a ponte caiu"

    cleanup_mount_env
}

wait_out() {
    # $1 = padrão em $MT/jout; espera até ~8s
    local i
    for i in $(seq 1 80); do
        grep -q -- "$1" "$MT/jout" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}

# --- descoberta automática: tnrx-connect jupyter (sem argumentos) ---

JT_LISTENERS=()

jt_listen() {
    # $1 = porta. Escuta em 0.0.0.0 por 20s (faz o papel do Jupyter no ar).
    python3 -c "
import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', $1)); s.listen(); time.sleep(20)" &
    JT_LISTENERS+=("$!")
    sleep 0.3
}

jt_cleanup() {
    local p
    for p in "${JT_LISTENERS[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
    JT_LISTENERS=()
}

jt_registry() {
    # $1 = pasta remota, $2 = job, $3 = nó, $4 = porta, $5 = token, $6 = início (epoch)
    mkdir -p "$1/.tnrx/jupyter"
    printf 'NODE=%s\nPORT=%s\nTOKEN=%s\nJOBID=%s\nSTARTED=%s\n' "$3" "$4" "$5" "$2" "$6" > "$1/.tnrx/jupyter/$2.env"
}

jt_conf() {
    # cria o .conf de uma sessão para a pasta atual: $1 = pasta remota
    mkdir -p "$HOME/.config/tnrx-connect"
    printf 'HOST=user@srv\nREMOTE_PATH=%q\nLOCAL_DIR=%q\nLAST_USED=1\n' "$1" "$(pwd -P)" > "$HOME/.config/tnrx-connect/user@srv_proj.conf"
}

jt_run() {
    # $1 = stdin (formato printf %b). Sobe `tnrx-connect jupyter` em background.
    printf '%b' "$1" | TNRX_JUPYTER_POLL_SECS=0.1 TNRX_JUPYTER_LIVE_SECS=1 TNRX_JUPYTER_START_POLL_SECS=0.2 "$TNRX_CONNECT" jupyter > "$MT/jout" 2>&1 &
    JPID=$!
}

test_jupyter_auto_single_server() {
    log_test "jupyter (auto): um servidor no ar -> lista e Enter conecta nele"
    setup_mount_env
    local remote="$MT/proj remoto"; jt_conf "$remote"
    jt_listen 48950
    jt_registry "$remote" 95272 127.0.0.1 48950 aabbccdd0011 "$(date +%s)"

    jt_run ''
    wait_out "Ponte aberta" && pass_test "ponte aberta só com Enter" || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    local out; out=$(cat "$MT/jout")
    assert_contains "$out" "Procurando servidores Jupyter no ar em user@srv" "usa o host da sessão"
    assert_contains "$out" "[1] proj remoto  127.0.0.1:48950" "lista com o nome do projeto"
    assert_contains "$out" "← este projeto" "marca o projeto atual"
    assert_contains "$out" "[n] Iniciar um novo Jupyter em proj remoto" "oferece iniciar um novo"
    assert_contains "$out" "não usa a senha fixa" "avisa que esse Jupyter não usa a senha fixa"
    assert_not_contains "$out" "Host (" "não pergunta o host"
    assert_contains "$out" "127.0.0.1:48950" "ponte para nó:porta do registro"
    assert_contains "$out" "?token=aabbccdd0011" "link com o token do registro"
    assert_contains "$out" "job 95272" "mostra o job"
    assert_contains "$(cat "$FAKE_STATE/ssh.fwd")" ":127.0.0.1:48950" "encaminhamento pedido"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null
    assert_contains "$(cat "$FAKE_STATE/ssh.fwd")" "cancel " "cancela a ponte ao sair"

    jt_cleanup; cleanup_mount_env
}

test_jupyter_auto_none() {
    log_test "jupyter (auto): nenhum servidor -> só avisa e sai"
    setup_mount_env
    local remote="$MT/proj"; mkdir -p "$remote"; jt_conf "$remote"

    local out rc
    out=$("$TNRX_CONNECT" jupyter < /dev/null 2>&1); rc=$?
    assert_contains "$out" "Nenhum servidor Jupyter no ar em user@srv" "avisa que não há servidor"
    assert_contains "$out" "Iniciar um novo Jupyter em proj" "oferece iniciar um novo"
    assert_contains "$out" "tnrx-connect jupyter" "sem resposta: diz como iniciar depois"
    [[ ! -f "$remote/.tnrx/jupyter/launch.log" ]] && pass_test "sem confirmação, não inicia nada" || fail_test "iniciou sem confirmação"
    assert_not_contains "$out" "URL" "não pede para colar URL"
    [[ "$rc" == "1" ]] && pass_test "sai com erro" || fail_test "exit=$rc"
    [[ ! -s "$FAKE_STATE/ssh.fwd" ]] && pass_test "nenhuma ponte aberta" || fail_test "abriu ponte sem servidor"
    [[ ! -f "$HOME/.cache/tnrx-connect/ssh-$(printf '%s' user@srv | cksum | awk '{print $1}').sock" ]] \
        && pass_test "fecha a conexão que abriu" || fail_test "conexão mestra ficou aberta"

    cleanup_mount_env
}

test_jupyter_auto_multiple_servers_menu() {
    log_test "jupyter (auto): vários servidores -> menu, mais recente primeiro"
    setup_mount_env
    local remote="$MT/proj"; jt_conf "$remote"
    local now; now=$(date +%s)
    jt_listen 48951; jt_listen 48953
    jt_registry "$remote" 11 127.0.0.1 48951 aa11 $((now - 7200))
    jt_registry "$remote" 22 127.0.0.1 48953 bb22 $((now - 60))

    jt_run '2\n'
    wait_out "Ponte aberta" || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    local out; out=$(cat "$MT/jout")
    assert_contains "$out" "[1] proj  127.0.0.1:48953  (job 22" "o mais recente é o [1]"
    assert_contains "$out" "[2] proj  127.0.0.1:48951  (job 11" "o mais antigo é o [2]"
    assert_contains "$out" "?token=aa11" "a opção 2 conecta no mais antigo"
    assert_contains "$(cat "$FAKE_STATE/ssh.fwd")" ":127.0.0.1:48951" "encaminha o escolhido"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    jt_cleanup; cleanup_mount_env
}

test_jupyter_auto_ignores_and_prunes_dead() {
    log_test "jupyter (auto): registros de servidores parados são ignorados; os velhos são apagados"
    setup_mount_env
    local remote="$MT/proj"; jt_conf "$remote"
    local now; now=$(date +%s)
    jt_listen 48955
    jt_registry "$remote" 1 127.0.0.1 48955 aa11 "$now"
    jt_registry "$remote" 2 127.0.0.1 48956 bb22 "$((now - 60))"
    jt_registry "$remote" 3 127.0.0.1 48957 cc33 "$((now - 200000))"

    jt_run ''
    wait_out "Ponte aberta" || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    local out; out=$(cat "$MT/jout")
    assert_contains "$out" "?token=aa11" "conecta no único que responde"
    assert_not_contains "$out" "[2]" "só um estava no ar"
    [[ -f "$remote/.tnrx/jupyter/2.env" ]] && pass_test "parado há pouco tempo: mantido" || fail_test "apagou registro recente"
    [[ ! -f "$remote/.tnrx/jupyter/3.env" ]] && pass_test "parado há mais de 1 dia: apagado" || fail_test "registro antigo ficou"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    jt_cleanup; cleanup_mount_env
}

test_jupyter_auto_ignores_stale_registry_on_same_port() {
    log_test "jupyter (auto): registro velho no mesmo nó:porta de um Jupyter novo é ignorado"
    setup_mount_env
    local remote="$MT/proj"; jt_conf "$remote"
    local now; now=$(date +%s)
    jt_listen 48966
    jt_registry "$remote" 100 127.0.0.1 48966 aa11 $((now - 3600))
    jt_registry "$remote" 101 127.0.0.1 48966 bb22 $((now - 60))

    jt_run ''
    wait_out "Ponte aberta" || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    local out; out=$(cat "$MT/jout")
    assert_contains "$out" "job 101" "lista o mais recente"
    assert_not_contains "$out" "job 100" "mesmo nó:porta: o registro mais antigo some (sem squeue)"
    assert_contains "$out" "?token=bb22" "conecta com a senha do registro certo"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    # Com squeue: só valem os jobs que ainda estão na fila
    jt_listen 48967
    jt_registry "$remote" 102 127.0.0.1 48967 cc33 $((now - 30))
    printf '101\n' > "$FAKE_STATE/squeue_ids"
    jt_run ''
    wait_out "Ponte aberta" || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    out=$(cat "$MT/jout")
    assert_not_contains "$out" "job 102" "job fora do squeue é ignorado, mesmo com a porta respondendo"
    assert_contains "$out" "job 101" "job no squeue continua"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    jt_cleanup; cleanup_mount_env
}

test_jupyter_auto_rejects_bad_registry_files() {
    log_test "jupyter (auto): registro com conteúdo suspeito é ignorado (nunca executado)"
    setup_mount_env
    local remote="$MT/proj"; jt_conf "$remote"
    jt_listen 48958
    local now; now=$(date +%s)
    jt_registry "$remote" 1 '127.0.0.1;touch_pwned' 48958 aa11 "$now"
    jt_registry "$remote" 2 127.0.0.1 48958 'aa11;touch_pwned' "$now"
    jt_registry "$remote" 3 127.0.0.1 'x48958' aa11 "$now"

    local out
    out=$("$TNRX_CONNECT" jupyter < /dev/null 2>&1)
    assert_contains "$out" "Nenhum servidor Jupyter no ar" "todos rejeitados"
    [[ ! -e "$remote/touch_pwned" && ! -e "$PWD/touch_pwned" ]] && pass_test "nada foi executado" || fail_test "conteúdo do registro foi executado"

    jt_cleanup; cleanup_mount_env
}

test_jupyter_auto_bridge_closes_when_server_ends() {
    log_test "jupyter (auto): quando o Jupyter para no servidor, a ponte fecha e o comando termina"
    setup_mount_env
    local remote="$MT/proj"; jt_conf "$remote"
    jt_listen 48960
    jt_registry "$remote" 7 127.0.0.1 48960 aa11 "$(date +%s)"

    jt_run ''
    wait_out "Ponte aberta" || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    jt_cleanup
    local i
    for i in $(seq 1 60); do kill -0 "$JPID" 2>/dev/null || break; sleep 0.2; done
    if kill -0 "$JPID" 2>/dev/null; then fail_test "comando não terminou"; kill -TERM "$JPID"; else pass_test "terminou sozinho"; fi
    wait "$JPID" 2>/dev/null
    assert_contains "$(cat "$MT/jout")" "terminou; a ponte foi fechada" "avisa"
    assert_contains "$(cat "$FAKE_STATE/ssh.fwd")" "cancel " "cancela a ponte"

    cleanup_mount_env
}

test_jupyter_auto_from_subfolder() {
    log_test "jupyter (auto): rodado numa subpasta da pasta montada usa a sessão dela"
    setup_mount_env
    local remote="$MT/proj"; jt_conf "$remote"
    mkdir -p sub/deep; cd sub/deep || exit 1
    jt_listen 48962
    jt_registry "$remote" 8 127.0.0.1 48962 aa11 "$(date +%s)"

    jt_run ''
    wait_out "Ponte aberta" && pass_test "achou a sessão da pasta acima" || fail_test "não achou" "$(cat "$MT/jout")"
    assert_not_contains "$(cat "$MT/jout")" "Host (" "sem perguntas"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    jt_cleanup; cleanup_mount_env
}

test_jupyter_auto_asks_when_no_session() {
    log_test "jupyter (auto): fora de uma pasta montada pergunta host e pasta"
    setup_mount_env
    local remote="$MT/proj remoto"; mkdir -p "$remote"
    jt_listen 48964
    jt_registry "$remote" 9 127.0.0.1 48964 aa11 "$(date +%s)"

    jt_run "user@srv\n$remote\n"
    wait_out "Ponte aberta" && pass_test "ponte aberta com host/pasta informados" || fail_test "não abriu" "$(cat "$MT/jout")"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    local out
    out=$(printf 'user@srv\nrelativa\n' | "$TNRX_CONNECT" jupyter 2>&1)
    assert_contains "$out" "caminho absoluto" "pasta relativa é recusada"

    jt_cleanup; cleanup_mount_env
}

jt_wait_cmd_end() {
    local i
    for i in $(seq 1 100); do kill -0 "$JPID" 2>/dev/null || return 0; sleep 0.1; done
    return 1
}

jt_stop_fake_tnrx() {
    pkill -TERM -f "$FAKES_DIR/tnrx" 2>/dev/null
    sleep 0.3
}

test_jupyter_lists_other_projects() {
    log_test "jupyter (auto): lista também os Jupyters de outros projetos deste host que o laptop conhece"
    setup_mount_env
    local remote="$MT/proj" outro="$MT/outro"; mkdir -p "$outro"; jt_conf "$remote"
    printf 'HOST=user@srv\nREMOTE_PATH=%q\nLOCAL_DIR=/x/outro\nLAST_USED=1\n' "$outro" > "$HOME/.config/tnrx-connect/user@srv_outro.conf"
    printf 'HOST=user@outro\nREMOTE_PATH=%q\nLOCAL_DIR=/x/y\nLAST_USED=1\n' "$MT/alheio" > "$HOME/.config/tnrx-connect/user@outro_y.conf"
    mkdir -p "$MT/alheio"
    local now; now=$(date +%s)
    jt_listen 48970; jt_listen 48971; jt_listen 48972
    jt_registry "$remote" 1 127.0.0.1 48970 aa11 $((now - 600))
    jt_registry "$outro" 2 127.0.0.1 48971 bb22 $((now - 30))
    jt_registry "$MT/alheio" 3 127.0.0.1 48972 cc33 "$now"

    jt_run '2\n'
    wait_out "Ponte aberta" || fail_test "ponte não abriu" "$(cat "$MT/jout")"
    local out; out=$(cat "$MT/jout")
    assert_contains "$out" "[1] outro  127.0.0.1:48971" "o outro projeto aparece (mais recente)"
    assert_contains "$out" "[2] proj  127.0.0.1:48970  (job 1, há 10 min)  ← este projeto" "o projeto atual aparece marcado"
    assert_not_contains "$out" "48972" "não lista projeto de outro host"
    assert_contains "$out" "?token=aa11" "conecta no escolhido"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    jt_cleanup; cleanup_mount_env
}

test_jupyter_start_new_with_fixed_url() {
    log_test "jupyter (auto): inicia um novo pelo laptop, com senha fixa e porta local fixa (URL estável pro VS Code)"
    setup_mount_env
    local remote="$MT/proj"; mkdir -p "$remote"; jt_conf "$remote"

    jt_run '\n'
    wait_out "Ponte aberta" && pass_test "iniciou e conectou" || fail_test "não conectou" "$(cat "$MT/jout")"
    local out; out=$(cat "$MT/jout")
    assert_contains "$out" "Iniciar um novo Jupyter em proj" "pergunta se inicia um novo"
    assert_contains "$out" "job na fila do Slurm" "mostra o progresso (fila)"
    assert_contains "$out" "Jupyter no ar" "avisa quando subiu"
    assert_contains "$out" "Esta URL é fixa" "explica que a URL é fixa"

    local token conf port
    token=$(cat "$remote/.tnrx/jupyter/token" 2>/dev/null)
    [[ "$token" =~ ^[0-9a-f]{48}$ ]] && pass_test "senha fixa gravada no servidor (48 hex)" || fail_test "token inválido" "$token"
    [[ "$(stat -c %a "$remote/.tnrx/jupyter/token" 2>/dev/null)" == "600" ]] && pass_test "arquivo da senha com permissão 600" || fail_test "permissão da senha"
    [[ "$(cat "$remote/.tnrx/.gitignore" 2>/dev/null)" == "*" ]] && pass_test ".tnrx/.gitignore criado" || fail_test "sem .tnrx/.gitignore"
    assert_contains "$out" "?token=$token" "o link usa a senha fixa"
    [[ "$(stat -c %a "$HOME/.config/tnrx-connect/jupyter.secret" 2>/dev/null)" == "600" ]] && pass_test "segredo local com permissão 600" || fail_test "segredo local"
    assert_not_contains "$(ps -Ao command=)" "$token" "a senha não aparece na linha de comando de nenhum processo local"
    conf="$HOME/.config/tnrx-connect/user@srv_proj.conf"
    port=$(sed -n 's/^JUPYTER_PORT=//p' "$conf")
    [[ -n "$port" ]] && pass_test "porta local fixa guardada no .conf ($port)" || fail_test "JUPYTER_PORT não gravado"
    assert_contains "$out" "http://127.0.0.1:$port/lab?token=$token" "URL do VS Code com porta e senha fixas"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    # Segunda vez (mesmo Jupyter): mesma porta, mesma senha
    jt_run '1\n'
    wait_out "Ponte aberta" || fail_test "não reconectou" "$(cat "$MT/jout")"
    assert_contains "$(cat "$MT/jout")" "http://127.0.0.1:$port/lab?token=$token" "reconectar dá a mesma URL"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    # Outro Jupyter do mesmo projeto, iniciado depois: mesma senha
    jt_stop_fake_tnrx
    rm -f "$remote/.tnrx/jupyter/777.env"
    FAKE_TNRX_PORT=48991 jt_run '\n'
    wait_out "Ponte aberta" || fail_test "não iniciou de novo" "$(cat "$MT/jout")"
    assert_contains "$(cat "$MT/jout")" "http://127.0.0.1:$port/lab?token=$token" "novo Jupyter, mesma URL (mesma porta local e senha)"
    assert_contains "$(cat "$FAKE_STATE/ssh.fwd")" "forward localhost:$port:127.0.0.1:48991" "a porta fixa aponta pro Jupyter novo"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null

    jt_stop_fake_tnrx; cleanup_mount_env
}

test_jupyter_token_depends_on_local_secret() {
    log_test "jupyter: a senha fixa depende do projeto, do host e do segredo deste laptop"
    setup_mount_env
    local a b c d
    a=$(bash -c "source <(sed '/^# --- Lógica de Entrada ---/,\$d' '$TNRX_CONNECT'); jupyter_token user@srv /p/a")
    b=$(bash -c "source <(sed '/^# --- Lógica de Entrada ---/,\$d' '$TNRX_CONNECT'); jupyter_token user@srv /p/a")
    c=$(bash -c "source <(sed '/^# --- Lógica de Entrada ---/,\$d' '$TNRX_CONNECT'); jupyter_token user@srv /p/b")
    rm -f "$HOME/.config/tnrx-connect/jupyter.secret"
    d=$(bash -c "source <(sed '/^# --- Lógica de Entrada ---/,\$d' '$TNRX_CONNECT'); jupyter_token user@srv /p/a")
    [[ "$a" =~ ^[0-9a-f]{48}$ && "$a" == "$b" ]] && pass_test "estável para o mesmo projeto" || fail_test "instável" "$a / $b"
    [[ "$a" != "$c" ]] && pass_test "muda com o projeto" || fail_test "igual entre projetos"
    [[ "$a" != "$d" ]] && pass_test "muda com o segredo local (não dá pra deduzir só pelo nome)" || fail_test "não depende do segredo"
    cleanup_mount_env
}

test_jupyter_start_failure_shows_log() {
    log_test "jupyter (auto): se o tnrx falha ao iniciar, mostra o fim do log"
    setup_mount_env
    local remote="$MT/proj"; mkdir -p "$remote"; jt_conf "$remote"

    local out rc
    out=$(printf '\n' | FAKE_TNRX_FAIL=1 TNRX_JUPYTER_START_POLL_SECS=0.2 "$TNRX_CONNECT" jupyter 2>&1); rc=$?
    assert_contains "$out" "O tnrx terminou sem subir o Jupyter" "explica a falha"
    assert_contains "$out" "Nenhum arquivo .sif encontrado" "mostra o log do tnrx"
    [[ "$rc" == "1" ]] && pass_test "sai com erro" || fail_test "exit=$rc"

    cleanup_mount_env
}

test_jupyter_start_cancel_while_waiting() {
    log_test "jupyter (auto): interromper enquanto espera o Jupyter subir cancela o job"
    setup_mount_env
    local remote="$MT/proj"; mkdir -p "$remote"; jt_conf "$remote"

    FAKE_TNRX_DELAY=30 jt_run '\n'
    wait_out "Iniciando o Jupyter" || fail_test "não iniciou" "$(cat "$MT/jout")"
    sleep 0.5
    kill -TERM "$JPID"
    jt_wait_cmd_end && pass_test "o comando terminou" || fail_test "comando não terminou"
    wait "$JPID" 2>/dev/null
    assert_contains "$(cat "$MT/jout")" "Cancelando o Jupyter" "avisa o cancelamento"
    local i
    for i in $(seq 1 20); do [[ -f "$FAKE_STATE/tnrx_cancelled" ]] && break; sleep 0.1; done
    [[ -f "$FAKE_STATE/tnrx_cancelled" ]] && pass_test "o tnrx (e o srun) no servidor recebeu o cancelamento" || fail_test "o job continuou"
    [[ -z "$(pgrep -f "$FAKES_DIR/tnrx")" ]] && pass_test "nada ficou rodando no servidor" || fail_test "sobrou processo"

    jt_stop_fake_tnrx; cleanup_mount_env
}

# --- Interface JSON (VS Code) ---

jq_py() {
    # $1 = JSON, $2 = expressão python sobre `d` (o JSON carregado). Imprime o resultado.
    printf '%s' "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print($2)" 2>&1
}

assert_json() {
    # $1 = JSON, $2 = expressão python, $3 = valor esperado (texto), $4 = nome
    local got
    got=$(jq_py "$1" "$2")
    [[ "$got" == "$3" ]] && pass_test "$4" || fail_test "$4" "esperado '$3', veio '$got'"
}

test_api_status_json() {
    log_test "api: status --json lista montagens, estado, conexão e tnrx_slurm.conf efetivo"
    setup_mount_env
    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1
    printf '# comentário\nPARTITION=a100\nGPUS="2"  # duas\nexport TIME=04:00:00\n' > tnrx_slurm.conf
    # mesma pasta local, configurada também pra outro host: não está montada por esta config
    printf 'HOST=user@b\nREMOTE_PATH=/b/proj\nLOCAL_DIR=%s\nLAST_USED=1\n' "$(pwd -P)" > "$HOME/.config/tnrx-connect/user@b_proj.conf"
    mkdir -p "$MT/work/velho"
    printf 'HOST=user@outro\nREMOTE_PATH=/x/velho\nLOCAL_DIR=%s\nLAST_USED=5\n' "$MT/work/velho" > "$HOME/.config/tnrx-connect/user@outro_velho.conf"

    local out
    out=$("$TNRX_CONNECT" status --json 2>/dev/null </dev/null)
    jq_py "$out" "'ok'" | grep -q '^ok$' && pass_test "JSON válido" || fail_test "JSON inválido" "$out"
    local M="[m for m in d['mounts'] if m['name']=='proj' and m['host']=='user@srv'][0]"
    assert_json "$out" "$M['state']" "mounted" "pasta montada: state=mounted"
    assert_json "$out" "$M['connected']" "True" "conexão ativa"
    assert_json "$out" "$M['remote_path']" "/data/proj" "pasta remota"
    assert_json "$out" "isinstance($M['rclone_pid'], int)" "True" "PID do rclone"
    assert_json "$out" "$M['slurm']['values']['PARTITION']" "{'value': 'a100', 'from_file': True}" "PARTITION do arquivo"
    assert_json "$out" "$M['slurm']['values']['GPUS']['value']" "2" "aspas e comentário removidos"
    assert_json "$out" "$M['slurm']['values']['TIME']['value']" "04:00:00" "aceita 'export'"
    assert_json "$out" "$M['slurm']['values']['MEM']" "{'value': '4G', 'from_file': False}" "chave ausente: padrão do tnrx"
    assert_json "$out" "[(m['state'], m['slurm']) for m in d['mounts'] if m['name']=='velho'][0]" "('unmounted', None)" "pasta desmontada: sem slurm"
    assert_json "$out" "sorted((m['host'], m['state']) for m in d['mounts'] if m['name']=='proj')" "[('user@b', 'unmounted'), ('user@srv', 'mounted')]" "mesma pasta com outro host: só a config do lock conta como montada"
    assert_json "$out" "sorted((h['host'], h['connected']) for h in d['hosts'])" "[('user@b', False), ('user@outro', False), ('user@srv', True)]" "hosts com o estado da conexão"

    kill -9 "$(rclone_pid)"; sleep 0.3
    out=$("$TNRX_CONNECT" status --json 2>/dev/null)
    assert_json "$out" "[m['state'] for m in d['mounts'] if m['name']=='proj' and m['host']=='user@srv'][0]" "stale" "rclone morto: state=stale"
    "$TNRX_CONNECT" umount -f >/dev/null 2>&1
    cleanup_mount_env
}

test_api_slurm_defaults_match_tnrx() {
    log_test "api: padrões do Slurm no tnrx-connect iguais aos do tnrx"
    local k a b ok=true
    for k in PARTITION GPUS CPUS MEM TIME; do
        a=$(sed -n "s/^DEFAULT_$k=\"\\(.*\\)\"/\\1/p" "$SCRIPT_DIR/tnrx")
        b=$(sed -n "s/^SLURM_DEFAULT_$k=\"\\(.*\\)\"/\\1/p" "$TNRX_CONNECT")
        [[ -n "$a" && "$a" == "$b" ]] || { ok=false; fail_test "padrão $k difere" "tnrx='$a' tnrx-connect='$b'"; }
    done
    [[ "$ok" == "true" ]] && pass_test "PARTITION, GPUS, CPUS, MEM e TIME iguais"
}

test_api_cluster_json() {
    log_test "api: cluster --json traz partições (nós e GPUs livres) e meus jobs dos hosts montados"
    setup_mount_env
    printf 'user@srv\n/data/proj\n' | "$TNRX_CONNECT" mount >/dev/null 2>&1

    # a mesma pasta local também configurada pra outro host (não montado): não entra
    printf 'HOST=user@b\nREMOTE_PATH=/b/proj\nLOCAL_DIR=%s\nLAST_USED=1\n' "$(pwd -P)" > "$HOME/.config/tnrx-connect/user@b_proj.conf"
    local out
    out=$("$TNRX_CONNECT" cluster --json 2>/dev/null </dev/null)
    assert_json "$out" "[h['host'] for h in d['hosts']]" "['user@srv']" "só os hosts montados (não o outro .conf da mesma pasta)"
    assert_json "$out" "d['hosts'][0]['ok']" "True" "consulta ok"
    assert_json "$out" "[(p['name'], p['default']) for p in d['hosts'][0]['partitions']]" "[('l40s', True), ('a100', False)]" "partições, com a padrão marcada"
    assert_json "$out" "d['hosts'][0]['partitions'][1]['nodes']['total']" "2" "linhas do sinfo da mesma partição somadas (sem repetir partição)"
    assert_json "$out" "d['hosts'][0]['partitions'][0]['nodes']" "{'allocated': 2, 'idle': 1, 'other': 1, 'total': 4}" "nós A/I/O/T"
    assert_json "$out" "d['hosts'][0]['partitions'][0]['gpus']" "{'total': 8, 'used': 3, 'unavailable': 2, 'free': 3}" "GPUs l40s (nó em drain não conta como livre)"
    assert_json "$out" "d['hosts'][0]['partitions'][1]['gpus']['free']" "0" "a100 fora do ar: 0 livres"
    assert_json "$out" "[(j['id'], j['state'], j['work_dir']) for j in d['hosts'][0]['jobs']]" "[('95272', 'RUNNING', '/data/proj'), ('95300', 'PENDING', '/data/outro proj')]" "meus jobs, com a pasta"
    assert_json "$out" "d['hosts'][0]['jobs'][1]['name']" 'train "x"' "nome com aspas escapado no JSON"

    out=$("$TNRX_CONNECT" cluster 2>&1 </dev/null)
    assert_contains "$out" "GPUs livres" "versão de terminal"
    assert_contains "$out" "95300" "lista os jobs no terminal"

    "$TNRX_CONNECT" umount >/dev/null 2>&1
    out=$("$TNRX_CONNECT" cluster --json --host user@srv 2>/dev/null </dev/null)
    assert_json "$out" "(d['hosts'][0]['connected'], d['hosts'][0]['error']['code'])" "(False, 'not_connected')" "sem conexão: not_connected, sem autenticar"
    [[ ! -f "$(ctrl_sock)" ]] && pass_test "não abriu conexão (não pede 2FA)" || fail_test "abriu conexão"
    cleanup_mount_env
}

test_api_cluster_cancel() {
    log_test "api: cluster cancel / jupyter stop cancelam um job (scancel) sem perguntar nada"
    setup_mount_env
    mkdir -p "$HOME/.cache/tnrx-connect"; touch "$(ctrl_sock)"
    local out rc
    out=$("$TNRX_CONNECT" cluster cancel 95272 --host user@srv --json 2>/dev/null </dev/null); rc=$?
    assert_json "$out" "(d['ok'], d['job'])" "(True, '95272')" "cancelado"
    assert_contains "$(cat "$FAKE_STATE/scancel")" "95272" "scancel chamado no servidor"
    out=$("$TNRX_CONNECT" jupyter stop 95273 --host user@srv --json 2>/dev/null </dev/null)
    assert_json "$out" "d['ok']" "True" "jupyter stop também"
    out=$("$TNRX_CONNECT" cluster cancel 999 --host user@srv --json 2>/dev/null </dev/null); rc=$?
    assert_json "$out" "d['error']['code']" "scancel_failed" "erro do scancel vira scancel_failed"
    out=$("$TNRX_CONNECT" cluster cancel '1;rm -rf x' --host user@srv --json 2>/dev/null </dev/null); rc=$?
    assert_json "$out" "d['error']['code']" "usage" "job inválido recusado"
    [[ "$rc" == "2" ]] && pass_test "uso inválido sai com 2" || fail_test "exit=$rc"
    cleanup_mount_env
}

test_api_jupyter_list_json() {
    log_test "api: jupyter list --json agrupa por host e projeto, com URL local fixa"
    setup_mount_env
    local remote="$MT/proj remoto" outro="$MT/outro"; mkdir -p "$remote" "$outro"; jt_conf "$remote"
    printf 'HOST=user@srv\nREMOTE_PATH=%q\nLOCAL_DIR=/x/outro\nLAST_USED=1\nJUPYTER_PORT=18555\n' "$outro" > "$HOME/.config/tnrx-connect/user@srv_outro.conf"
    printf 'HOST=user@off\nREMOTE_PATH=/y\nLOCAL_DIR=/x/y\nLAST_USED=1\n' > "$HOME/.config/tnrx-connect/user@off_y.conf"
    mkdir -p "$HOME/.cache/tnrx-connect"; touch "$(ctrl_sock)"
    jt_listen 48980
    jt_registry "$outro" 41 127.0.0.1 48980 aa11 "$(date +%s)"

    local out
    out=$("$TNRX_CONNECT" jupyter list --json 2>/dev/null </dev/null)
    assert_json "$out" "sorted((h['host'], h['connected']) for h in d['hosts'])" "[('user@off', False), ('user@srv', True)]" "hosts com conexão"
    assert_json "$out" "sorted(p['name'] for h in d['hosts'] if h['host']=='user@srv' for p in h['projects'])" "['outro', 'proj remoto']" "projetos conhecidos do host (inclusive com espaço)"
    assert_json "$out" "[len(p['servers']) for h in d['hosts'] for p in h['projects'] if p['name']=='proj remoto'][0]" "0" "projeto sem Jupyter: lista vazia"
    assert_json "$out" "[(s['job'], s['node'], s['port'], s['local_port'], s['bridge_open'], s['token_fixed']) for h in d['hosts'] for p in h['projects'] if p['name']=='outro' for s in p['servers']][0]" "('41', '127.0.0.1', 48980, 18555, False, False)" "servidor com porta local fixa do projeto"
    assert_json "$out" "[s['url'] for h in d['hosts'] for p in h['projects'] if p['name']=='outro' for s in p['servers']][0]" "http://127.0.0.1:18555/lab?token=aa11" "URL local"
    jt_cleanup; cleanup_mount_env
}

test_api_jupyter_start_connect_json() {
    log_test "api: jupyter start/connect --json emitem eventos; connect mantém a ponte até ser encerrado"
    setup_mount_env
    local remote="$MT/proj"; mkdir -p "$remote"; jt_conf "$remote"
    mkdir -p "$HOME/.cache/tnrx-connect"; touch "$(ctrl_sock)"

    local out
    out=$(TNRX_JUPYTER_START_POLL_SECS=0.2 "$TNRX_CONNECT" jupyter start --host user@srv --project "$remote" --json 2>/dev/null </dev/null)
    local events
    events=$(printf '%s\n' "$out" | python3 -c "import json,sys; print([json.loads(l)['event'] for l in sys.stdin if l.strip()])" 2>&1)
    assert_contains "$events" "'launching'" "evento launching"
    assert_contains "$events" "'waiting'" "evento waiting"
    assert_contains "$events" "'ready']" "termina com ready"
    local ready token
    ready=$(printf '%s\n' "$out" | tail -1)
    token=$(cat "$remote/.tnrx/jupyter/token")
    assert_json "$ready" "(d['server']['job'], d['server']['token'] == '$token', d['server']['token_fixed'])" "('777', True, True)" "ready traz o servidor com a senha fixa"
    assert_contains "$(printf '%s\n' "$out" | grep waiting | head -1)" '"phase":"queued"' "fase da fila"

    TNRX_JUPYTER_POLL_SECS=0.1 TNRX_JUPYTER_LIVE_SECS=1 "$TNRX_CONNECT" jupyter connect --host user@srv --project "$remote" --json > "$MT/jout" 2>/dev/null </dev/null &
    JPID=$!
    wait_out '"event":"bridge"' && pass_test "evento bridge" || fail_test "sem evento bridge" "$(cat "$MT/jout")"
    local bridge port
    bridge=$(head -1 "$MT/jout")
    port=$(sed -n 's/^JUPYTER_PORT=//p' "$HOME/.config/tnrx-connect/user@srv_proj.conf")
    assert_json "$bridge" "(d['fixed_port'], d['server']['local_port'], d['server']['bridge_open'])" "(True, $port, True)" "ponte na porta fixa (gravada no .conf)"
    out=$("$TNRX_CONNECT" jupyter list --json 2>/dev/null </dev/null)
    assert_json "$out" "[s['bridge_open'] for h in d['hosts'] for p in h['projects'] for s in p['servers']][0]" "True" "list mostra a ponte aberta"
    kill -TERM "$JPID"; wait "$JPID" 2>/dev/null
    assert_contains "$(tail -1 "$MT/jout")" '"event":"closed","reason":"signal"' "encerrada: evento closed (signal)"
    assert_contains "$(cat "$FAKE_STATE/ssh.fwd")" "cancel " "cancela o encaminhamento"

    # a ponte fecha sozinha quando o Jupyter é encerrado (jupyter stop)
    TNRX_JUPYTER_POLL_SECS=0.1 TNRX_JUPYTER_LIVE_SECS=1 "$TNRX_CONNECT" jupyter connect --host user@srv --project "$remote" --job 777 --json > "$MT/jout" 2>/dev/null </dev/null &
    JPID=$!
    wait_out '"event":"bridge"' || fail_test "sem ponte" "$(cat "$MT/jout")"
    "$TNRX_CONNECT" jupyter stop 777 --host user@srv --json >/dev/null 2>&1 </dev/null
    jt_wait_cmd_end || { kill -TERM "$JPID"; sleep 3; }
    jt_wait_cmd_end && pass_test "ponte terminou com o Jupyter" || { fail_test "ponte não terminou"; kill -TERM "$JPID"; }
    wait "$JPID" 2>/dev/null
    assert_contains "$(tail -1 "$MT/jout")" '"reason":"server_stopped"' "evento closed (server_stopped)"

    out=$("$TNRX_CONNECT" jupyter connect --host user@srv --project "$remote" --json 2>/dev/null </dev/null)
    assert_json "$out" "(d['event'], d['code'])" "('error', 'no_server')" "sem Jupyter: erro no_server"
    jt_stop_fake_tnrx; cleanup_mount_env
}

test_api_never_authenticates() {
    log_test "api: sem conexão, os comandos --json falham com not_connected e nunca pedem senha/2FA"
    setup_mount_env
    local remote="$MT/proj"; mkdir -p "$remote"; jt_conf "$remote"
    local out rc
    out=$("$TNRX_CONNECT" jupyter start --host user@srv --project "$remote" --json 2>/dev/null </dev/null); rc=$?
    assert_json "$out" "(d['event'], d['code'])" "('error', 'not_connected')" "start: not_connected"
    [[ "$rc" == "3" ]] && pass_test "sai com 3 (sem conexão)" || fail_test "exit=$rc"
    out=$("$TNRX_CONNECT" cluster cancel 1 --host user@srv --json 2>/dev/null </dev/null)
    assert_json "$out" "d['error']['code']" "not_connected" "cancel: not_connected"
    out=$("$TNRX_CONNECT" jupyter list --json 2>/dev/null </dev/null)
    assert_json "$out" "d['hosts'][0]['connected']" "False" "list: host sem conexão"
    [[ ! -f "$(ctrl_sock)" ]] && pass_test "nenhuma conexão aberta" || fail_test "abriu conexão"
    [[ ! -e "$remote/.tnrx/jupyter/launch.log" ]] && pass_test "nada iniciado no servidor" || fail_test "iniciou algo"
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
    test_mount_command_returns_prompt
    test_mount_is_idempotent
    test_mount_second_run_uses_saved_defaults
    test_mount_refuses_non_empty_folder
    test_mount_rejects_relative_remote_path
    test_mount_refuses_home_dir
    test_mount_failure_cleans_up
    test_ssh_requires_mount
    test_ssh_from_subfolder_and_master_lost
    test_mount_recovers_after_rclone_crash
    test_mount_recovers_while_busy
    test_mount_busy_unmount_keeps_state
    test_umount_from_subfolder
    test_umount_keeps_master_used_elsewhere
    test_mount_conf_name_collision
    test_mount_multiple_confs_same_folder
    test_mount_snapshot_history_restore
    test_mount_auto_snapshots_without_terminal
    test_mount_snapshot_skips_big_files
    test_mount_snapshot_requires_mount
    test_mount_refresh_sends_hup
    test_jupyter_tunnel_from_url
    test_jupyter_local_port_busy_shifts
    test_jupyter_input_formats
    test_jupyter_rejects_bad_input
    test_jupyter_keeps_master_it_did_not_open
    test_jupyter_master_lost_ends_command
    test_jupyter_auto_single_server
    test_jupyter_auto_none
    test_jupyter_auto_multiple_servers_menu
    test_jupyter_auto_ignores_and_prunes_dead
    test_jupyter_auto_ignores_stale_registry_on_same_port
    test_jupyter_auto_rejects_bad_registry_files
    test_jupyter_auto_bridge_closes_when_server_ends
    test_jupyter_auto_from_subfolder
    test_jupyter_auto_asks_when_no_session
    test_jupyter_lists_other_projects
    test_jupyter_start_new_with_fixed_url
    test_jupyter_token_depends_on_local_secret
    test_jupyter_start_failure_shows_log
    test_jupyter_start_cancel_while_waiting
    test_api_status_json
    test_api_slurm_defaults_match_tnrx
    test_api_cluster_json
    test_api_cluster_cancel
    test_api_jupyter_list_json
    test_api_jupyter_start_connect_json
    test_api_never_authenticates
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
