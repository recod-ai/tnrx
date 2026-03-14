# Tutorial `tnrx`: Apptainer + UV + Slurm

O `tnrx` é um wrapper projetado para unificar o isolamento do **Apptainer**, a velocidade do **uv** e a orquestração do **Slurm**.

## 0. 🚀 Instalando o `tnrx` no seu usuário

Como você já possui a pasta `~/.local/bin` no seu `PATH`, basta transformar o script em um comando global.

**Recomendo usar um link simbólico.** Dessa forma, você pode manter o código-fonte original em uma pasta de desenvolvimento (ou Git) e as alterações refletirão instantaneamente no comando global sem precisar copiar o arquivo novamente.

#### 1. Torne o script executável e crie o link

Navegue até a pasta onde o arquivo `tnrx` está e execute:

```bash
chmod +x tnrx
ln -sf "$(pwd)/tnrx" ~/.local/bin/tnrx

```

#### 2. Teste

Agora, entre em qualquer pasta de projeto que contenha um arquivo `.sif` e um `tnrx_slurm.conf` e digite:

```bash
tnrx slurm nvidia-smi
``` 

Saída esperada (antes de outras configurações)

```
❌ Erro: Nenhum arquivo .sif encontrado. Use 'tnrx install apptainer'.
⚙️  Slurm: l40s | GPU:1 | MEM:16G
```

#### 🧠 Comportamento do Comando Global

É importante lembrar que o `tnrx` foi desenhado para ser **contextual**:

* **No Headnode:** Quando você roda `tnrx uv add ...`, ele procura o `.sif` na pasta atual para saber em qual ambiente deve instalar a biblioteca.
* **No Slurm:** Quando você roda `tnrx slurm ...`, ele lê as configurações do `tnrx_slurm.conf` **da pasta onde você disparou o comando**.

Isso permite que você mude de projeto no terminal e o `tnrx` se comporte de acordo com as necessidades específicas daquele experimento (ex: um projeto com 1 GPU e outro com 4 GPUs).

## 1. Instalação e Preparação

Em vez de baixar imagens manualmente, o `tnrx` gerencia o ambiente a partir de um arquivo de definição (`.def`).

```bash
# 1. Instala um binário local do uv no seu usuário (~/.local/bin)
tnrx install uv

# 2. Compila a imagem .sif a partir do arquivo .def presente na pasta
tnrx install apptainer

```

> **Importante:** O `tnrx` assume que existe apenas um arquivo `.sif` na pasta do projeto.

---

## 2. Gestão de Dependências (Headnode)

O comando `tnrx uv` executa o binário `uv` de dentro do container, mas utiliza a interface de rede do **headnode**. Isso permite instalar pacotes com acesso à internet enquanto garante compatibilidade com o SO do container.

```bash
# Inicializa o projeto (cria pyproject.toml)
tnrx uv init

# Adiciona bibliotecas (resolve dependências e cria/atualiza o .venv)
tnrx uv add torch torchvision lightning

```

| Comando | Função |
| --- | --- |
| `tnrx uv add <lib>` | Instala uma nova dependência. |
| `tnrx uv remove <lib>` | Remove uma dependência. |
| `tnrx uv sync` | Sincroniza o ambiente baseado no `uv.lock`. |

---

## 3. Configuração do Cluster (`tnrx_slurm.conf`)

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

## 4. Execução no Slurm

Existem dois modos de execução nos nós de computação:

#### A. Modo Direto (`slurm`)

Para comandos bash genéricos ou scripts que não dependem do ambiente gerenciado pelo `uv`.

```bash
tnrx slurm nvidia-smi

```

#### B. Modo UV (`uvslurm`) - **Recomendado**

Executa seu código através do `uv run --frozen`. O flag `--frozen` garante que o `uv` não tente acessar a internet para checar dependências, usando estritamente o que está no cache.

```bash
tnrx uvslurm python train.py --batch-size 32

```

---

## 5. Jupyter Lab e VS Code

#### Rodando Jupyter no Slurm

Para debugar interativamente via notebook:

```bash
tnrx uvslurm jupyter lab --ip=0.0.0.0 --no-browser
```

Caso queira já colocar uma senha:

```bash
tnrx uvslurm jupyter lab --ip=0.0.0.0 --no-browser --IdentityProvider.token='sua_senha_aqui'
```

Mas para acessar dentro do seu computador é necessário fazer uma ponte ssh:

```
ssh -L 8888:dl-01:8888 username@headnode
```

#### Configurando o VS Code (Remote-SSH)

Para ter autocomplete e detecção de tipos:

1. `Ctrl+Shift+P` -> **Python: Select Interpreter**.
2. Escolha **Enter interpreter path...**.
3. Forneça o caminho absoluto da pasta `.venv` criada no seu projeto: `/home/usuario/projeto/.venv/bin/python`.
4. Se você estiver em um remote, o jupyter vai indicar o "link" interno como `http://dl-05:8888/lab?token=4312`