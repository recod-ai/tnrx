#!/bin/bash
#
# Instalador do tnrx e do tnrx-connect.
#
#   curl -fsSL https://raw.githubusercontent.com/recod-ai/tnrx/main/install.sh | bash
#
# Os arquivos ficam numa pasta só da instalação (~/.local/share/tnrx, ou
# $TNRX_HOME), e ~/.local/bin ganha links para os comandos dentro dela. A pasta
# nunca muda de lugar, então os links não quebram; o que muda a cada
# atualização é o conteúdo dela, trocado de uma vez.
#
# Uso (os comandos `update`, `update-dev` e `uninstall` do tnrx e do
# tnrx-connect chamam este script):
#   install.sh                    clona o repositório e instala (o mesmo que --update)
#   install.sh --from <pasta>     instala a partir de uma cópia local do repositório,
#                                 inclusive mudanças ainda não commitadas (update-dev)
#   install.sh --uninstall        remove os links e a pasta da instalação
#   --choose                      (com qualquer um dos dois primeiros) pergunta de
#                                 novo o que instalar
#
# Componentes: tnrx, download_huggingface, tnrx-connect e vscode (a extensão).
# A primeira instalação pergunta cada um; as atualizações repetem a escolha
# gravada em VERSION.
#
# Variáveis: TNRX_REPO (repositório git), TNRX_BRANCH, TNRX_HOME (pasta da
# instalação), TNRX_COMPONENTS (lista de componentes, sem perguntar),
# TNRX_SKIP_SETUP=1 (não roda o `tnrx install` no servidor),
# TNRX_SKIP_VSCODE=1 (nunca instala a extensão do VS Code).

set -e

INSTALL_DIR="${TNRX_HOME:-$HOME/.local/share/tnrx}"
# O repositório da última instalação fica em VERSION, então quem instalou de
# outro endereço (ex.: por SSH, se o repositório for privado) não precisa
# repetir o TNRX_REPO a cada update.
REPO="${TNRX_REPO:-$(sed -n 's/^REPO=//p' "$INSTALL_DIR/VERSION" 2>/dev/null || true)}"
REPO="${REPO:-https://github.com/recod-ai/tnrx.git}"
BRANCH="${TNRX_BRANCH:-main}"
BIN_DIR="$HOME/.local/bin"
COMMANDS=(tnrx tnrx-connect download_huggingface)
VSCODE_EXT_ID="tnrx.tnrx"
CHOOSE=false
SELECTED=""     # componentes escolhidos, separados por espaço

die() { echo "❌ $*" >&2; exit 1; }

version_field() { sed -n "s/^$1=//p" "$INSTALL_DIR/VERSION" 2>/dev/null || true; }

copy_tree() {
    # Copia de $1 para $2 os arquivos do repositório: os versionados e os novos
    # que o .gitignore não exclui. Assim .venv, *.sif e configs pessoais ficam de fora.
    local src="$1" dst="$2"
    mkdir -p "$dst"
    (cd "$src" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - --) | tar -xf - -C "$dst"
}

has() { [[ " $SELECTED " == *" $1 "* ]]; }

can_ask() {
    # Com `curl | bash` a entrada do script é o pipe, então as perguntas vão
    # para o terminal (/dev/tty). TNRX_INTERACTIVE=1 lê da entrada (testes).
    [ "$TNRX_INTERACTIVE" == "1" ] || (exec </dev/tty) 2>/dev/null
}

ask_yn() {
    # ask_yn <pergunta> <s|n: resposta padrão>; sucesso se a resposta for sim.
    local hint resp
    if [ "$2" == "s" ]; then hint="S/n"; else hint="s/N"; fi
    printf '  %s [%s]: ' "$1" "$hint" >&2
    if [ "$TNRX_INTERACTIVE" == "1" ]; then
        read -r resp || resp=""
    else
        read -r resp </dev/tty || resp=""
    fi
    resp="${resp:-$2}"
    [[ "$resp" =~ ^[sSyY] ]]
}

has_code() { [ "$TNRX_SKIP_VSCODE" != "1" ] && command -v code >/dev/null 2>&1; }

