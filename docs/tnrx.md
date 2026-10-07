# `tnrx`: rodar projetos no cluster

> **Onde roda:** no servidor (Abaporu, Headnode). Para trabalhar no projeto a partir do laptop, veja o [`tnrx-connect`](tnrx-connect.md). Visão geral: [README](../README.md).

O `tnrx` junta três peças para que todo projeto rode do mesmo jeito em qualquer servidor:

* **Container (Apptainer/Singularity):** o sistema em que o código roda (Ubuntu, CUDA, cuDNN) vem de uma imagem (`.sif`), escolhida no `tnrx.conf` do projeto. O resultado não depende do que está instalado no servidor.
* **uv:** o Python e as bibliotecas ficam num `.venv` na pasta do projeto, descritos pelo `pyproject.toml` e travados pelo `uv.lock`.
* **Slurm:** os jobs vão para os nós de GPU com os recursos do `tnrx.conf` do projeto.

Uma regra explica quase todos os comandos: **o headnode tem internet, os nós de computação não.** Por isso, tudo o que baixa algo (bibliotecas, imagem, modelos) roda no headnode, e tudo o que usa GPU roda nos nós, só com o que já foi baixado.

| Comando | Onde roda | Para quê |
| --- | --- | --- |
| `tnrx update` | headnode | Atualizar o `tnrx` |
| `tnrx uv ...` | headnode, dentro do container | Gerenciar as bibliotecas |
| `tnrx hf ...` | headnode, dentro do container | Baixar modelos e datasets do Hugging Face |
| `tnrx uvslurm ...` | nó de GPU, dentro do container, com o `.venv` | Rodar o código do projeto (o modo normal) |
| `tnrx slurm ...` | nó de GPU, dentro do container, sem o `.venv` | Rodar um comando qualquer; abrir um shell no nó |

Todo comando vale para a **pasta atual**: o `tnrx` usa o `tnrx.conf`, o `.venv` e o `.tnrx_env` da pasta onde você está. Por isso cada projeto pode ter sua imagem, suas bibliotecas e seus recursos de GPU.

## Instalação

