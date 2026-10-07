# `tnrx-connect`: o projeto do servidor no seu laptop

> **Onde roda:** no seu laptop. Ele leva você até o [`tnrx`](tnrx.md), que roda no servidor. Visão geral: [README](../README.md).

O `tnrx-connect` monta a pasta de um projeto do servidor numa pasta do laptop. Você edita no laptop, com o seu editor ou o Claude Code, e roda no servidor, com o `tnrx`. Só existe uma cópia dos arquivos, a do servidor: o que você salva no laptop é o que o job usa.

Ele não precisa de nada instalado no servidor: usa só `ssh` e SFTP. A senha e o 2FA são pedidos uma vez por sessão.

## Como funciona

| Peça | O que é | Comando |
| --- | --- | --- |
| **Montagem** | A pasta remota aparece numa pasta local, via `rclone`. Fica montada até você desmontar, mesmo que feche todos os terminais | `tnrx-connect mount` / `umount` |
| **Terminal do servidor** | Um `ssh` aberto direto na pasta remota do projeto. É nele que você roda o `tnrx` | `tnrx-connect ssh` |
| **Ponte do Jupyter** | Um túnel do laptop até o nó de GPU onde o Jupyter roda | `tnrx-connect jupyter` |
| **Snapshots** | Cópias automáticas da pasta a cada minuto, num git separado no laptop, para desfazer edições | `tnrx-connect history` / `restore` |
| **Conexão mestra** | Uma única conexão SSH autenticada, que todas as peças acima reaproveitam. É por isso que o 2FA é pedido uma vez só | (automática) |

A regra prática: **`tnrx ...` roda no terminal do servidor; `tnrx-connect ...` roda no laptop.**

Um dia normal usa duas abas no laptop:

| Aba | O que roda |
| --- | --- |
| **Terminal do servidor** (`tnrx-connect ssh`) | `tnrx uv add`, `tnrx uvslurm`, `squeue`, `git commit` |
| **Laptop**, na pasta montada | O editor, o Claude Code e os comandos `tnrx-connect` (`jupyter`, `refresh`, `history`, `umount`) |

Se você usa o VS Code, a [extensão](../vscode/README.md) mostra numa barra lateral as montagens, a configuração do Slurm, as GPUs livres e os Jupyters, e abre os terminais por você.

## Instalação

No laptop você precisa de:

* `ssh` (OpenSSH), `rclone` e FUSE (`fuse3` no Linux). O macOS ainda não é suportado.
* Acesso SFTP ao servidor (confira com `sftp <servidor>`).
* `git` e `~/.local/bin` no `PATH`.

```bash
curl -fsSL https://raw.githubusercontent.com/recod-ai/tnrx/main/install.sh | bash
```

