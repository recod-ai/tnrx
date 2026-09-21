# `tnrx-connect`: trabalhar no seu laptop com o projeto no servidor

> **Onde roda:** no **seu laptop/desktop/notebook**, não no servidor. O `tnrx-connect` é o companion do [`tnrx`](tnrx.md) (que roda no servidor). Visão geral das duas ferramentas: [README](../README.md).

## Por que existe

Os nós de computação do Slurm não têm acesso à internet, e ferramentas como o Claude Code precisam de internet o tempo todo — então elas não podem rodar lá. Rodar essas ferramentas direto no headnode também não é uma boa ideia: é uma máquina compartilhada por todo o time, e um agente de coding facilmente a sobrecarrega. Um proxy de rede pelo headnode resolveria o problema tecnicamente, mas reabriria de propósito o isolamento de rede que os nós têm por motivo de segurança — não é uma decisão pra tomar dentro de um script.

A solução é rodar a ferramenta no **seu laptop** (com internet plena) e deixar os arquivos do projeto no servidor. O `tnrx-connect` é o companion do `tnrx` que faz essa ponte, roda só no laptop e **não exige instalar nada no servidor** (usa `ssh` e o subsistema SFTP do `sshd`). Ele tem dois modos:

* **Modo mount (recomendado):** monta a pasta do projeto do servidor, via `rclone`, na pasta onde você rodou o comando. Só existe **uma cópia** dos arquivos (no servidor), então não há duas versões pra divergir — editar no laptop ou no servidor é editar o mesmo arquivo.
* **Modo rsync (alternativo):** mantém uma cópia local sincronizada com o servidor, só de ida (laptop → servidor). Veja [Modo alternativo: rsync](#modo-alternativo-rsync).

## Modo mount (recomendado)

> **Status:** este modo foi validado com testes automatizados que usam `ssh`, `rclone` e `fusermount3` **falsos** (fluxo, lock, recuperação de sessão, snapshots). Ele ainda **não foi testado com o `rclone` real nem no Abaporu**. Antes de depender dele, valide à mão: (1) senha/2FA pedidas uma única vez, com o `rclone` reaproveitando a conexão SSH já autenticada; (2) escritas pendentes sobrevivem a uma queda de rede e sobem na próxima montagem; (3) desempenho de `git status` e de buscas na pasta montada.

### Pré-requisitos e instalação (no laptop)

* `ssh` (OpenSSH com `ControlMaster`), `rclone` e FUSE (`fuse3` no Linux; macFUSE no macOS, ainda não validado).
* SFTP habilitado no servidor (confira com `sftp <host>`).
* Uma cópia deste repositório **no laptop** (só o script `tnrx-connect` é usado lá; o restante do repositório é do [`tnrx`](tnrx.md), que roda no servidor). O `~/.local/bin` precisa estar no seu `PATH`.

Na pasta do repositório clonado no laptop:

```bash
chmod +x tnrx-connect
ln -sf "$(pwd)/tnrx-connect" ~/.local/bin/tnrx-connect
```

### Uso

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
* Em **outra aba local**: `cd ~/trabalho/meu-projeto && claude`. Numa aba que já estava aberta nessa pasta antes de montar, rode `cd .` (ou reabra) pra enxergar o conteúdo montado.
* Ao sair do terminal SSH (`exit`/`Ctrl-D`), o comando tira um último snapshot, desmonta, espera o `rclone` terminar de enviar o que estava pendente e encerra a conexão.

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
