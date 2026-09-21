# `tnrx`: Singularity + UV + Slurm no servidor

> **Onde roda:** no **servidor** (Abaporu, Headnode). Este documento cobre o `tnrx`. Para editar código no seu laptop (ex.: com o Claude Code), veja o [`tnrx-connect`](tnrx-connect.md). Visão geral das duas ferramentas: [README](../README.md).

O `tnrx` é um wrapper projetado para unificar o isolamento do **Singularity**, a velocidade do **uv** e a orquestração do **Slurm**.

## 🚀 Instalando o `tnrx` no seu usuário

Como você já possui a pasta `~/.local/bin` no seu `PATH`, basta transformar o script em um comando global.

**Recomendo usar um link simbólico.** Dessa forma, você pode manter o código-fonte original em uma pasta de desenvolvimento (ou Git) e as alterações refletirão instantaneamente no comando global sem precisar copiar o arquivo novamente.

### 1. Torne o script executável e crie o link

Navegue até a pasta onde o arquivo `tnrx` está e execute:

```bash
chmod +x tnrx
ln -sf "$(pwd)/tnrx" ~/.local/bin/tnrx
```

### 2. Teste

Agora, entre em qualquer pasta de projeto que contenha um arquivo `.sif` e um `tnrx_slurm.conf` e digite:

```bash
tnrx slurm nvidia-smi
```

Saída esperada (antes de outras configurações)

```bash
❌ Erro: Nenhum arquivo .sif encontrado. Use 'tnrx install singularity'.
⚙️  Slurm: h200 | GPU:1 | MEM:16G
```

#### 🧠 Comportamento do Comando Global

É importante lembrar que o `tnrx` foi desenhado para ser **contextual**:

* **No Headnode:** Quando você roda `tnrx uv add ...`, ele procura o `.sif` na pasta atual para saber em qual ambiente deve instalar a biblioteca.
* **No Slurm:** Quando você roda `tnrx slurm ...`, ele lê as configurações do `tnrx_slurm.conf` **da pasta onde você disparou o comando**.

Isso permite que você mude de projeto no terminal e o `tnrx` se comporte de acordo com as necessidades específicas daquele experimento (ex: um projeto com 1 GPU e outro com 4 GPUs).

## 1. Instalação e Preparação

Neste ambiente, o gerenciamento é feito utilizando uma imagem SIF pronta, otimizada para performance em GPUs. O `tnrx` facilita a configuração do binário do `uv` e a busca da imagem necessária.

```bash
tnrx install uv
tnrx install singularity
```

---

## 1.1 Particularidades de cada servidor (`tnrx_hosts.conf`)

Bind path, binário do runtime (`singularity`/`apptainer`) e o diretório compartilhado do Hugging Face Hub variam de servidor para servidor (ex.: Abaporu usa `/data/` e Headnode usa `/hadatasets/`). Em vez de ficarem hardcoded no script, essas particularidades ficam centralizadas em `tnrx_hosts.conf`, na mesma pasta do script `tnrx`:

```
# HOSTNAME | BIND_PATH | RUNTIME | HUB_ROOT
abaporu|/data/:/data/|singularity|/data/huggingface_hub
headnode|/hadatasets/:/hadatasets/|singularity|/hadatasets/huggingface_hub
```

O `tnrx` identifica o servidor atual via `hostname` e busca a linha correspondente nesse arquivo antes de qualquer comando que dependa do container. Hoje todos os servidores do grupo usam `singularity` (o Abaporu não tem `apptainer` instalado), mas o campo `RUNTIME` existe justamente para não travar o projeto nesse binário caso outro servidor use `apptainer` no futuro — basta adicionar uma linha nova, sem tocar no script.

Se o hostname atual não estiver listado, o `tnrx` recusa a execução e mostra quais hosts estão configurados.

---

## 2. Gestão de Dependências (Headnode)