choose_components() {
    # Define SELECTED: TNRX_COMPONENTS, senão a escolha da instalação anterior
    # (a não ser com --choose), senão pergunta. Sem terminal, usa o padrão da máquina.
    local src="$1" server=false saved def_tnrx def_connect
    is_server "$src" && server=true
    saved=$(version_field COMPONENTS)
    if [ -n "$TNRX_COMPONENTS" ]; then
        SELECTED="${TNRX_COMPONENTS//,/ }"
        return 0
    fi
    if [ -n "$saved" ] && [ "$CHOOSE" != "true" ]; then
        SELECTED="$saved"
        return 0
    fi
    if $server; then def_tnrx=s; def_connect=n; else def_tnrx=n; def_connect=s; fi
    if ! can_ask; then
        if $server; then SELECTED="tnrx download_huggingface"; else SELECTED="tnrx-connect"; fi
        has tnrx-connect && has_code && SELECTED="$SELECTED vscode"
        echo "ℹ️  Sem terminal para perguntar: instalando o padrão desta máquina ($SELECTED)."
        echo "   Para escolher: TNRX_COMPONENTS=\"...\" ou --choose num terminal."
        return 0
    fi
    if $server; then
        echo "O que instalar nesta máquina? (servidor $(hostname))"
    else
        echo "O que instalar nesta máquina? ($(hostname) não está em tnrx_hosts.conf: parece um laptop)"
    fi
    SELECTED=""
    ask_yn "tnrx: roda os projetos no cluster (servidor)" "$def_tnrx" && SELECTED="$SELECTED tnrx"
    if has tnrx; then
        ask_yn "download_huggingface: baixa modelos e datasets com 'tnrx hf'" s && SELECTED="$SELECTED download_huggingface"
    fi
    ask_yn "tnrx-connect: trabalha no projeto do servidor a partir do laptop" "$def_connect" && SELECTED="$SELECTED tnrx-connect"
    if has tnrx-connect && has_code; then
        ask_yn "Extensão do VS Code: barra lateral do tnrx-connect" s && SELECTED="$SELECTED vscode"
    fi
    SELECTED="${SELECTED# }"
    [ -n "$SELECTED" ] || die "Nada escolhido: nada foi instalado."
}

write_version() {
    # VERSION: de que commit e de onde veio a instalação (lido por `tnrx --version`),
    # e o que foi escolhido (repetido pelas atualizações).
    local src="$1" dst="$2" origin="$3" commit date dirty=""
    commit=$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo "?")
    date=$(git -C "$src" log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || echo "?")
    if [ "$origin" != "$REPO" ] && [ -n "$(git -C "$src" status --porcelain 2>/dev/null)" ]; then
        dirty=" (com mudanças não commitadas)"
    fi
    {
        echo "COMMIT=$commit"
        echo "DATE=$date"
        echo "SOURCE=$origin$dirty"
        echo "REPO=$REPO"
        echo "COMPONENTS=$SELECTED"
        echo "INSTALLED=$(date '+%Y-%m-%d %H:%M')"
    } > "$dst/VERSION"
}

swap_in() {
    # Troca a pasta da instalação pela nova de uma vez (mv). Processos que já
    # estão rodando, como o loop de snapshots de uma montagem, continuam lendo a
    # versão antiga até terminar; copiar por cima corromperia o script deles.
    local new="$1" old="$INSTALL_DIR.old.$$"
    if [ -e "$INSTALL_DIR" ]; then
        mv "$INSTALL_DIR" "$old"
    fi
    mkdir -p "$(dirname "$INSTALL_DIR")"
    mv "$new" "$INSTALL_DIR"
    rm -rf "$old"
}

