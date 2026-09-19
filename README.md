# Tutorial `tnrx`: Singularity + UV + Slurm no Abaporu

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

## 1.2 Trabalhando localmente com Claude Code (`tnrx-connect`)

Os nós de computação do Slurm não têm acesso à internet, e ferramentas como o Claude Code precisam de internet o tempo todo — então elas não podem rodar lá. Rodar essas ferramentas direto no headnode também não é uma boa ideia: é uma máquina compartilhada por todo o time, e um agente de coding facilmente a sobrecarrega. Um proxy de rede pelo headnode resolveria o problema tecnicamente, mas reabriria de propósito o isolamento de rede que os nós têm por motivo de segurança — não é uma decisão pra tomar dentro de um script.

A solução é editar localmente, no seu laptop (com internet plena), e manter o diretório do projeto sincronizado com o servidor. `tnrx-connect` é o companion do `tnrx` que faz isso: roda no **seu laptop**, não no servidor, e não exige instalar nada novo lá — só usa `ssh`/`rsync`, que já existem em qualquer Linux padrão.

### Instalação (no laptop)

```bash
chmod +x tnrx-connect
ln -sf "$(pwd)/tnrx-connect" ~/.local/bin/tnrx-connect
```

### Configuração por projeto (`.tnrx_connect`)

Na raiz do seu projeto (no laptop), copie o template e ajuste:

```bash
cp .tnrx_connect.example /caminho/do/seu/projeto/.tnrx_connect
```

```bash
# .tnrx_connect — configuração local de sincronização (NÃO versionar)
HOST=abaporu                                     # alvo SSH, resolvido a partir do laptop
REMOTE_PATH=/home/seu_usuario/projetos/seu_projeto   # caminho absoluto no servidor
```

Ou gere interativamente com `tnrx-connect init`.

**Atenção:** `HOST` aqui **não é o mesmo campo** que `HOSTNAME` em `tnrx_hosts.conf`. Aquele é a saída de `hostname` *dentro* do servidor (usado pelo `tnrx` pra resolver bind path/runtime); `HOST` em `.tnrx_connect` precisa ser algo que o **seu laptop** consiga resolver via SSH — idealmente um alias do seu `~/.ssh/config`. Use o mesmo nome nos dois só por consistência mental; são arquivos independentes, em máquinas diferentes.

`.tnrx_connect` fica no `.gitignore` (como o `.tnrx_env`): `REMOTE_PATH` depende do `$HOME` de cada pessoa no servidor, não é algo pra versionar.

### Uso

| Comando | O que faz |
| --- | --- |
| `tnrx-connect` | Sincroniza uma vez e abre um terminal SSH no servidor; mantém a sincronização ativa em background enquanto essa sessão estiver aberta (default: `connect`) |
| `tnrx-connect sync` | Sincroniza uma vez (local → remoto), sem abrir SSH — útil antes de um `tnrx slurm`/`tnrx uvslurm` pontual |
| `tnrx-connect pull` | Puxa do servidor pro local uma vez, sem apagar nada local — pra recuperar um resultado pequeno gerado manualmente no projeto |
| `tnrx-connect init` | Cria o `.tnrx_connect` deste projeto interativamente |
| `tnrx-connect uninstall` | Remove o symlink local |

No dia a dia: rode `tnrx-connect` no seu laptop, edite os arquivos localmente com o Claude Code, e use o terminal do servidor que ele abriu pra disparar `tnrx slurm`/`tnrx uvslurm`/`tnrx uvslurm jupyter lab` normalmente — exatamente como documentado no resto deste README. A sincronização continua rodando em background e some sozinha quando você sai da sessão (`exit`, `Ctrl-D` ou queda de conexão).

### Como a sincronização funciona

- Só sincroniza **do laptop pro servidor** por padrão (o laptop é a fonte da verdade do código). `pull` é manual e não apaga nada.
- Usa o **próprio `.gitignore` do seu projeto** como lista de exclusão do `rsync` — `.venv/`, `*.sif`, `slurm-*.out` etc. nunca são enviados nem apagados no servidor, exatamente como já são ignorados pelo git.
- Resultados de treino/logs devem ir para o storage compartilhado já bind-montado (`/data`/`/hadatasets`, o mesmo `HUB_ROOT` do `tnrx hf`), não para dentro do diretório do projeto — assim nunca precisam "voltar" pro laptop.
- É um polling simples (a cada alguns segundos, configurável via `POLL_INTERVAL` em `.tnrx_connect`), não um watcher instantâneo — o `rsync` já faz diff incremental por conta própria, então isso é barato.

### Login com senha + 2FA (ex.: Abaporu)

Se o `HOST` exige senha e segundo fator (não só chave SSH), o `tnrx-connect connect` pede isso **uma única vez**, no início: ele abre uma conexão SSH "mestra" (multiplexada) e todo o resto da sessão — o `mkdir` inicial, cada rodada do sync em background, o terminal interativo — reaproveita essa mesma conexão já autenticada, sem pedir senha/2FA de novo. Ao sair (`exit`/`Ctrl-D`), essa conexão mestra é encerrada junto.

`tnrx-connect sync`/`tnrx-connect pull` usados sozinhos (sem uma sessão `connect` aberta) pedem senha/2FA normalmente a cada chamada, como um `ssh` manual — mas se você já tem um `tnrx-connect connect` aberto em outra aba pro mesmo `HOST`, eles detectam e reaproveitam essa conexão também, sem prompt.

### Cuidados

- **`--delete` está ligado por padrão** (`SYNC_DELETE=true` em `.tnrx_connect`): arquivos apagados localmente somem do servidor no próximo sync. Um arquivo criado manualmente no servidor, dentro do projeto, e não coberto pelo `.gitignore` pode ser apagado — desative com `SYNC_DELETE=false` se isso for um problema pro seu fluxo.
- **Rede caiu no meio da sessão?** A conexão mestra cai junto, e o sync em background passa a falhar (fica só no log, não trava). Rode `tnrx-connect connect` de novo — vai pedir senha/2FA de novo, é esperado.
- **Editou e disparou um job na sequência muito rápido?** O polling pode não ter processado ainda; rode `tnrx-connect sync` bloqueante antes de um `tnrx slurm`/`uvslurm` pontual, em vez de confiar só no sync em background.
- Pré-requisito: cliente OpenSSH com suporte a `ControlMaster` (padrão em qualquer instalação razoavelmente recente) — é o que permite autenticar uma vez só por sessão.

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

O `tnrx` possui um comando dedicado para espelhar modelos e datasets do Hugging Face em um diretório compartilhado (`/data/huggingface_hub`). Isso economiza espaço no seu `/home` e evita downloads duplicados.

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

* `uv-lock-check`: Verifica se o ficheiro `uv.lock` está sincronizado com o `pyproject.toml`. Se adicionaste algo ao projeto e esqueceste de rodar o sync, o commit falhará.

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