O comando `tnrx uv` executa o binário `uv` de dentro do container, mas utiliza a interface de rede do **headnode**. Isso permite instalar pacotes com acesso à internet enquanto garante compatibilidade com o SO do container.

Como já temos um ``pyproject.toml` inicial, não precisamos inicializar o repositório, mas sim podemos diretamente adicionar novas bibliotecas.

```bash
# Adiciona bibliotecas (resolve dependências e cria/atualiza o .venv)
tnrx uv add torch torchvision lightning

```

| Comando | Função |
| --- | --- |
| `tnrx uv init` | Inicializa o projeto (cria pyproject.toml). |
| `tnrx uv add <lib>` | Instala uma nova dependência. |
| `tnrx uv remove <lib>` | Remove uma dependência. |
| `tnrx uv sync` | Sincroniza o ambiente baseado no `uv.lock`. |

---

## 3. Configuração do Cluster (`tnrx_slurm.conf`)

Você não precisa passar flags de GPU ou Memória via linha de comando. Edite o arquivo `tnrx_slurm.conf` no diretório do projeto:

```bash
PARTITION=h200
GPUS=1
CPUS=4
MEM=16G
TIME=02:00:00

```

Se precisar mudar de partição (ex: para a `l40s`), basta alterar este arquivo. O `tnrx` lerá essas definições automaticamente antes de submeter qualquer job.

---

## 4. Variáveis de Ambiente Customizadas (`.tnrx_env`)

Caso precise alterar ou adicionar variáveis de ambiente dentro do container (ex: configurar Proxy, mudar o cache do NLTK ou ajustar certificados SSL), você pode criar um arquivo chamado `.tnrx_env` na raiz do seu projeto.

O tnrx carregará esse arquivo automaticamente e injetará as variáveis no container.

### Como usar

Crie o arquivo `.tnrx_env` e defina as variáveis no formato `CHAVE=VALOR`:

```Bash
# Exemplo de conteúdo do .tnrx_env
SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
REQUESTS_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
NLTK_DATA=/data/nltk_data
DEBUG_MODE=true
```

### Comportamentos Específicos:

* **Anular uma variável**: Se você quiser que uma variável seja lida como vazia pelo Python (""), basta deixá-la sem valor: `MINHA_VAR=`.

* **Persistência**: O arquivo é opcional. Se ele não existir, o tnrx seguirá as configurações padrão do sistema.

* **Segurança**: Por padrão, o `.tnrx_env` está no `.gitignore`, já que ele pode conter chaves de API ou tokens sensíveis.

## 5. Execução no Slurm

Existem dois modos de execução nos nós de computação:

### A. Modo Direto (`slurm`)

Para comandos bash genéricos ou scripts que não dependem do ambiente gerenciado pelo `uv`.

```bash
tnrx slurm nvidia-smi
```

### B. Modo UV (`uvslurm`) - **Recomendado**

Executa seu código através do `uv run --frozen`. O flag `--frozen` garante que o `uv` não tente acessar a internet para checar dependências, usando estritamente o que está no cache.

```bash
tnrx uvslurm python deep_check.py
```

---

## 6. Jupyter Lab e VS Code

### Rodando Jupyter no Slurm

O comando `tnrx` automatiza a alocação de GPU, o isolamento via Singularity e a configuração do ambiente Python.

⚠️ Importante: Antes de rodar o Jupyter pela primeira vez, você deve instalar o pacote `ipykernel` no seu ambiente virtual através do container. Sem ele, o Jupyter não conseguirá conectar ao seu código:

```bash
tnrx uv add ipykernel
```

 Para iniciar o servidor no cluster:

```bash
tnrx uvslurm jupyter lab
```

**Nota**: O script detecta o comando jupyter e injeta automaticamente as flags --ip=0.0.0.0, --no-browser e as permissões de acesso, além de criar um kernel para o ambiente em `.venv`, cujo nome será `Python (TNRX-nome_da_pasta)`

### Acessando via VS Code (Remote-SSH)

1. Para conectar seu notebook ao servidor rodando na GPU:

    * Abra seu arquivo `deep_check.ipynb`.

    * Clique em **Select Kernel** (canto superior direito) -> **Existing Jupyter Server**.

    * Cole a URL completa com o token gerado no terminal, substituindo o `hostname` pelo **nome do nó** (verificar com o comando `squeue`) (ex: `http://gpu03:8888/lab?token=...`).

