#!/bin/bash

# --- Configurações ---
IMAGE="pytorch_latest.sif"
CONTAINER_PYTHON="/usr/bin/python3"
VENV_DIR=".venv"
UV_BIN="$HOME/.local/bin/uv"

# Função para instalar o UV no host
install_uv_host() {
    echo "📥 Instalando UV no host (~/.local/bin)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    echo "✅ UV instalado."
}

# Verifica se o UV existe
check_uv() {
    if [ ! -f "$UV_BIN" ]; then
        echo "❌ Erro: UV não encontrado em $UV_BIN. Rode: ./uvapp.sh install"
        exit 1
    fi
}

# Verifica se a imagem existe
if [ ! -f "$IMAGE" ]; then
    echo "❌ Erro: Imagem $IMAGE não encontrada."
    exit 1
fi

COMMAND=$1
shift

case $COMMAND in
    install)
        install_uv_host
        ;;

    # Comando nativo do UV para criar o projeto (pyproject.toml)
    init)
        check_uv
        echo "🚀 Inicializando projeto com UV..."
        # Roda o init do uv no host (não precisa do container para criar o .toml)
        "$UV_BIN" init "$@"
        ;;

    # Garante que o venv dentro do container esteja sincronizado
    sync)
        check_uv
        echo "🔄 Sincronizando ambiente virtual dentro do container..."
        apptainer exec "$IMAGE" "$UV_BIN" sync --python "$CONTAINER_PYTHON"
        ;;
    
    # Adiciona pacotes ao pyproject.toml e instala
    add|remove|lock)
        check_uv
        echo "📦 Executando uv $COMMAND..."
        apptainer exec "$IMAGE" "$UV_BIN" "$COMMAND" "$@"
        ;;

    # Executa comandos no ambiente do container
    run)
        # Se o .venv não existir, tenta dar um sync automático
        if [ ! -d "$VENV_DIR" ]; then
            echo "⚠️  Ambiente .venv não encontrado. Tentando sincronizar..."
            apptainer exec "$IMAGE" "$UV_BIN" sync --python "$CONTAINER_PYTHON"
        fi
        apptainer exec --nv "$IMAGE" "$UV_BIN" run "$@"
        ;;

    *)
        echo "Uso: ./uvapp.sh {install|init|sync|add|remove|lock|run}"
        echo "  Ex: ./uvapp.sh init           (Cria pyproject.toml)"
        echo "  Ex: ./uvapp.sh add numpy      (Instala e salva no toml)"
        echo "  Ex: ./uvapp.sh sync           (Instala o que está no lock)"
        echo "  Ex: ./uvapp.sh run python x.py(Roda com GPU)"
        exit 1
        ;;
esac