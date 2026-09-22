# `tnrx-connect`: trabalhar no seu laptop com o projeto no servidor

> **Onde roda:** no **seu laptop/desktop/notebook**, não no servidor. O `tnrx-connect` é o companion do [`tnrx`](tnrx.md) (que roda no servidor). Visão geral das duas ferramentas: [README](../README.md).

Este manual é para você conseguir trabalhar **só lendo este arquivo**: primeiro como começar, depois **como fazer cada tarefa do dia a dia** (inclusive os comandos do `tnrx` que você roda no servidor), depois a referência completa e os problemas comuns. Quando precisar de mais detalhe sobre o `tnrx`, cada tarefa tem o link para a seção dele.

## Por que existe

Os nós de computação do Slurm não têm acesso à internet, e ferramentas como o Claude Code precisam de internet o tempo todo, então elas não podem rodar lá. Rodar essas ferramentas direto no headnode também não é uma boa ideia: é uma máquina compartilhada por todo o time, e um agente de coding facilmente a sobrecarrega. Um proxy de rede pelo headnode resolveria o problema tecnicamente, mas reabriria de propósito o isolamento de rede que os nós têm por motivo de segurança, e essa não é uma decisão para tomar dentro de um script.

A solução é rodar a ferramenta no **seu laptop** (com internet plena) e deixar os arquivos do projeto no servidor. O `tnrx-connect` faz essa ponte, roda só no laptop e **não exige instalar nada no servidor** (usa `ssh` e o subsistema SFTP do `sshd`). Ele tem dois modos:

* **Modo mount (recomendado):** monta a pasta do projeto do servidor, via `rclone`, na pasta onde você rodou o comando. Só existe **uma cópia** dos arquivos (no servidor), então não há duas versões para divergir: editar no laptop ou no servidor é editar o mesmo arquivo.
* **Modo rsync (alternativo):** mantém uma cópia local sincronizada com o servidor, só de ida (laptop → servidor). Veja [Modo alternativo: rsync](#modo-alternativo-rsync).

## Quem roda o quê

Você usa **duas abas de terminal** no laptop, mais o navegador:

| Onde | O que roda lá |
| --- | --- |
| **Aba 1 do laptop** (a que rodou `tnrx-connect`) | Vira o **terminal do servidor**: é aqui que você roda os comandos `tnrx ...` (instalar bibliotecas, submeter jobs, iniciar o Jupyter, baixar modelos, fazer commit) |
| **Aba 2 do laptop** | Editor e Claude Code na pasta montada, e os comandos do próprio `tnrx-connect` (`jupyter`, `refresh`, `history`, `restore`) |
| **Navegador / VS Code** | O Jupyter, por uma ponte que o `tnrx-connect jupyter` abre |

A regra prática: **`tnrx ...` é sempre no terminal do servidor (aba 1); `tnrx-connect ...` é sempre no laptop.**

## Primeiros passos

> **Status do modo mount:** ele já montou o Headnode com o `rclone` real e funciona. Ainda **não foram validados** num servidor real: senha/2FA pedidas uma única vez no Abaporu, escritas pendentes sobrevivendo a uma queda de rede, o desempenho de `git status`/buscas na pasta montada e o macOS. A lista de conferência está em [validacao-manual.md](validacao-manual.md).


### Pré-requisitos e instalação (no laptop)

* `ssh` (OpenSSH com `ControlMaster`), `rclone` e FUSE (`fuse3` no Linux; macFUSE no macOS, ainda não validado).
* SFTP habilitado no servidor (confira com `sftp <host>`).
* Uma cópia deste repositório **no laptop** (só o script `tnrx-connect` é usado lá; o restante do repositório é do [`tnrx`](tnrx.md), que roda no servidor). O `~/.local/bin` precisa estar no seu `PATH`.

Na pasta do repositório clonado no laptop:

```bash
chmod +x tnrx-connect
ln -sf "$(pwd)/tnrx-connect" ~/.local/bin/tnrx-connect
```

### Primeira sessão

Crie uma pasta **vazia** pro projeto, entre nela e rode:

```bash
mkdir -p ~/trabalho/meu-projeto && cd ~/trabalho/meu-projeto
tnrx-connect
```

```
Host (user@servidor ou alias do ~/.ssh/config) [abaporu]:
Pasta remota [/home/marcos/proj] (Enter = manter, b = navegar):
```

* **Toda execução pergunta de novo**, já com os valores da última vez: Enter aceita. Em `b` você navega pelas pastas do servidor (subir/descer) em vez de digitar o caminho.
* O **host** pode ser `usuario@servidor.edu` ou um alias do seu `~/.ssh/config` (inclusive com `ProxyJump`).
* Depois disso o comando autentica (senha/2FA uma única vez), monta o projeto em cima da pasta atual e **este terminal vira o terminal SSH do servidor** (já dentro da pasta do projeto).
* Em **outra aba local**: `cd ~/trabalho/meu-projeto && claude`. Todo terminal que já estava **dentro** dessa pasta antes de montar (inclusive aquele em que você rodou o `tnrx-connect`, depois de sair) continua vendo a pasta vazia de antes, porque o diretório de trabalho dele aponta para a pasta local sem o mount: rode `cd .` (ou reabra o terminal) pra enxergar o conteúdo montado.
* Ao sair do terminal SSH (`exit`/`Ctrl-D`), o comando tira um último snapshot, desmonta, espera o `rclone` terminar de enviar o que estava pendente e encerra a conexão.

## Tarefas do dia a dia

Cada receita diz **onde** rodar (aba 1 = terminal do servidor; aba 2 = laptop) e aponta para a seção do [`tnrx`](tnrx.md) com mais detalhes.

### Abrir o projeto (e o terminal do servidor)

No laptop, numa pasta **vazia**:

```bash
mkdir -p ~/trabalho/meu-projeto && cd ~/trabalho/meu-projeto
tnrx-connect
```

Aceite o host e a pasta remota com Enter (ou `b` para navegar pelas pastas do servidor). Depois de autenticar, este terminal vira o terminal do servidor, já dentro da pasta do projeto. Detalhes: [Primeira sessão](#primeira-sessão).

### Editar o código com o Claude Code ou o seu editor

Na **aba 2** do laptop:

```bash
cd ~/trabalho/meu-projeto
claude          # ou abra o seu editor nessa pasta
```

Os arquivos que você salva sobem para o servidor uns 5 segundos depois: o que você edita aqui é o que o `tnrx` roda lá. Se essa aba já estava aberta dentro da pasta antes de montar, rode `cd .` primeiro.

### Preparar um projeto novo no servidor (uma vez por projeto)

Na **aba 1**:

```bash
tnrx install uv               # instala o uv em ~/.local/bin
tnrx install singularity      # baixa o .sif (a imagem do container) para a pasta do projeto
```

O `.sif` precisa estar na pasta do projeto para qualquer comando `tnrx uv`/`tnrx uvslurm`. Mais em [tnrx.md, seção 1](tnrx.md#1-instalação-e-preparação). Se o `tnrx` recusar com `Hostname '...' não está configurado`, o servidor precisa de uma linha em `tnrx_hosts.conf`: [tnrx.md, seção 1.1](tnrx.md#11-particularidades-de-cada-servidor-tnrx_hostsconf).

### Instalar bibliotecas do projeto

Na **aba 1** (o `tnrx uv` usa a internet do headnode e cria o `.venv` no servidor):

```bash
tnrx uv add numpy pandas      # adiciona bibliotecas
tnrx uv remove pandas         # remove
tnrx uv sync                  # recria o ambiente a partir do uv.lock
```

O `.venv/` fica escondido do mount no laptop, e isso é normal. Mais em [tnrx.md, seção 2](tnrx.md#2-gestão-de-dependências-headnode).

### Rodar um script na GPU

Na **aba 1**:

```bash
tnrx uvslurm python train.py          # usa o ambiente do .venv (recomendado)
tnrx slurm nvidia-smi                 # para comandos genéricos, fora do uv
```

Partição, número de GPUs, CPUs, memória e tempo saem do arquivo `tnrx_slurm.conf` da pasta do projeto, que você pode editar no laptop (é um arquivo do projeto como outro qualquer):

```bash
PARTITION=l40s
GPUS=1
CPUS=4
MEM=16G
TIME=02:00:00
```

Para ver a fila ou cancelar um job (comandos do Slurm, na aba 1): `squeue -u $USER` e `scancel <jobid>`. Mais em [tnrx.md, seções 3 e 5](tnrx.md#3-configuração-do-cluster-tnrx_slurmconf) e [5](tnrx.md#5-execução-no-slurm).

### Abrir um Jupyter e usá-lo no navegador

1. **Uma vez por projeto**, na aba 1: `tnrx uv add ipykernel`.
2. Na **aba 1**, na pasta do projeto: `tnrx uvslurm jupyter lab`. Se o job ficar na fila, espere. Quando ele começar, aparece `🌐 [tnrx] Nó: dl-05 | porta: 8888` e os logs do Jupyter.
3. Na **aba 2** do laptop, dentro da pasta do projeto:

   ```bash
   tnrx-connect jupyter
   ```

   Ele acha o Jupyter que está no ar, abre a ponte e imprime o link (com o token já dentro):

   ```
   🌐 Abra no navegador:  http://dl-05.recod-headnode.localhost:8888/lab?token=...
      Programas que não resolvem *.localhost (ex.: VS Code): http://127.0.0.1:8888/lab?token=...
   ```

4. Abra o link no navegador. **No VS Code:** abra o `.ipynb`, clique em **Select Kernel → Existing Jupyter Server**, cole o link `127.0.0.1` e escolha o kernel `Python (TNRX-nome_da_pasta)`.
5. Para encerrar: na aba 1, `Ctrl-C` **duas vezes em menos de 1 segundo** (o `srun` pede isso). A ponte fecha sozinha. `Ctrl-C` na aba da ponte fecha só a ponte; o Jupyter continua no servidor.

Se aparecer `Nenhum servidor Jupyter no ar neste projeto`, veja [Problemas comuns](#problemas-comuns). Mais em [Jupyter no nó de computação](#jupyter-no-nó-de-computação) e [tnrx.md, seção 6](tnrx.md#6-jupyter-lab-e-vs-code).

### Baixar um modelo ou dataset do Hugging Face

Na **aba 1**, no headnode (os nós de computação não têm internet). Uma vez por usuário: instale o utilitário `download_huggingface` (o link simbólico da [seção 7-A do tnrx.md](tnrx.md#a-preparação-e-instalação-do-comando)) e configure o token no `~/.bashrc` do servidor (`export HF_TOKEN="hf_..."`). Depois:

```bash
tnrx hf model google/siglip1-base-patch16-224
tnrx hf dataset jxie/flickr8k
```

Os arquivos vão para o diretório compartilhado do servidor (`HUB_ROOT`: `/data/huggingface_hub` no Abaporu, `/hadatasets/huggingface_hub` no Headnode), e seu código os carrega por esse caminho absoluto. Mais em [tnrx.md, seção 7](tnrx.md#7-hugging-face-shared-hub-central-de-modelosdatasets).

### Ver no laptop o que o servidor gerou

Um resultado salvo por um job (ou um notebook salvo pelo Jupyter) só aparece no laptop quando o cache de diretórios expira (30 s). Para ver na hora, na aba 2:

```bash
tnrx-connect refresh
```

Resultados de treino e logs grandes devem ir para o storage compartilhado (`/data`, `/hadatasets`), não para dentro da pasta do projeto.

### Voltar atrás depois de uma edição errada

Na aba 2. O `tnrx-connect` tira snapshots automáticos enquanto a sessão está aberta:

```bash
tnrx-connect history                    # lista os snapshots, o mais recente primeiro
tnrx-connect restore <id> arquivo.py    # restaura um arquivo
tnrx-connect restore <id>               # restaura a árvore toda
```

Mais em [Snapshots e rollback](#snapshots-e-rollback-git-sombra).

### Fazer commit

Faça `git add` e `git commit` na **aba 1** (o terminal do servidor), não pela pasta montada: o pre-commit deste projeto usa o `./tnrx` do servidor, e o `git status` sobre o mount pode ser lento. Mais em [tnrx.md, seção 8](tnrx.md#8-qualidade-de-código-e-pre-commit).

### Encerrar o dia e voltar amanhã

Na aba 1, `exit` (ou `Ctrl-D`): o comando tira um último snapshot, desmonta, espera o `rclone` terminar de enviar o que estava pendente e fecha a conexão. Se a desmontagem falhar porque algo ainda usa a pasta (o Claude Code, um editor, um shell dentro dela), feche esses programas, saia da pasta (`cd ~`) e rode `tnrx-connect unmount ~/trabalho/meu-projeto`.

Para voltar: `cd ~/trabalho/meu-projeto && tnrx-connect`, e Enter nas duas perguntas (o cache é persistente).


## Referência do modo mount

### Onde ficam as coisas

| Caminho | Conteúdo | Persiste? |
| --- | --- | --- |
| `~/.config/tnrx-connect/<host>_<pasta>.conf` | `HOST`, `REMOTE_PATH`, `LOCAL_DIR` (a pasta local usada), `LAST_USED` | Sim |
| `~/.local/share/tnrx-connect/<host>_<pasta>/vfs-*/` | Cache do `rclone` | **Sim — nunca é apagado automaticamente** |
| `~/.local/share/tnrx-connect/<host>_<pasta>/shadow.git` | Snapshots (git sombra) | Sim |
| `~/.local/share/tnrx-connect/<host>_<pasta>/mount.log` | Log do `rclone` e dos snapshots | Sim |
| `~/.local/share/tnrx-connect/locks/` | Lock da sessão ativa por pasta | Só enquanto a sessão existe |

O nome do `.conf` usa o nome da pasta local. Se duas pastas de caminhos diferentes tiverem o mesmo nome (`~/a/proj` e `~/b/proj`) com o mesmo host, a segunda ganha um sufixo curto de hash pra não colidir. Se uma pasta já foi usada com mais de um host, o comando lista as opções (a mais recente primeiro) e pergunta qual usar.

### Regras

* **A pasta precisa estar vazia** (o mount esconderia qualquer conteúdo local). Por isso a configuração fica em `~/.config`, e não dentro do projeto. O comando também recusa rodar em `/` e na sua home.
* **Uma sessão por pasta:** se já houver uma sessão ativa naquela pasta, o comando recusa e mostra host, pasta remota, PID e desde quando. Esse bloqueio é **local** (desta máquina): não impede outra pessoa, em outro laptop, de montar o mesmo `REMOTE_PATH`. Se a mesma pasta remota já estiver montada em outra pasta desta máquina, ele só avisa.
* **Sessão que caiu** (`kill -9`, queda de energia): na próxima execução naquela pasta o comando detecta o lock velho, desmonta o que sobrou e espera o `rclone` antigo terminar antes de remontar.
* **O cache é persistente.** Ele guarda leituras e escritas em disco; se a conexão cair, o que ainda não subiu continua no cache. O único limite é `CACHE_MAX_SIZE` (padrão `20G`) — o `rclone` só descarta arquivos quando passa disso.
* O `.venv/` fica escondido do mount (evita varrer diretórios enormes); ele continua existindo normalmente no servidor.

### Senha + 2FA (ex.: Abaporu)

Se o host exige senha e segundo fator, o comando pede isso **uma única vez**: ele abre uma conexão SSH "mestra" (multiplexada) e tudo depois — o mount, cada operação de listagem/leitura/escrita do `rclone` e o terminal interativo — reaproveita essa conexão já autenticada. Ela é compartilhada entre sessões do mesmo host e só é encerrada quando a última sessão termina.

### Atualização e atraso de visibilidade

O SFTP não avisa quando algo muda no servidor. Por isso:

* O que **mudou no servidor** (um notebook salvo pelo Jupyter, o resultado de um job) só aparece no laptop quando o cache de diretórios expira (`DIR_CACHE_TIME`, padrão `30s`). Pra ver na hora: `tnrx-connect refresh`.
* O que **você salva no laptop** vai primeiro pro cache local e sobe ao servidor uns 5 segundos depois. Um processo no servidor que leia o arquivo nesse intervalo ainda vê a versão antiga.
* Se o **mesmo arquivo** for salvo ao mesmo tempo por você (via mount) e por outro processo (por exemplo o autosave do Jupyter no mesmo notebook), vale a última escrita — o `rclone` não faz merge. Na prática, mantenha um escritor por arquivo.

### Snapshots e rollback (git sombra)

Enquanto a sessão está aberta, um repositório git **separado** tira snapshots da pasta montada a cada `SNAPSHOT_INTERVAL` segundos (padrão `60`), só quando algo mudou. Ele fica em `~/.local/share/tnrx-connect/<host>_<pasta>/shadow.git`, **fora do projeto**, então não interfere no `.git` original (que continua no servidor, dentro do projeto).

```bash
tnrx-connect history                    # lista os snapshots (mais recente primeiro)
tnrx-connect restore <id> arquivo.py    # restaura um arquivo
tnrx-connect restore <id>               # restaura a árvore toda
```

* Respeita o `.gitignore` do projeto e as regras do `.git/info/exclude` dele.
* Arquivos maiores que `SNAPSHOT_MAX_FILE_MB` (padrão `5`) ficam de fora — importante pra dados e pesos. Notebooks com muitas saídas engordam o repositório sombra (o `git gc` automático ajuda).
* O primeiro snapshot só sai depois do primeiro intervalo, e lê os arquivos pelo mount (baixando-os pro cache), então pode ser lento em projetos grandes.
* `restore` tira um snapshot de segurança **antes** de restaurar (o próprio restore é desfazível) e **não apaga** arquivos criados depois do snapshot escolhido. Se o arquivo estiver aberto no Jupyter, o autosave dele pode sobrescrever o restaurado.
* Nunca tira snapshot com a pasta desmontada (senão gravaria "todos os arquivos apagados"), e ignora um snapshot em que mais da metade dos arquivos sumiu de uma vez (mount instável).
* O repositório sombra vive no laptop: se o laptop for perdido, o histórico vai junto (os arquivos continuam no servidor).

### Comandos

| Comando | O que faz |
| --- | --- |
| `tnrx-connect` | Pergunta host/pasta remota, monta na pasta atual e abre o terminal SSH |
| `tnrx-connect status [pasta]` | Sessão, mount, cache (tamanho) e snapshots |
| `tnrx-connect refresh` | Limpa o cache de diretórios (vê o que mudou no servidor agora) |
| `tnrx-connect history [caminho]` | Lista os snapshots |
| `tnrx-connect restore <id> [caminho ...]` | Restaura arquivos de um snapshot |
| `tnrx-connect snapshot` | Tira um snapshot agora |
| `tnrx-connect unmount [-f] [pasta]` | Desmonta um mount que ficou órfão (sessão que caiu). `-f` = desmontagem preguiçosa |
| `tnrx-connect jupyter` | Acha os Jupyters do projeto que estão no ar, você escolhe e ele abre a ponte (veja [Jupyter](#jupyter-no-nó-de-computação)) |
| `tnrx-connect jupyter <URL\|nó:porta>` | Abre a ponte para um Jupyter cuja URL você já tem |

### Jupyter no nó de computação

O mount só traz **arquivos**. O Jupyter roda num nó de computação (ex.: `dl-05`), e o endereço `http://dl-05:8888` só é alcançável de dentro da rede do cluster. O `tnrx-connect jupyter` abre uma **ponte** (túnel SSH) do seu laptop até esse nó, pela mesma conexão já autenticada (sem novo 2FA). Ele não inicia nada no servidor: **você inicia o Jupyter no servidor, e o `tnrx-connect` só descobre qual está no ar e conecta**, sem você precisar copiar nó, porta e token.

**Como ele descobre:** quando o Jupyter sobe, o `tnrx` do servidor grava `.tnrx/jupyter/<job>.env` na pasta do projeto (com nó, porta, token, job e horário). O registro só é gravado **depois que a porta responde**, então se o arquivo existe, o Jupyter estava no ar. O `tnrx-connect jupyter` lê esses arquivos pela conexão SSH, testa a partir do servidor se cada `nó:porta` ainda responde e ignora os que não respondem (os parados há mais de um dia são apagados).

```bash
tnrx-connect jupyter
```

* Dentro da pasta montada (ou de uma subpasta dela) ele usa o host e a pasta remota da sessão e **não pergunta nada**. Fora dela, pergunta o host e a pasta do projeto.
* **Nenhum servidor no ar:** só avisa (`Nenhum servidor Jupyter no ar neste projeto`) e sai.
* **Um servidor:** conecta direto. **Vários:** mostra um menu, o mais recente primeiro, com `nó:porta`, job e há quanto tempo está no ar:

  ```
  Servidores Jupyter no ar (mais recente primeiro):
    [1] dl-05:8888  (job 95272, há 3 min)
    [2] dl-02:8889  (job 95190, há 2 h)
  Conectar em qual [1]:
  ```

* **A ponte fica ativa enquanto o Jupyter estiver no ar.** Se ele terminar (ou a conexão SSH cair), o comando avisa e sai. `Ctrl-C` fecha só a ponte; o Jupyter continua no servidor.
* **Porta local:** ele tenta usar o **mesmo número** da porta do servidor (o `tnrx` já escolhe uma porta livre lá). Se essa porta já estiver em uso no laptop (por outra ponte ou outro programa), usa a próxima livre e avisa. Assim duas pontes com a mesma porta remota não conflitam.
* **O nome `nó.host.localhost` é só um rótulo.** Navegadores resolvem qualquer `*.localhost` para o seu próprio computador, então ele não muda para onde a ponte vai. Vale porque servidores Jupyter diferentes em `localhost` compartilham cookies (o `_xsrf`) e se atrapalham; com nomes diferentes, não. Se o navegador não abrir esse nome, use o link `127.0.0.1`.
* Se a conexão mestra do host ainda não existir, o comando autentica (senha/2FA) e a fecha ao sair. Se ela veio de uma sessão do `tnrx-connect` aberta, reaproveita e não a fecha.

**Requisitos e cuidados:**

* O `tnrx` do servidor precisa estar **atualizado** (`git pull` lá): é ele que gera o token e grava o registro.
* Inicie o Jupyter **na raiz do projeto**: o registro fica na pasta onde você rodou `tnrx uvslurm jupyter lab`.
* O registro tem o **token** do Jupyter. O arquivo tem permissão 600 e a pasta `.tnrx/` tem um `.gitignore` próprio que ignora tudo, então ele não vai para um `git add .`. Ele aparece na pasta montada do laptop, então um programa local que leia a pasta (como o Claude Code) pode vê-lo: o token só dá acesso àquele Jupyter no cluster.
* Se o Jupyter demorar mais de 3 minutos para responder, o registro não é gravado (ajustável com `TNRX_JUPYTER_REGISTER_SECS` ao iniciar). Nesse caso, use a forma manual abaixo.

**Se você já tem a URL (forma manual):** `tnrx-connect jupyter <URL|nó:porta>` abre a ponte sem consultar o servidor. Aceita a URL que o Jupyter imprimiu (`http://dl-05:8888/lab?token=...`), `dl-05:8888`, `dl-05 8888` ou só `dl-05` (porta 8888). Se você passar a URL `127.0.0.1`, ele pergunta o nome do nó. Serve para um `tnrx` antigo, que não grava o registro.

### Configuração opcional

Adicione linhas ao `.conf` da pasta (elas são preservadas a cada execução):

```bash
CACHE_MAX_SIZE=50G          # limite do cache em disco (padrão: 20G)
DIR_CACHE_TIME=10s          # por quanto tempo confia na listagem de pastas (padrão: 30s)
SNAPSHOT_INTERVAL=30        # segundos entre snapshots (padrão: 60)
SNAPSHOT_MAX_FILE_MB=10     # ignora arquivos maiores que isso nos snapshots (padrão: 5)
```

### Cuidados

* **Desmontagem ocupada:** se algo ainda usa a pasta (o Claude Code, um editor, um shell dentro dela), a desmontagem falha, a montagem **continua ativa** e nada é perdido. Feche o que usa a pasta, saia dela (`cd ~`) e rode `tnrx-connect unmount <pasta>`.
* **`rclone` ainda enviando escritas:** ao sair, o comando espera o `rclone` terminar (até 2 minutos) e não o mata. Se passar disso, as escritas pendentes ficam no cache e são retomadas na próxima montagem.
* **Commits:** o pre-commit deste projeto depende do `./tnrx` no servidor, então faça `git add`/`git commit` pelo terminal SSH que o comando abriu, não pela pasta montada no laptop. O `git status` sobre o mount também pode ser lento.
* **Rede caiu no meio da sessão:** a conexão mestra cai junto. Feche, rode `tnrx-connect` de novo (vai pedir senha/2FA de novo, é esperado) e ele recupera a sessão anterior.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| A pasta montada aparece **vazia** | O terminal já estava dentro da pasta antes de montar | `cd .` ou reabra o terminal |
| `... não está vazia` ao rodar `tnrx-connect` | O mount é feito **por cima** da pasta local e esconderia o conteúdo dela | Rode numa pasta vazia (`mkdir` uma nova) ou mova o conteúdo local; o que está no servidor pode ter arquivos à vontade |
| `Já existe uma sessão do tnrx-connect ativa nesta pasta` | Outra sessão viva usa essa pasta | Use a aba dela, ou saia dela; se ela caiu, rode de novo (o lock velho é recuperado) |
| Pede senha/2FA de novo | A conexão mestra caiu (rede) | É esperado: autentique de novo e rode `tnrx-connect` |
| `Nenhum servidor Jupyter no ar neste projeto` | O Jupyter não está rodando, ainda está na fila, foi iniciado em **outra pasta**, ou o `tnrx` do servidor está desatualizado | Na aba 1, na raiz do projeto: `tnrx uvslurm jupyter lab` e espere subir; `git pull` no servidor; confira com `squeue -u $USER` |
| O navegador mostra `Connection refused` | O Jupyter terminou ou o nó/porta mudou | Rode `tnrx-connect jupyter` de novo (ele lista só o que responde) |
| O navegador não abre `nó.host.localhost` | O navegador ou o sistema não resolve `*.localhost` | Use o link `127.0.0.1` |
| `Hostname '...' não está configurado` (do `tnrx`) | O servidor não está em `tnrx_hosts.conf` | Adicione uma linha: [tnrx.md, seção 1.1](tnrx.md#11-particularidades-de-cada-servidor-tnrx_hostsconf) |
| `Nenhum arquivo .sif encontrado` (do `tnrx`) | Falta a imagem do container na pasta | `tnrx install singularity` |
| `'apptainer'/'singularity' não foi encontrado nesta máquina` (do `tnrx`) | Você está numa máquina sem o runtime (ex.: o nó `ssh`, só de acesso) | Rode o `tnrx` no nó certo do servidor |
| Salvei no laptop e o servidor ainda vê a versão antiga | O arquivo sobe uns 5 s depois de salvo | Espere alguns segundos antes de submeter o job |
| O job não sai da fila | Faltam recursos na partição | `squeue -u $USER`; ajuste `PARTITION`/`GPUS` no `tnrx_slurm.conf` |
| A desmontagem falha ao sair (`Ainda em uso`) | Algo ainda usa a pasta | Feche o editor/Claude Code, `cd ~`, e `tnrx-connect unmount <pasta>` |

## Modo alternativo: rsync

Use se o mount não funcionar no seu ambiente ou se você prefere ter uma **cópia local** do projeto. Aqui a sincronização é **só de ida** (laptop → servidor): o laptop é a fonte da verdade, então editar direto no servidor pode ser sobrescrito no próximo envio.

```bash
tnrx-connect init    # cria o .tnrx_connect deste projeto (HOST + navegação de pastas pro REMOTE_PATH)
tnrx-connect rsync   # sincroniza em background e abre o terminal SSH
```

`.tnrx_connect` (na raiz do projeto, no `.gitignore`) segue o formato do template `.tnrx_connect.example`:

```bash
HOST=abaporu                                       # alvo SSH (user@servidor ou alias do ~/.ssh/config)
REMOTE_PATH=/home/seu_usuario/projetos/seu_projeto # caminho absoluto no servidor
# SYNC_DELETE=true    # espelha deleções locais no servidor (padrão: true)
# POLL_INTERVAL=3     # segundos entre sincronizações (padrão: 3)
```

| Comando | O que faz |
| --- | --- |
| `tnrx-connect rsync` | Sincroniza uma vez e abre o terminal SSH, mantendo o sync ativo em background enquanto a sessão estiver aberta |
| `tnrx-connect sync` | Sincroniza uma vez (local → remoto), sem abrir SSH — útil antes de um `tnrx slurm`/`tnrx uvslurm` pontual |
| `tnrx-connect pull` | Puxa do servidor pro local uma vez, sem apagar nada local |
| `tnrx-connect init` | Cria o `.tnrx_connect` interativamente |
| `tnrx-connect uninstall` | Remove o symlink local |

**Enquanto o terminal do `tnrx-connect rsync` estiver aberto, a sincronização roda sozinha, continuamente, em background** (um loop de `rsync` a cada `POLL_INTERVAL` segundos; não é instantâneo, mas o `rsync` faz diff incremental, então cada rodada é barata). Ao sair da sessão, o loop é encerrado automaticamente. Outros detalhes:

* Usa o **`.gitignore` do projeto** como lista de exclusão do `rsync` — `.venv/`, `*.sif`, `slurm-*.out` etc. nunca são enviados nem apagados no servidor.
* **`--delete` vem ligado** (`SYNC_DELETE=true`): arquivos apagados localmente somem do servidor no próximo envio. Um arquivo criado manualmente no servidor, dentro do projeto e fora do `.gitignore`, pode ser apagado — desative com `SYNC_DELETE=false`.
* **Senha + 2FA:** mesma conexão mestra do modo mount — autentica uma vez. `sync`/`pull` usados sozinhos pedem senha/2FA a cada chamada, a menos que já exista uma sessão aberta pro mesmo host (aí reaproveitam).
* Resultados de treino/logs devem ir pro storage compartilhado já montado (`/data`/`/hadatasets`, o mesmo `HUB_ROOT` do `tnrx hf`), não pra dentro do diretório do projeto.
* Editou e disparou um job em seguida? O polling pode não ter processado ainda: rode `tnrx-connect sync` antes de um `tnrx slurm`/`tnrx uvslurm` pontual.