2. Selecionar o Kernel do Projeto:

    * Após conectar ao servidor, clique novamente no Kernel e escolha o kernel específico do projeto: `Python (TNRX-nome_da_pasta)`.

    * Este kernel aponta diretamente para o seu `.venv`, garantindo que o import torch funcione com a versão correta.

### Autocomplete e Tipagem

Para que o VS Code reconheça as bibliotecas do ambiente enquanto você escreve código:

1. `Ctrl+Shift+P` -> Python: Select Interpreter.

2. O VS Code deve detectar automaticamente o ambiente em `./.venv/bin/python`. Caso não apareça, escolha **Enter interpreter path...** e forneça o caminho absoluto.

---

## 7. Hugging Face Shared Hub (Central de Modelos/Datasets)

O `tnrx` possui um comando dedicado para espelhar modelos e datasets do Hugging Face em um diretório compartilhado. Isso economiza espaço no seu `/home` e evita downloads duplicados.

O caminho desse diretório é definido pelo campo `HUB_ROOT` de [`tnrx_hosts.conf`](#11-particularidades-de-cada-servidor-tnrx_hostsconf) — **varia por servidor** (ex.: `/data/huggingface_hub` no Abaporu, `/hadatasets/huggingface_hub` no Headnode), então os exemplos abaixo usam o caminho do Abaporu; ajuste conforme o servidor em que você está.

### A. Preparação e Instalação do Comando

Para que o `tnrx` consiga invocar o utilitário de download independentemente da pasta onde você está, siga estes passos para torná-lo um binário global:

#### Crie link e  dê permissão: Transforme o script em um executável chamado apenas `download_huggingface` (sem o `.py`) dentro da sua pasta de binários local

```bash
chmod +x download_huggingface
ln -sf "$(pwd)/download_huggingface" ~/.local/bin/download_huggingface
```

### B. Configurando sua Autenticação

Para baixar modelos (especialmente os privados ou com restrições), você deve fornecer seu Token do Hugging Face.

1. Vá em **Hugging Face Settings -> Tokens** e crie um token de leitura.
2. Adicione-o ao seu ambiente no Headnode (adicione esta linha no seu `~/.bashrc` para persistir):

```bash
export HF_TOKEN="hf_seu_token_aqui"
```

Obs: esse export irá "morrer" em cada sessão, então quando for usar de novo, se quiser manter fixo. Aplique a mudança: `source ~/.bashrc`.

O `tnrx` detectará automaticamente esta variável e a repassará com segurança para dentro do container durante o download.

### C. Baixando Modelos e Datasets

Os downloads ocorrem obrigatoriamente no **Headnode**, pois os nós de computação não possuem acesso à internet.

```bash
# Baixar um modelo
tnrx hf model google/siglip1-base-patch16-224

# Baixar um dataset
tnrx hf dataset jxie/flickr8k
```

| Comando | Descrição | Destino no Host |
| --- | --- | --- |
| `tnrx hf model <id>` | Baixa um modelo do HF. | `/data/huggingface_hub/models/` |
| `tnrx hf dataset <id>` | Baixa um dataset do HF. | `/data/huggingface_hub/datasets/` |

### D. Como usar no seu código

Como o diretório `/data` é montado automaticamente pelo `tnrx` em todos os nós via `--bind`, você pode carregar os modelos diretamente apontando para o caminho absoluto. O `tnrx` cuida do mapeamento do volume para você:

```python
from transformers import AutoModel

# O caminho segue a estrutura: /data/huggingface_hub/tipo/autor/repo
model_path = "/data/huggingface_hub/models/google/siglip2-base-patch16-224"

model = AutoModel.from_pretrained(model_path)

```

Para verificarmos que isso funciona:

```bash
tnrx uv add transformers
tnrx uvslurm python load_model.py /data/huggingface_hub/models/google/siglip2-base-patch16-224
```

---

## 8. Qualidade de Código e Pre-commit

Para garantir que o código segue os padrões do projeto (Black, Isort) e que as dependências no `uv.lock` estão sempre sincronizadas com o `pyproject.toml`, utilizamos o **pre-commit**.

### Instalação

Os hooks do pre-commit devem ser instalados no teu ambiente local (nó de login) para que o VS Code os execute instantaneamente ao realizar um commit:

1. **Instale o pre-commit:**

```bash
tnrx uv add pre-commit
```

1. **Instale os hooks do Git**

Como o versionamento (normalmente) é feito fora do container, a instalação deve também ser feita fora.

```bash
./.venv/bin/pre-commit install
```

**O que o Pre-commit atual (`.pre-commit-config.yaml`) faz?**

Sempre que tentar realizar um git commit (seja via terminal ou interface do VS Code), os seguintes passos são validados:

* `uv-lock-check`: Verifica se o ficheiro `uv.lock` está sincronizado com o `pyproject.toml`, reaproveitando o próprio `./tnrx uv lock --check` (que já resolve bind path/runtime/uv certos a partir de `tnrx_hosts.conf`). Por isso, precisa rodar num host reconhecido nesse arquivo. Se adicionaste algo ao projeto e esqueceste de rodar o sync, o commit falhará.

* `uv-format-toml` (opcional): compila o `pyproject.toml` com `uv pip compile` só pra validar que ele resolve, sem tocar em `/data`/`/hadatasets`.

* `tnrx-test-suite` / `tnrx-connect-test-suite`: rodam `test_tnrx.sh`/`test_tnrx_connect.sh` a cada commit — cobrem parsing de config, mensagens de erro e a montagem dos comandos `singularity`/`rsync` (via `--debug`), sem depender de GPU/rede real. A do `tnrx-connect` também exercita o modo mount de ponta a ponta com `ssh`/`rclone`/`fusermount3` falsos (lock, recuperação de sessão, snapshots) e leva cerca de 25s.

* `Black`: Formata automaticamente o teu código Python para seguir as normas PEP8.

* `Isort`: Organiza os teus imports por ordem alfabética e por secções (standard, third-party, local).

* `Checkers`: Valida a sintaxe de ficheiros YAML e TOML e impede que subas ficheiros de pesos/dados superiores a 10MB para o repositório.

### Demonstração

1. Altere exclusivamente o `pyproject.toml`

```bash
echo 'scipy = ">=1.10.0"' >> pyproject.toml
```

1. Tente o commit

Pode ser tanto na linha de comando quanto no vscode - deve funcionar em ambos

```bash
git add pyproject.toml
git commit -m "teste"
```

O pre-commit vai interceptar o comando e produzir um output semelhante a este

```bash
Check if uv.lock is out of sync..........................................Failed
- hook id: uv-lock-check
- exit code: 1
error: The lock file is out of sync with the project file. Run `uv lock` to update.
```

O Git **não** criou o commit. Mais especificamente, O `uv-lock-check` impediu que enviasse um projeto que "quebraria" na mão de outro colega porque havia inconsistência entre o `pyproject.toml` e o `uv.lock`.

### Como Resolver Falhas

Se o pre-commit bloquear um commit:

* Erro de Sincronização (`uv.lock`): Significa que o teu ambiente mudou. Faça o comando de sincronização via tnrx:

```Bash
tnrx uvslurm uv sync
```

Depois, adicione o `uv.lock` alterado ao commit.

* Erros de Formatação: O Black/Isort corrigirá os ficheiros automaticamente. Basta adicionar as alterações (`git add .`) e tentar o commit novamente.