Uma vez por usuário, em cada servidor (e no laptop, para o [`tnrx-connect`](tnrx-connect.md#instalação)). Precisa de `git` e de `~/.local/bin` no `PATH`.

```bash
curl -fsSL https://raw.githubusercontent.com/recod-ai/tnrx/main/install.sh | bash
```

O instalador pergunta o que instalar:

```
O que instalar nesta máquina? (servidor abaporu)
  tnrx: roda os projetos no cluster (servidor) [S/n]:
  download_huggingface: baixa modelos e datasets com 'tnrx hf' [S/n]:
  tnrx-connect: trabalha no projeto do servidor a partir do laptop [s/N]:
```

| Componente | Para quê | Sugerido em |
| --- | --- | --- |
| `tnrx` | Rodar os projetos no cluster | Servidor |
| `download_huggingface` | Usado pelo `tnrx hf`; só é oferecido junto com o `tnrx` | Servidor |
| `tnrx-connect` | Trabalhar no projeto do servidor a partir do laptop | Laptop |
| Extensão do VS Code | Barra lateral do `tnrx-connect`; só é oferecida junto com ele, e se o comando `code` existir | Laptop |

A máquina é um servidor se o hostname dela está em [`tnrx_hosts.conf`](#servidores-tnrx_hostsconf). Enter aceita a sugestão. Depois ele:

1. copia os arquivos para `~/.local/share/tnrx` (mude com `TNRX_HOME`). Você não precisa de uma pasta `tnrx` no servidor;
2. cria em `~/.local/bin` os comandos escolhidos, que apontam para essa pasta;
3. com o `tnrx` escolhido, num servidor, roda `tnrx install`: instala o `uv`, se faltar, e baixa a imagem padrão do container para o [banco de imagens](#a-imagem-do-container), se ela ainda não estiver lá;
4. com a extensão escolhida, gera e instala a extensão no VS Code.

A escolha fica gravada: as atualizações repetem a mesma escolha sem perguntar. Para mudar, use `tnrx update --choose`; o que deixou de ser escolhido é removido. Sem terminal para perguntar, ele instala o que sugeriria para a máquina. Para escolher sem perguntas, use `TNRX_COMPONENTS="tnrx download_huggingface"`.

| Comando | O que faz |
| --- | --- |
| `tnrx update` | Baixa a versão mais nova do GitHub, troca a instalação e mostra o que mudou. Roda os passos 3 e 4 de novo, então algo novo que a versão precise já fica pronto |
| `tnrx update --choose` | O mesmo, perguntando de novo o que instalar |
| `tnrx version` | Commit e data da versão instalada |
| `tnrx uninstall` | Remove os comandos, a extensão do VS Code (se foi instalada) e a pasta da instalação. O banco de imagens fica |

A atualização troca a pasta inteira de uma vez, então uma montagem do `tnrx-connect` ou um job que já está rodando não é afetado.

**Repositório privado:** o `curl` acima só funciona com o repositório público. Com ele privado, instale por SSH (precisa de uma chave SSH cadastrada no GitHub):

```bash
git clone git@github.com:recod-ai/tnrx.git /tmp/tnrx
TNRX_REPO=git@github.com:recod-ai/tnrx.git bash /tmp/tnrx/install.sh
rm -rf /tmp/tnrx
```

A instalação lembra o endereço, e os `tnrx update` seguintes usam o mesmo.

O `tnrx` só roda nos servidores listados em [`tnrx_hosts.conf`](#servidores-tnrx_hostsconf). Num servidor que não está lá, ele recusa e mostra os que estão.

## Preparar um projeto

Uma vez por projeto, na pasta dele:

```bash
cd ~/meu-projeto
tnrx uv init                        # só se ainda não existe um pyproject.toml
tnrx uv add torch                   # bibliotecas do projeto
cp ~/tnrx/deep_check.py .
tnrx uvslurm python deep_check.py   # confere a GPU
```

Nada mais é obrigatório: sem configuração, o projeto usa a imagem padrão e os recursos padrão do Slurm. A imagem é baixada para o [banco de imagens](#a-imagem-do-container) na primeira vez que precisar.

Arquivos que o `tnrx` usa na pasta do projeto:

| Arquivo | O que é | Vai para o git? |
| --- | --- | --- |
| `tnrx.conf` | Opcional: recursos do Slurm e a imagem do container ([detalhes](#configuração-do-projeto-tnrxconf)) | Sim |
| `tnrx.def` | Opcional: a receita da imagem, se o projeto precisa de pacotes do sistema ([detalhes](#customizar-a-imagem-tnrxdef)) | Sim |
| `pyproject.toml`, `uv.lock` | Bibliotecas do projeto | Sim |
| `.venv/` | O ambiente instalado | Não |
| `.tnrx_env` | Opcional: variáveis de ambiente para dentro do container ([detalhes](#variáveis-de-ambiente-tnrx_env)) | Não (pode ter tokens) |
| `.tnrx/` | Criada pelo `tnrx`: registro dos Jupyters no ar, com a senha deles | Não (tem um `.gitignore` próprio) |

## Configuração do projeto (`tnrx.conf`)

Cada projeto pode ter um `tnrx.conf` na pasta. As chaves que faltam ficam com o padrão. Há um exemplo comentado em [`tnrx.conf`](../tnrx.conf):

```bash
PARTITION=h200
GPUS=1
CPUS=4
MEM=16G
TIME=02:00:00
IMAGE=docker://nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04
```

| Chave | O que é | Padrão |
| --- | --- | --- |
| `PARTITION` | Partição do Slurm (as disponíveis estão no `sinfo`) | `l40s` |
| `GPUS` | GPUs por job | `1` |
| `CPUS` | CPUs por job | `2` |
| `MEM` | Memória por job | `4G` |
| `TIME` | Tempo máximo do job | `00:10:00` |
| `IMAGE` | Imagem do container ([detalhes](#a-imagem-do-container)) | o `tnrx.def` do projeto, se existir, senão `docker://nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04` |

O arquivo é lido como um script `bash`, então não use espaços em volta do `=`. Ele é do projeto e vai para o git: quem clonar o projeto roda com os mesmos recursos e a mesma imagem. No laptop, dá para editá-lo como qualquer arquivo da pasta montada, com `tnrx-connect config set GPUS=2` ou pela [extensão do VS Code](../vscode/README.md).

O nome antigo, `tnrx_slurm.conf`, ainda é lido quando o projeto não tem `tnrx.conf`; o `tnrx` avisa para renomear. O `tnrx install singularity` e o `tnrx-connect config` renomeiam sozinhos quando gravam algo.

## A imagem do container

O `IMAGE` do `tnrx.conf` aceita três formas:

| Valor | Exemplo |
| --- | --- |
| Uma imagem Docker | `IMAGE=docker://nvcr.io/nvidia/pytorch:24.01-py3` (sem `docker://`, ele assume Docker) |
| Um *definition file* do projeto | `IMAGE=tnrx.def` ([detalhes](#customizar-a-imagem-tnrxdef)) |
| O caminho de um `.sif` pronto | `IMAGE=/hadatasets/imagens/minha.sif` |

Sem `IMAGE`, o `tnrx` usa, nesta ordem: um `.sif` que esteja na pasta do projeto (o jeito antigo), o `tnrx.def` do projeto, a imagem padrão.

As imagens Docker e as de `.def` ficam num **banco por usuário**, `~/.tnrx/sifs/` (mude com a variável `TNRX_SIF_DIR`). Cada imagem é baixada ou gerada uma vez, no primeiro comando que precisar dela, sempre no headnode (os nós de GPU não têm internet); dez projetos com a mesma imagem ocupam o espaço de uma. O nome no banco diz de onde a imagem veio:

| Origem | Nome no banco |
| --- | --- |
| `docker://nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04` | `nvidia_cuda_12.6.3-cudnn-runtime-ubuntu24.04.sif` |
| `docker://nvcr.io/nvidia/pytorch:24.01-py3` | `nvcr.io_nvidia_pytorch_24.01-py3.sif` |
| um `tnrx.def` com `From: nvidia/cuda:12.6.3-...` | `nvidia_cuda_12.6.3-...__def-<hash>.sif` |

O `<hash>` vem do conteúdo do `.def`: projetos com o mesmo `.def` compartilham a imagem, e editar o `.def` faz o próximo comando gerar uma imagem nova. As antigas continuam no banco até você apagá-las (`ls -lh ~/.tnrx/sifs`); se uma imagem apagada for necessária de novo, ela é baixada ou gerada outra vez. Se a sua cota no `/home` for pequena, aponte o `TNRX_SIF_DIR` para o armazenamento compartilhado (ex.: `export TNRX_SIF_DIR=/hadatasets/$USER/sifs` no `~/.bashrc`).

A imagem padrão é `nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04`: Ubuntu 24.04, CUDA 12.6 e cuDNN 9, **sem Python**. O Python vem do `uv`: no primeiro `tnrx uv sync` ou `tnrx uv add`, ele baixa a versão pedida no `pyproject.toml` (em `~/.local/share/uv/python/`) e cria o `.venv` com ela. Para fixar a versão do Python, crie um arquivo `.python-version` no projeto (ex.: `echo 3.12 > .python-version`) e coloque-o no git.

### Customizar a imagem (`tnrx.def`)

Para pacotes do sistema (um `apt-get install`), o projeto precisa de uma imagem própria. O formato do Apptainer/Singularity para isso é o *definition file* (`.def`), o equivalente ao `Dockerfile`. O repositório traz um modelo, [`tnrx.def`](../tnrx.def), que gera a imagem padrão com `git` e `curl`:

```bash
cp ~/tnrx/tnrx.def .
# edite a seção %post: apt-get install -y --no-install-recommends <pacotes>
tnrx install singularity
```

Para trocar a imagem, mude o `IMAGE` no `tnrx.conf`, ou use `tnrx install singularity [origem]`: ele grava o `IMAGE` e já baixa ou gera a imagem, para o primeiro job não esperar por isso. Sem origem, ele usa o `tnrx.def` do projeto, se existir, senão a imagem padrão. `--force` baixa ou gera a imagem de novo.

**Build sem root:** gerar a imagem a partir de um `.def` usa `--fakeroot`, que só funciona se o admin configurou `/etc/subuid` e `/etc/subgid` para o seu usuário. Se o build falhar por isso, a mensagem diz o nome que a imagem deve ter: gere-a numa máquina em que você tenha root (`apptainer build <nome> tnrx.def`) e copie para o banco no servidor.

**Ao trocar de imagem**, rode `tnrx uv sync` para recriar o `.venv`.

## Bibliotecas (`tnrx uv`)

O `tnrx uv` roda o `uv` dentro do container, no headnode, que tem internet:

```bash
tnrx uv add numpy pandas      # adiciona ao pyproject.toml, atualiza o uv.lock e instala no .venv
tnrx uv remove pandas         # remove
tnrx uv sync                  # deixa o .venv igual ao uv.lock (depois de um git pull, por exemplo)
tnrx uv lock                  # atualiza o uv.lock depois de editar o pyproject.toml à mão
tnrx uv tree                  # mostra a árvore de dependências
```

São aceitos `add`, `remove`, `sync`, `init`, `lock`, `tree` e `export`. Para **executar** código, use `tnrx uvslurm`: `tnrx uv run` é recusado, porque rodaria no headnode compartilhado.

## Rodar no Slurm

```bash
tnrx uvslurm python train.py --epochs 10    # o código do projeto, com o .venv (o modo normal)
tnrx slurm nvidia-smi                       # um comando qualquer, sem o .venv
tnrx slurm                                  # shell interativo num nó de GPU (o mesmo que `tnrx slurm bash`)
```

O `tnrx uvslurm` roda `uv run --frozen` no nó: usa o `uv.lock` como está, sem tentar atualizá-lo. Como o nó não tem internet, rode `tnrx uv sync` no headnode antes, sempre que as bibliotecas mudarem.

O job roda em primeiro plano: a saída aparece no terminal, e `Ctrl-C` o cancela. Para acompanhar e cancelar de outro terminal: `squeue -u $USER` e `scancel <job>`.

Os recursos do job (partição, GPUs, CPUs, memória e tempo) vêm do [`tnrx.conf`](#configuração-do-projeto-tnrxconf) do projeto. As partições disponíveis aparecem no `sinfo` (ou em `tnrx-connect cluster`, no laptop).

### Variáveis de ambiente (`.tnrx_env`)

Variáveis listadas no `.tnrx_env` da pasta do projeto chegam ao código dentro do container, em todos os comandos (`uv`, `slurm`, `uvslurm`, `hf`):

```bash
SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
NLTK_DATA=/data/nltk_data
WANDB_MODE=offline
MINHA_VAR=                 # sem valor: a variável existe e é vazia
```

Uma variável por linha, no formato `CHAVE=VALOR`. Linhas vazias e começadas por `#` são ignoradas. O valor é usado como está: não coloque aspas. O `.tnrx_env` fica fora do git, então ele pode guardar tokens.

### Conferir a GPU

O repositório tem dois scripts de exemplo. Copie para o projeto o que servir:

```bash
tnrx uvslurm python deep_check.py        # PyTorch: precisa de `tnrx uv add torch`
tnrx uvslurm python deep_check_jax.py    # JAX, inclusive uma convolução (cuDNN): precisa de `tnrx uv add "jax[cuda12]"`
```

## Jupyter

Uma vez por projeto, instale o Jupyter no `.venv` (a imagem não traz Jupyter):

```bash
tnrx uv add jupyterlab ipykernel
```

**Do laptop**, o caminho mais simples é o `tnrx-connect jupyter`: ele inicia o Jupyter no servidor, espera o job subir e abre a ponte até o seu navegador ou VS Code, com uma URL que não muda. Veja [tnrx-connect.md](tnrx-connect.md#jupyter).

**No servidor**, à mão:

```bash
tnrx uvslurm jupyter lab
```

Quando o comando contém `jupyter`, o `tnrx`:

* registra o kernel `Python (TNRX-<pasta do projeto>)`, que usa o `.venv` do projeto;
* escolhe a primeira porta livre a partir de 8888 no nó e imprime `🌐 [tnrx] Nó: dl-05 | porta: 8888`;
* passa ao Jupyter `--ip=0.0.0.0 --no-browser` e a URL certa (`http://<nó>:<porta>`);
* usa como senha (token) a senha fixa do projeto, que o `tnrx-connect` grava em `.tnrx/jupyter/token`. Sem esse arquivo, gera uma senha aleatória;
* quando o Jupyter começa a responder, grava `.tnrx/jupyter/<job>.env` (nó, porta, senha, job), que é como o `tnrx-connect` descobre os Jupyters no ar.

Rode na **raiz do projeto**, porque o registro fica na pasta onde o comando foi rodado. Para começar por outra porta: `TNRX_JUPYTER_PORT=9000 tnrx uvslurm jupyter lab`. Um `--port` na linha de comando é ignorado. Se o Jupyter demorar mais de 3 minutos para responder, o registro não é gravado (ajuste com `TNRX_JUPYTER_REGISTER_SECS`).

O endereço `http://dl-05:8888` só abre de dentro da rede do cluster. Do laptop, a ponte é o [`tnrx-connect jupyter`](tnrx-connect.md#jupyter).

## Hugging Face

O `tnrx hf` baixa modelos e datasets para uma pasta **compartilhada** do servidor, para não repetir downloads nem ocupar o `/home`:

```bash
tnrx hf model google/siglip2-base-patch16-224
tnrx hf dataset jxie/flickr8k
```

| Servidor | Pasta (`HUB_ROOT`) |
| --- | --- |
| Abaporu | `/data/huggingface_hub` |
| Headnode | `/hadatasets/huggingface_hub` |

Os arquivos vão para `<HUB_ROOT>/models/<autor>/<repo>` ou `<HUB_ROOT>/datasets/<autor>/<repo>`. A pasta compartilhada é montada no container em todos os comandos, então o código carrega pelo caminho absoluto:

```python
from transformers import AutoModel

model = AutoModel.from_pretrained("/data/huggingface_hub/models/google/siglip2-base-patch16-224")
```

Antes do primeiro download:

1. Instale o `download_huggingface` (ele está na [instalação](#instalação)).
2. Crie um token de leitura no Hugging Face (*Settings → Access Tokens*) e coloque-o no `~/.bashrc` do servidor: `export HF_TOKEN="hf_..."`. Depois rode `source ~/.bashrc` ou abra um terminal novo.
3. O download roda com o `.venv` do projeto atual, que precisa ter o `huggingface-hub`: `tnrx uv add huggingface-hub`.

O `tnrx` confere o token antes de baixar e o repassa ao container sem expô-lo na linha de comando. Para conferir um modelo baixado: `tnrx uv add transformers torch` e `tnrx uvslurm python load_model.py <caminho do modelo>`.

## Servidores (`tnrx_hosts.conf`)

O que muda de um servidor para outro fica em [`tnrx_hosts.conf`](../tnrx_hosts.conf), na pasta do repositório:

```
# HOSTNAME | BIND_PATH | RUNTIME | HUB_ROOT
abaporu|/data/:/data/|singularity|/data/huggingface_hub
ssh|/hadatasets/:/hadatasets/|apptainer|/hadatasets/huggingface_hub
headnode|/hadatasets/:/hadatasets/|apptainer|/hadatasets/huggingface_hub
```

| Campo | O que é |
| --- | --- |
| `HOSTNAME` | A saída do comando `hostname` no servidor. Nem sempre é o nome que você usa no `ssh`: o Headnode responde `ssh` |
| `BIND_PATH` | A pasta de dados montada no container, no formato `host:container` |
| `RUNTIME` | O programa do container: `singularity` ou `apptainer` |
| `HUB_ROOT` | A pasta do Hugging Face, vista de dentro do container. Precisa estar dentro do `BIND_PATH` |

Para usar o `tnrx` num servidor novo, basta acrescentar uma linha. Se o `RUNTIME` não existir na máquina, o `tnrx` recusa com uma mensagem.

## Referência de comandos

| Comando | O que faz |
| --- | --- |
| `tnrx update [--choose]` | Atualiza a partir do GitHub; `--choose` pergunta de novo o que instalar |
| `tnrx update-dev [pasta]` | Instala a sua cópia de desenvolvimento ([detalhes](desenvolvimento.md#instalar-a-sua-cópia)) |
| `tnrx version` | Versão instalada |
| `tnrx uninstall` | Remove os comandos e a pasta da instalação |
| `tnrx install` | Prepara o servidor: o `uv` e a imagem padrão (o instalador já roda isto) |
| `tnrx install uv` | Instala o `uv` em `~/.local/bin` |
| `tnrx install singularity [origem] [--force]` | Grava o `IMAGE` no `tnrx.conf` e baixa ou gera a imagem ([detalhes](#a-imagem-do-container)) |
| `tnrx uv {add\|remove\|sync\|init\|lock\|tree\|export} ...` | O `uv` no container, no headnode |
| `tnrx uvslurm <comando>` | `uv run --frozen <comando>` num nó de GPU |
| `tnrx slurm [comando]` | O comando num nó de GPU, sem o `.venv`. Sem comando (ou `bash`): shell interativo |
| `tnrx hf {model\|dataset} <autor/repo>` | Baixa do Hugging Face para o `HUB_ROOT` |
| `tnrx uninstall` | Remove os links de `~/.local/bin` |
| `tnrx --debug <comando>` | Mostra o comando real (`srun`, `apptainer`...) antes de rodá-lo. `-x` é o mesmo |

## Problemas comuns

| Mensagem ou sintoma | Causa | O que fazer |
| --- | --- | --- |
| `Hostname '...' não está configurado` | O servidor não está em `tnrx_hosts.conf` | Acrescente uma linha ([detalhes](#servidores-tnrx_hostsconf)) |
| `'apptainer' não foi encontrado nesta máquina` | Você está num nó sem o runtime do container | Rode o `tnrx` no nó de login certo do servidor |
| `IMAGE=... (no tnrx.conf) não existe` | O `IMAGE` aponta para um `.sif` ou `.def` que não está lá | Corrija o caminho, ou apague a linha para usar o padrão |
| `Ignorando ... aponta para uma imagem que não existe mais` | Sobrou um link de uma versão anterior do `tnrx` | Pode apagar o link; o `tnrx` já segue sem ele |
| `Mais de um .sif encontrado` | Sobraram imagens antigas na pasta, e o `tnrx.conf` não tem `IMAGE` | Apague as que não usa, ou escolha com `IMAGE` |
| `tnrx_slurm.conf agora se chama tnrx.conf` | O projeto ainda usa o nome antigo | `mv tnrx_slurm.conf tnrx.conf` |
| `No interpreter found` ou erro de Python no `tnrx uv` | O `uv` não pôde baixar o Python | Confira se `UV_PYTHON_DOWNLOADS` não está como `never` no seu ambiente |
| `ModuleNotFoundError` no `tnrx uvslurm` | A biblioteca não está no `.venv` | `tnrx uv add <biblioteca>` |
| `jupyter: command not found` | O Jupyter não está no `.venv` | `tnrx uv add jupyterlab ipykernel` |
| Erro de rede ou de download no `tnrx uvslurm` | O `.venv` não está em dia com o `uv.lock`, e o nó não tem internet | `tnrx uv sync` no headnode e rode de novo |
| O job não sai da fila | Faltam recursos na partição | `squeue -u $USER`; mude `PARTITION` ou `GPUS` no `tnrx.conf` |
| O build do `tnrx.def` falha falando de fakeroot | O servidor não permite build sem root | Gere o `.sif` em outra máquina ([detalhes](#customizar-a-imagem-tnrxdef)) |
| `HF_TOKEN inválido ou expirado` | Token errado ou revogado | Crie outro no Hugging Face e atualize o `~/.bashrc` |