Ele pergunta o que instalar e, num laptop, já sugere o `tnrx-connect` e, se o comando `code` existir, a [extensão do VS Code](../vscode/README.md). Para atualizar: `tnrx-connect update`; versão instalada: `tnrx-connect version`. O instalador é o mesmo do servidor ([detalhes](tnrx.md#instalação)), e no servidor o `tnrx` também precisa estar instalado.

**Dica:** um alias no `~/.ssh/config` do laptop evita digitar usuário e endereço, e funciona com `ProxyJump`:

```
Host recod-headnode
    HostName <endereço do servidor>
    User <seu usuário>
```

## Primeira sessão

Numa pasta **vazia** do laptop:

```bash
mkdir -p ~/trabalho/meu-projeto && cd ~/trabalho/meu-projeto
tnrx-connect
```

```
Host (user@servidor ou alias do ~/.ssh/config) [recod-headnode]:
Pasta remota [/home/marcos/meu-projeto] (Enter = manter, b = navegar):
```

* O host é um alias do `~/.ssh/config` ou `usuario@servidor`. Na pasta remota, `b` deixa você navegar pelas pastas do servidor em vez de digitar o caminho.
* Ele pede a senha e o 2FA, monta a pasta e abre o terminal do servidor já na pasta do projeto.
* Nas próximas vezes, as perguntas já vêm com as respostas anteriores: é só apertar Enter.

Em **outra aba**, abra o editor ou o Claude Code:

```bash
cd ~/trabalho/meu-projeto
claude
```

Se a aba já estava dentro da pasta antes de montar, ela ainda vê a pasta vazia: rode `cd .` para enxergar o conteúdo montado.

Se o projeto é novo no servidor, prepare-o no terminal do servidor ([detalhes](tnrx.md#preparar-um-projeto)):

```bash
tnrx uv init            # só se ainda não existe um pyproject.toml
tnrx uv add torch       # na primeira vez, pergunta qual imagem do container usar (Enter = a padrão)
```

## Dia a dia

### Abrir o projeto

```bash
cd ~/trabalho/meu-projeto && tnrx-connect
```

Numa pasta já montada, ele não pergunta nada e só abre o terminal do servidor. Pode fechar e reabrir esse terminal quantas vezes quiser (`tnrx-connect ssh`): a pasta continua montada. Dentro de uma subpasta, o terminal abre na subpasta correspondente do servidor.

### Instalar bibliotecas e rodar na GPU

No terminal do servidor:

```bash
tnrx uv add numpy pandas
tnrx uvslurm python train.py
```

Os recursos do job (partição, GPUs, memória, tempo) vêm do `tnrx_slurm.conf` do projeto, que você edita no laptop como qualquer arquivo ([detalhes](tnrx.md#configurar-os-recursos-tnrx_slurmconf)). Para ver as GPUs livres e os seus jobs sem sair do laptop:

```bash
tnrx-connect cluster               # partições, GPUs livres e os seus jobs
tnrx-connect cluster cancel <job>  # cancela um job
```

O que você salva no laptop chega ao servidor uns **5 segundos** depois. Espere esse tempo antes de submeter um job que usa o arquivo recém-salvo.

### Ver no laptop o que o servidor gerou

Arquivos criados ou alterados no servidor (por um job, pelo Jupyter) aparecem no laptop em até **30 segundos**. Para ver na hora:

```bash
tnrx-connect refresh
```

Resultados grandes (checkpoints, logs de treino, datasets) devem ir para o armazenamento compartilhado (`/data`, `/hadatasets`), não para a pasta do projeto: assim não passam pelo cache do laptop nem pelos snapshots.

### Fazer commit

Faça o `git` no **terminal do servidor**. Pela pasta montada, o `git status` é lento (cada arquivo é consultado pela rede), e hooks de pre-commit que chamam o `tnrx` só funcionam no servidor.

### Desfazer uma edição

```bash
tnrx-connect history                    # snapshots, o mais recente primeiro
tnrx-connect restore <id> arquivo.py    # restaura um arquivo
tnrx-connect restore <id>               # restaura a pasta toda
```

Veja [Snapshots](#snapshots).

### Encerrar

Não é obrigatório desmontar: a pasta pode ficar montada por dias. Mas a conexão cai quando a rede cai ou o laptop hiberna, e aí é só [reconectar](#a-rede-caiu). Para desmontar, saia da pasta e rode:

```bash
cd ~ && tnrx-connect umount ~/trabalho/meu-projeto
```

Ele tira um último snapshot, desmonta, espera terminar o envio do que estava pendente e fecha a conexão. Se algo ainda usa a pasta (o editor, o Claude Code, um terminal dentro dela), ele recusa e a pasta continua montada: feche o que a usa e rode de novo, ou use `-f` para desmontar mesmo assim.

## Jupyter

O Jupyter roda num nó de GPU, que o laptop não alcança diretamente. O `tnrx-connect jupyter` abre uma ponte até ele pela conexão já autenticada.

Uma vez por projeto, no terminal do servidor: `tnrx uv add jupyterlab ipykernel`.

No laptop, dentro da pasta montada:

```bash
tnrx-connect jupyter
```

```
Servidores Jupyter no ar em recod-headnode (mais recente primeiro):
  [1] meu-projeto  dl-05:8888  (job 95272, há 3 min)  ← este projeto
  [2] outro        dl-02:8889  (job 95190, há 2 h)
  [n] Iniciar um novo Jupyter em meu-projeto (/home/marcos/meu-projeto)
Conectar em qual [1]:
```

* Ele lista os Jupyters no ar deste projeto e dos outros projetos do mesmo servidor que o laptop conhece.
* Com `n` (ou Enter, quando não há nenhum no ar), ele inicia o Jupyter no servidor (`tnrx uvslurm jupyter lab`), mostra se o job está na fila ou subindo, e conecta quando o Jupyter responde. `Ctrl-C` durante a espera cancela o job.
* Conectado, ele mostra o link:

  ```
  🌐 Abra no navegador:  http://dl-05.recod-headnode.localhost:18342/lab?token=...
     Programas que não resolvem *.localhost (ex.: VS Code): http://127.0.0.1:18342/lab?token=...
  📌 Esta URL é fixa para meu-projeto: no VS Code, configure uma vez (Existing Jupyter Server) e depois só escolha o servidor.
  ```

* Deixe essa aba aberta enquanto usa o Jupyter. `Ctrl-C` fecha só a ponte: o Jupyter continua no servidor e você reconecta depois com o mesmo comando. Para encerrar o Jupyter: `tnrx-connect cluster cancel <job>`.

**A URL é fixa por projeto.** A porta local (entre 18000 e 18999) e a senha são sempre as mesmas para o mesmo projeto, mesmo que o Jupyter caia em outro nó. Assim, o VS Code lembra do servidor:

1. Abra o `.ipynb` na pasta montada, clique em **Select Kernel → Existing Jupyter Server** e cole o link `127.0.0.1`.
2. Escolha o kernel `Python (TNRX-<pasta do projeto>)`.
3. Das próximas vezes, rode `tnrx-connect jupyter` e escolha no VS Code o servidor que ele já conhece.

Use o notebook **só no VS Code**, com o kernel remoto. Se o mesmo notebook também estiver aberto no navegador, o autosave do Jupyter e o editor disputam o arquivo, e vale a última gravação.

**Se você já tem a URL** (de um Jupyter iniciado à mão, por exemplo): `tnrx-connect jupyter <URL>` abre a ponte direto. Aceita a URL impressa pelo Jupyter, `dl-05:8888` ou só `dl-05`.

<details>
<summary>Como a descoberta, a senha e a porta funcionam</summary>

* **Descoberta:** quando o Jupyter começa a responder, o `tnrx` grava `.tnrx/jupyter/<job>.env` (nó, porta, senha, job) na pasta do projeto. O `tnrx-connect` lê esses registros e testa, a partir do servidor, se cada um ainda responde. Registros parados há mais de um dia são apagados. Por isso o Jupyter precisa ser iniciado na raiz do projeto.
* **Senha:** é derivada de um segredo aleatório do laptop (`~/.config/tnrx-connect/jupyter.secret`), do host e da pasta remota. O `tnrx-connect` a grava em `.tnrx/jupyter/token` no servidor (permissão 600, fora do git) ao montar e antes de iniciar um Jupyter, e o `tnrx` a usa, inclusive num Jupyter iniciado à mão. Para trocar as senhas de todos os projetos, apague o `jupyter.secret`.
* **Porta:** escolhida na primeira conexão e guardada no `.conf` do projeto como `JUPYTER_PORT`. Se estiver ocupada no laptop, ele usa outra só daquela vez e avisa.
* **O nome `nó.host.localhost`** é só um rótulo: o navegador resolve qualquer `*.localhost` para o próprio laptop. Ele existe porque Jupyters diferentes no mesmo `localhost` misturam os cookies. Se o navegador não abrir esse nome, use o link `127.0.0.1`.
* **Segurança:** a senha fica em arquivos 600 que aparecem na pasta montada, então programas locais que leem a pasta (como o Claude Code) podem vê-la. Ela só dá acesso aos Jupyters daquele projeto. No nó, ela também aparece na linha de comando do Jupyter, visível para outros usuários do mesmo nó enquanto o job roda.
* **A ponte fecha sozinha** quando o Jupyter termina (checado a cada ~30 s) ou quando a conexão cai.

</details>

## Snapshots

Enquanto a pasta está montada, o `tnrx-connect` tira um snapshot a cada minuto, se algo mudou. Os snapshots ficam num repositório git **separado**, no laptop (`~/.local/share/tnrx-connect/<id>/shadow.git`), e não mexem no `.git` do projeto.

* Seguem o `.gitignore` do projeto e ignoram arquivos maiores que 5 MB.
* O `restore` tira um snapshot antes de restaurar, então ele mesmo pode ser desfeito. Ele não apaga arquivos criados depois do snapshot escolhido.
* Nunca há snapshot com a pasta desmontada, e um snapshot em que mais da metade dos arquivos sumiu é descartado (sinal de montagem instável).
* O histórico vive só no laptop. Os arquivos em si continuam no servidor.

`tnrx-connect snapshot` tira um snapshot na hora.

## Referência

### Comandos

| Comando | O que faz |
| --- | --- |
| `tnrx-connect` | Monta, se ainda não estiver montada, e abre o terminal do servidor |
| `tnrx-connect mount` | Monta a pasta remota na pasta atual e devolve o prompt. Numa pasta já montada, só confere e reautentica se a conexão caiu |
| `tnrx-connect ssh` | Abre o terminal do servidor na pasta remota correspondente. Sair dele não desmonta |
| `tnrx-connect umount [-f] [pasta]` | Snapshot final, desmonta e fecha a conexão se nada mais a usa. `-f` desmonta mesmo com a pasta em uso |
| `tnrx-connect status [pasta]` | Montagem, conexão, cache e snapshots |
| `tnrx-connect refresh` | Mostra agora o que mudou no servidor |
| `tnrx-connect history [caminho]` | Lista os snapshots |
| `tnrx-connect restore <id> [caminho ...]` | Restaura arquivos de um snapshot |
| `tnrx-connect snapshot` | Tira um snapshot agora |
| `tnrx-connect jupyter` | Lista os Jupyters no ar, conecta ou inicia um novo |
| `tnrx-connect jupyter <URL\|nó:porta>` | Abre a ponte para um Jupyter conhecido |
| `tnrx-connect jupyter list` | Lista os Jupyters no ar, sem conectar |
| `tnrx-connect cluster [--host H]` | Partições, GPUs livres e os seus jobs nos servidores com pasta montada |
| `tnrx-connect cluster cancel <job>` | Cancela um job |
| `tnrx-connect --debug <comando>` | Mostra os comandos reais (`ssh`, `rclone`) antes de rodá-los |
| `tnrx-connect update` | Atualiza o `tnrx-connect` (e a extensão do VS Code) a partir do GitHub |
| `tnrx-connect version` | Versão instalada |
| `tnrx-connect uninstall` | Remove os comandos e a pasta da instalação |

Os comandos `status`, `cluster` e `jupyter` também têm saída `--json`, para ferramentas: [tnrx-connect-json.md](tnrx-connect-json.md).

### Onde ficam as coisas (no laptop)

| Caminho | Conteúdo |
| --- | --- |
| `~/.config/tnrx-connect/<id>.conf` | Configuração de cada pasta: host, pasta remota, pasta local, porta do Jupyter, opções |
| `~/.config/tnrx-connect/jupyter.secret` | Segredo das senhas fixas do Jupyter |
| `~/.local/share/tnrx-connect/<id>/vfs-*/` | Cache do `rclone`. **Nunca é apagado automaticamente** |
| `~/.local/share/tnrx-connect/<id>/shadow.git` | Snapshots |
| `~/.local/share/tnrx-connect/<id>/mount.log` | Log do `rclone` e dos snapshots |

O `<id>` é `<host>_<nome da pasta local>`. A configuração fica fora do projeto porque a pasta local precisa estar vazia para montar.

### Opções

Acrescente ao `.conf` da pasta (as linhas são preservadas):

```bash
CACHE_MAX_SIZE=50G          # limite do cache em disco (padrão: 20G)
DIR_CACHE_TIME=10s          # tempo até ver mudanças feitas no servidor (padrão: 30s)
SNAPSHOT_INTERVAL=30        # segundos entre snapshots (padrão: 60)
SNAPSHOT_MAX_FILE_MB=10     # tamanho máximo de arquivo nos snapshots (padrão: 5)
```

### Regras da montagem

* **A pasta local precisa estar vazia**, porque a montagem esconde o que estava nela. O comando também recusa `/` e a sua home.
* **Uma montagem por pasta.** Montar de novo uma pasta montada só confere a montagem. A trava é só deste laptop: outra pessoa pode montar a mesma pasta remota.
* **O `.venv/` não aparece no laptop**, para não varrer milhares de arquivos. Ele continua existindo no servidor.
* **Mesmo arquivo, dois escritores:** se o laptop e um processo no servidor salvam o mesmo arquivo ao mesmo tempo, vale a última gravação. Mantenha um escritor por arquivo.
* **Montagem que caiu** (laptop reiniciado, `rclone` encerrado): o próximo `tnrx-connect mount` percebe e remonta sozinho, mesmo com programas ainda abertos na pasta antiga. Nada se perde: o que não tinha sido enviado continua no cache e é enviado na nova montagem.
* **O cache é persistente:** guarda leituras e escritas em disco até `CACHE_MAX_SIZE`. Uma escrita que não subiu por causa de uma queda de rede sobe quando a conexão volta.

## Problemas comuns

### A rede caiu

Com a rede fora ou o laptop hibernado, a conexão mestra cai e a pasta para de sincronizar. O que você salva fica no cache. Na pasta, rode:

```bash
tnrx-connect mount
```

Ele pede a senha e o 2FA de novo, e a pasta volta a sincronizar sem remontar. Se ela continuar travada: `tnrx-connect umount -f` e `tnrx-connect mount`.

### Tabela

| Sintoma | Causa | O que fazer |
| --- | --- | --- |
| A pasta montada aparece vazia | O terminal já estava na pasta antes de montar | `cd .` |
| `... não está vazia` | A pasta local tem arquivos | Use uma pasta vazia |
| `... não está montada` | A pasta foi desmontada | `tnrx-connect` |
| `A conexão autenticada com ... caiu` | Rede ou hibernação | [Reconectar](#a-rede-caiu) |
| Salvei no laptop e o job viu a versão antiga | O envio leva uns 5 s | Espere antes de submeter |
| Não vejo no laptop um arquivo que o job criou | A listagem é atualizada a cada 30 s | `tnrx-connect refresh` |
| `git status` lento | Cada arquivo é consultado pela rede | Use o `git` no terminal do servidor |
| `Nenhum servidor Jupyter no ar` | Ainda na fila, iniciado fora da raiz do projeto, ou `tnrx` desatualizado no servidor | Inicie um novo pelo menu; `tnrx update` no servidor |
| `O tnrx terminou sem subir o Jupyter` | Falha no servidor (projeto sem imagem, sem Jupyter no `.venv`, partição errada) | Leia o fim do log que ele mostra (`.tnrx/jupyter/launch.log`) |
| A URL do Jupyter no VS Code mudou | A porta fixa estava ocupada no laptop | Feche o que usa a porta e reconecte |
| O navegador não abre `nó.host.localhost` | O sistema não resolve `*.localhost` | Use o link `127.0.0.1` |
| `umount` falha com `Ainda em uso` | Algo usa a pasta | Feche o editor/Claude Code, `cd ~`, rode de novo (ou `-f`) |
| Erros do `tnrx` no terminal do servidor | | Veja [Problemas comuns do tnrx](tnrx.md#problemas-comuns) |

## Modo alternativo: rsync

Se a montagem não funciona no seu ambiente, ou você prefere uma **cópia local**, o modo rsync mantém a pasta do laptop sincronizada com o servidor, **só de ida** (laptop → servidor). O laptop é a fonte da verdade: uma edição feita direto no servidor pode ser sobrescrita no próximo envio.

```bash
tnrx-connect init     # cria o .tnrx_connect na raiz do projeto (host e pasta remota)
tnrx-connect rsync    # sincroniza e abre o terminal do servidor; sincroniza a cada 3 s enquanto ele estiver aberto
```

O `.tnrx_connect` segue o modelo [`.tnrx_connect.example`](../.tnrx_connect.example):

```bash
HOST=recod-headnode
REMOTE_PATH=/home/seu_usuario/meu-projeto
# SYNC_DELETE=true    # apaga no servidor o que você apagou no laptop (padrão: true)
# POLL_INTERVAL=3     # segundos entre sincronizações (padrão: 3)
```

| Comando | O que faz |
| --- | --- |
| `tnrx-connect rsync` | Sincroniza e abre o terminal do servidor; continua sincronizando enquanto ele estiver aberto |
| `tnrx-connect sync` | Sincroniza uma vez, laptop → servidor |
| `tnrx-connect pull` | Traz do servidor uma vez, sem apagar nada local |
| `tnrx-connect init` | Cria o `.tnrx_connect` |

* O `.gitignore` do projeto vale como lista de exclusão: `.venv/`, `*.sif` e o que mais estiver lá nunca são enviados nem apagados.
* Com `SYNC_DELETE=true`, um arquivo criado à mão no servidor, dentro do projeto e fora do `.gitignore`, é apagado no próximo envio.
* Editou e vai submeter um job logo em seguida? Rode `tnrx-connect sync` antes, para não depender do intervalo.