link_commands() {
    # Liga os comandos escolhidos e tira os que deixaram de ser escolhidos (só
    # os que apontam para esta instalação).
    local cmd linked=()
    mkdir -p "$BIN_DIR"
    for cmd in "${COMMANDS[@]}"; do
        if has "$cmd"; then
            ln -sfn "$INSTALL_DIR/$cmd" "$BIN_DIR/$cmd"
            linked+=("$cmd")
        elif [ -L "$BIN_DIR/$cmd" ] && [[ "$(readlink "$BIN_DIR/$cmd")" == "$INSTALL_DIR/"* ]]; then
            rm -f "$BIN_DIR/$cmd"
            echo "🗑️  Removido (não escolhido): $BIN_DIR/$cmd"
        fi
    done
    [ ${#linked[@]} -gt 0 ] && echo "🔗 Comandos em $BIN_DIR: ${linked[*]}"
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) echo "⚠️  $BIN_DIR não está no PATH. Acrescente ao ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
}

is_server() {
    # Um servidor é uma máquina listada no tnrx_hosts.conf da pasta $1.
    local h
    h=$(hostname)
    grep -vE '^[[:space:]]*(#|$)' "$1/tnrx_hosts.conf" | cut -d'|' -f1 | grep -qxF "$h"
}

setup_server() {
    [ "$TNRX_SKIP_SETUP" == "1" ] && return 0
    echo "🖥️  Servidor reconhecido ($(hostname)): preparando o uv e a imagem padrão..."
    if ! "$INSTALL_DIR/tnrx" install </dev/null; then
        echo "⚠️  A preparação do servidor falhou (veja acima). Rode 'tnrx install' de novo depois de resolver." >&2
    fi
}

uninstall_vscode() {
    has_code || return 0
    code --uninstall-extension "$VSCODE_EXT_ID" >/dev/null 2>&1 && echo "🗑️  Extensão do VS Code removida."
    return 0
}

setup_vscode() {
    # Instala (ou atualiza) a extensão do VS Code.
    has_code || { echo "ℹ️  Extensão do VS Code não instalada: comando 'code' não encontrado."; return 0; }
    command -v python3 >/dev/null 2>&1 || { echo "ℹ️  Extensão do VS Code não instalada: falta python3."; return 0; }
    local vsix
    if vsix=$(cd "$INSTALL_DIR/vscode" && python3 build-vsix.py 2>&1 | grep -o 'dist/[^ ]*\.vsix' | tail -1) && [ -n "$vsix" ] &&
        code --install-extension "$INSTALL_DIR/vscode/$vsix" --force >/dev/null 2>&1; then
        echo "🧩 Extensão do VS Code instalada (recarregue a janela: Developer: Reload Window)."
    else
        echo "⚠️  Não consegui instalar a extensão do VS Code. Veja vscode/README.md em $INSTALL_DIR." >&2
    fi
}

install_from() {
    # Instala a partir da pasta $1 (um clone novo ou a cópia de desenvolvimento).
    local src="$1" origin="$2" before before_source new now f
    for f in tnrx tnrx-connect install.sh tnrx_hosts.conf; do
        [ -f "$src/$f" ] || die "$src não parece o repositório do tnrx (falta $f)."
    done
    before=$(version_field COMMIT)
    before_source=$(version_field SOURCE)
    local before_components
    before_components=$(version_field COMPONENTS)
    choose_components "$src"
    new="$INSTALL_DIR.new.$$"
    rm -rf "$new"
    copy_tree "$src" "$new"
    write_version "$src" "$new" "$origin"
    swap_in "$new"
    link_commands

    now=$(version_field COMMIT)
    if [ -z "$before" ]; then
        echo "✅ Instalado em $INSTALL_DIR (commit $now)."
    elif [ "$before" == "$now" ] && [ "$origin" == "$REPO" ] && [ "$before_source" == "$REPO" ]; then
        echo "✅ Já estava na versão mais nova (commit $now)."
    else
        echo "✅ Atualizado em $INSTALL_DIR: $before -> $now."
        if [ "$origin" == "$REPO" ] && git -C "$src" cat-file -e "$before" 2>/dev/null; then
            echo "   O que mudou:"
            git -C "$src" log --oneline --no-decorate "$before..HEAD" | head -20 | sed 's/^/     /'
        fi
    fi

    if has tnrx; then
        if is_server "$INSTALL_DIR"; then
            setup_server
        else
            echo "ℹ️  $(hostname) não está em tnrx_hosts.conf: o tnrx só roda nos servidores listados lá."
        fi
    fi
    if has vscode; then
        setup_vscode
    elif [[ " $before_components " == *" vscode "* ]]; then
        uninstall_vscode
    fi
}

do_update() {
    command -v git >/dev/null 2>&1 || die "O git é necessário para instalar o tnrx."
    local tmp
    tmp=$(mktemp -d)
    echo "📥 Baixando $REPO ($BRANCH)..."
    # --filter=blob:none: traz o histórico (para mostrar o que mudou) sem o conteúdo antigo.
    if ! git clone --quiet --filter=blob:none --branch "$BRANCH" "$REPO" "$tmp/tnrx"; then
        rm -rf "$tmp"
        die "Não consegui clonar $REPO. Se o repositório é privado, use TNRX_REPO=git@github.com:recod-ai/tnrx.git (com chave SSH no GitHub)."
    fi
    # Segue com o instalador da versão nova: o que ela mudar na instalação já vale agora.
    local choose=()
    [ "$CHOOSE" == "true" ] && choose=(--choose)
    exec bash "$tmp/tnrx/install.sh" --clone "$tmp" "${choose[@]}"
}

do_uninstall() {
    local cmd
    SELECTED=$(version_field COMPONENTS)
    has vscode && uninstall_vscode
    for cmd in "${COMMANDS[@]}"; do
        if [ -L "$BIN_DIR/$cmd" ]; then
            rm -f "$BIN_DIR/$cmd"
            echo "🗑️  Removido: $BIN_DIR/$cmd"
        fi
    done
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        echo "🗑️  Removido: $INSTALL_DIR"
    fi
    echo "✨ tnrx desinstalado. Ficaram as imagens (~/.tnrx/sifs) e as configurações do tnrx-connect (~/.config/tnrx-connect)."
}

MODE=update
ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --update) MODE=update ;;
        --from|--clone) MODE="$1"; ARG="$2"; shift ;;
        --uninstall) MODE=uninstall ;;
        --choose) CHOOSE=true ;;
        *) die "Uso: install.sh [--update | --from <pasta> | --uninstall] [--choose]" ;;
    esac
    shift
done

case "$MODE" in
    update) do_update ;;
    --from)
        [ -n "$ARG" ] || die "Uso: install.sh --from <pasta do repositório>"
        src=$(cd "$ARG" 2>/dev/null && pwd -P) || die "Pasta não encontrada: $ARG"
        install_from "$src" "dev:$src"
        ;;
    --clone)
        # Uso interno de do_update: instala o clone em $ARG/tnrx e apaga $ARG no fim.
        CLONE_TMP="$ARG"
        trap 'rm -rf "$CLONE_TMP"' EXIT
        install_from "$CLONE_TMP/tnrx" "$REPO"
        ;;
    uninstall) do_uninstall ;;
esac
