# Tutorial `tnrx`: Apptainer + UV + Slurm

O `tnrx` é um wrapper projetado para unificar o isolamento do **Apptainer**, a velocidade do **uv** e a orquestração do **Slurm**.

### 1. Instalação e Preparação

Em vez de baixar imagens manualmente, o `tnrx` gerencia o ambiente a partir de um arquivo de definição (`.def`).

```bash
# 1. Instala um binário local do uv no seu usuário (~/.local/bin)
./tnrx install uv

# 2. Compila a imagem .sif a partir do arquivo .def presente na pasta
./tnrx install apptainer

```

> **Importante:** O `tnrx` assume que existe apenas um arquivo `.sif` na pasta do projeto.

---

### 2. Gestão de Dependências (Headnode)

O comando `tnrx uv` executa o binário `uv` de dentro do container, mas utiliza a interface de rede do **headnode**. Isso permite instalar pacotes com acesso à internet enquanto garante compatibilidade com o SO do container.

```bash
# Inicializa o projeto (cria pyproject.toml)
./tnrx uv init

# Adiciona bibliotecas (resolve dependências e cria/atualiza o .venv)
./tnrx uv add torch torchvision lightning

```

| Comando | Função |
| --- | --- |
| `tnrx uv add <lib>` | Instala uma nova dependência. |
| `tnrx uv remove <lib>` | Remove uma dependência. |
| `tnrx uv sync` | Sincroniza o ambiente baseado no `uv.lock`. |

---

### 3. Configuração do Cluster (`tnrx_slurm.conf`)

Diferente da versão antiga, você não precisa passar flags de GPU ou Memória via linha de comando. Edite o arquivo `tnrx_slurm.conf` no diretório do projeto:

```bash
PARTITION=l40s
GPUS=1
CPUS=4
MEM=16G
TIME=02:00:00

```

Se precisar mudar de partição (ex: para uma `rtx8000`), basta alterar este arquivo. O `tnrx` lerá essas definições automaticamente antes de submeter qualquer job.

---

### 4. Execução no Slurm

Existem dois modos de execução nos nós de computação:

#### A. Modo Direto (`slurm`)

Para comandos bash genéricos ou scripts que não dependem do ambiente gerenciado pelo `uv`.

```bash
./tnrx slurm nvidia-smi

```

#### B. Modo UV (`uvslurm`) - **Recomendado**

Executa seu código através do `uv run --frozen`. O flag `--frozen` garante que o `uv` não tente acessar a internet para checar dependências, usando estritamente o que está no cache.

```bash
./tnrx uvslurm python train.py --batch-size 32

```

---

### 5. Jupyter Lab e VS Code

#### Rodando Jupyter no Slurm

Para debugar interativamente via notebook:

```bash
./tnrx uvslurm jupyter lab --ip=0.0.0.0 --no-browser

```

#### Configurando o VS Code (Remote-SSH)

Para ter autocomplete e detecção de tipos:

1. `Ctrl+Shift+P` -> **Python: Select Interpreter**.
2. Escolha **Enter interpreter path...**.
3. Forneça o caminho absoluto da pasta `.venv` criada no seu projeto: `/home/usuario/projeto/.venv/bin/python`.

---

### 6. Por que este fluxo é superior?

1. **Configuração Declarativa**: O arquivo `.conf` evita erros de digitação em comandos `srun` longos e mantém o histórico de recursos usados no projeto.
2. **Imutabilidade no Nó**: O uso de `uv run --frozen` no modo `uvslurm` impede que o ambiente mude durante a execução em clusters sem internet.
3. **Cache Persistente**: Ao configurar o `UV_CACHE_DIR` no seu `.def` para apontar para o `$HOME` ou para a pasta do projeto, você evita que o `uv` baixe pacotes repetidamente em nós diferentes.
4. **Simplicidade de Build**: O `tnrx install apptainer` automatiza a criação da imagem, garantindo que o `.sif` esteja sempre alinhado com o seu `.def`.