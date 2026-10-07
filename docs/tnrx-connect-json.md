# `tnrx-connect --json`: interface para ferramentas

> Para quem escreve uma ferramenta em cima do `tnrx-connect` (a extensão do VS Code, por exemplo). O uso no terminal está em [tnrx-connect.md](tnrx-connect.md).

A ferramenta não reimplementa nada: ela chama o `tnrx-connect` com `--json` e lê a saída. Toda a lógica (montagem, SSH, Slurm, Jupyter) continua num lugar só, coberta pelo `test_tnrx_connect.sh`.

## Regras gerais

* **Nunca pergunta nada.** Com `--json`, nenhum comando lê do stdin. Passe `</dev/null` mesmo assim.
* **Nunca autentica.** Os comandos usam a conexão SSH mestra que o `tnrx-connect mount` abriu. Sem ela, falham com o código `not_connected` (saída 3). A autenticação, com senha/2FA, é sempre num terminal: a ferramenta abre um terminal com `tnrx-connect mount` (na pasta) e espera o usuário.
* **Montar, desmontar e abrir o terminal do servidor são comandos de terminal**, sem `--json`: `tnrx-connect mount`, `tnrx-connect ssh` (rodados na pasta local) e `tnrx-connect umount <pasta>` (não pergunta nada; o resultado é o código de saída e a mensagem no stderr).
* **Versão do formato:** todo objeto tem `"v": 1`. Campos novos podem aparecer sem mudar a versão; ignore os que não conhece.
* **stdout tem só JSON.** Mensagens para pessoas vão para o stderr.

### Dois formatos

| Tipo | Comandos | Saída |
| --- | --- | --- |
| **Resposta única** | `status`, `cluster`, `cluster cancel`, `jupyter list`, `jupyter stop` | Um objeto em uma linha: `{"v":1,"ok":true,...}` ou `{"v":1,"ok":false,"error":{"code":...,"message":...}}` |
| **Eventos** | `jupyter start`, `jupyter connect` | Um objeto por linha (JSON Lines), cada um com `"event"`. Erro vira `{"v":1,"event":"error","code":...,"message":...}` |

### Códigos de saída e de erro

| Saída | Significado |
| --- | --- |
| `0` | Sucesso |
| `1` | Falha (veja `error.code`) |
| `2` | Uso inválido (`usage`): opção faltando, job inválido |
| `3` | Sem conexão (`not_connected`) |
| `130` | Interrompido por sinal (o `jupyter start` cancela o job; o `jupyter connect` fecha a ponte) |

| `code` | Quando |
| --- | --- |
| `not_connected` | Não há conexão mestra viva com o host |
| `usage` | Faltou `--host`/`--project`, ou job inválido |
| `scancel_failed` | O `scancel` recusou (job inexistente, de outro usuário...) |
| `prepare_failed` | Não deu para gravar a senha fixa no projeto (a pasta remota existe?) |
| `launch_failed` | O servidor não iniciou o `tnrx` (sem `tnrx`, sem `setsid`) |
| `tnrx_failed` | O `tnrx` terminou sem subir o Jupyter; `message` traz o fim do log |
| `bridge_failed` | Nenhuma porta local livre para a ponte |
| `no_server` | `jupyter connect` sem Jupyter no ar no projeto (ou sem o `--job` pedido) |
| `query_failed`, `no_slurm` | Só dentro de um host do `cluster`: o servidor não respondeu, ou não tem `sinfo` |

### Opções comuns

* `--host H`: o host (como no `.conf`: alias do `~/.ssh/config` ou `user@servidor`). Sem ele, os comandos que precisam de um host usam o da pasta montada onde foram rodados.
* `--project P`: a pasta **remota** do projeto (caminho absoluto no servidor), como em `remote_path`.
* `--job J`: o id do job no Slurm.

## Comandos

### `tnrx-connect status --json`

Todas as pastas que este laptop conhece (os `.conf`), com o estado. Não usa a rede, exceto um `ssh -O check` por host (local, instantâneo) e a leitura do `tnrx_slurm.conf` pela pasta montada (com limite de 3 s).

```json
{"v":1,"ok":true,
 "mounts":[
  {"id":"recod-headnode_code","name":"code",
   "local_dir":"/home/marcos/Research/x/code","host":"recod-headnode","remote_path":"/home/marcos/x",
   "state":"mounted","connected":true,"rclone_pid":3610194,"since":1759590000,"last_used":1759590000,
   "jupyter_port":18342,"log":"/home/marcos/.local/share/tnrx-connect/recod-headnode_code/mount.log",
   "slurm":{"file":"/home/marcos/Research/x/code/tnrx_slurm.conf","exists":true,
            "values":{"PARTITION":{"value":"l40s","from_file":true},
                      "GPUS":{"value":"1","from_file":false}, "CPUS":{...}, "MEM":{...}, "TIME":{...}}}}
 ],
 "hosts":[{"host":"recod-headnode","connected":true}]}
```

* `state`:
  * `mounted`: montada e com o `rclone` rodando;
  * `mounting`: um `mount` está em andamento;
  * `stale`: o ponto de montagem existe, mas o `rclone` morreu (a ferramenta deve sugerir `tnrx-connect mount`, que recupera);
  * `unmounted`: não montada.

  A mesma pasta local pode ter um `.conf` por host: só o da montagem atual aparece como `mounted`.
* `connected`: a conexão mestra com o host está viva. `mounted` com `connected: false` = a rede caiu; a ferramenta oferece "Reconectar" (terminal com `tnrx-connect mount` na pasta).
* `slurm`: só para `mounted` + `connected` (senão `null`). Os valores são os **efetivos**: os do `tnrx_slurm.conf` (`from_file: true`) ou o padrão do `tnrx` (`from_file: false`). `file` é o caminho local, para abrir no editor.
* `jupyter_port`: a porta local fixa do Jupyter desse projeto, ou `null` se ainda não foi escolhida.
* `hosts`: cada host dos `.conf`, com a conexão.

### `tnrx-connect cluster [--host H] --json`

`sinfo` e os jobs do usuário (`squeue -u $USER`). Sem `--host`, consulta **os hosts que têm alguma pasta montada**. Um host com problema não derruba os outros: cada um tem seu `ok`.

```json
{"v":1,"ok":true,"hosts":[
 {"host":"recod-headnode","connected":true,"ok":true,
  "partitions":[
   {"name":"l40s","default":true,"available":"up","time_limit":"4-00:00:00",
    "nodes":{"allocated":0,"idle":0,"other":4,"total":4},
    "gres":"gpu:l40s:4","gpus":{"total":14,"used":9,"unavailable":0,"free":5}}],
  "jobs":[
   {"id":"104472","partition":"l40s","name":"apptainer","state":"RUNNING","elapsed":"22:33",
    "time_limit":"2:00:00","reason":"dl-05","work_dir":"/home/marcos/x"}]},
 {"host":"recod","connected":false,"ok":false,
  "error":{"code":"not_connected","message":"..."},"partitions":[],"jobs":[]}]}
```

* `nodes`: a soma das linhas do `sinfo` da partição (`%F`: alocados/livres/outros/total). Nós `MIXED` (parte das GPUs em uso) contam em `other`, então `idle` subestima o que está disponível: para "dá para rodar agora?", use `gpus.free`.
* `gpus`: de `scontrol show node -o` (`CfgTRES`/`AllocTRES` `gres/gpu`). `unavailable` = GPUs não alocadas em nós `DOWN`/`DRAIN`/`MAINT`/...; `free = total - used - unavailable`. `null` se o cluster não informa GPUs.
* `jobs[].work_dir`: a pasta em que o job foi submetido. Compare com `remote_path` para saber de que projeto ele é. `reason` é o nó (rodando) ou o motivo (na fila, ex.: `(Resources)`).
* `default`: a partição padrão do Slurm (a do `*` no `sinfo`), não a do `tnrx_slurm.conf`.

### `tnrx-connect cluster cancel <job> --host H --json` / `tnrx-connect jupyter stop <job> --host H --json`

`scancel <job>` no host. Os dois são o mesmo comando; `jupyter stop` existe para a ação "Encerrar" do bloco do Jupyter.

```json
{"v":1,"ok":true,"host":"recod-headnode","job":"104472"}
```

### `tnrx-connect jupyter list [--host H] --json`

Os Jupyters no ar, por host e por projeto. Sem `--host`, todos os hosts dos `.conf`. Os projetos são as pastas remotas que este laptop conhece naquele host (os `.conf`), mesmo sem Jupyter (lista vazia).

```json
{"v":1,"ok":true,"hosts":[
 {"host":"recod-headnode","connected":true,"projects":[
  {"name":"pareto-sensibility","remote_path":"/home/marcos/pareto-sensibility","local_dir":"/home/marcos/code",
   "servers":[
    {"node":"dl-05","port":8888,"job":"104472","started":1759590000,"token":"...","token_fixed":true,
     "bridge_open":false,"local_port":18342,"url":"http://127.0.0.1:18342/lab?token=..."}]}]}]}
```

* Um servidor só aparece se a porta responde **e** (quando o servidor tem `squeue`) o job ainda está na fila. Para o mesmo `nó:porta`, só o registro mais recente.
* `local_port`/`url`: com `bridge_open: true`, a ponte já está aberta (por qualquer `tnrx-connect jupyter` deste laptop) e a URL funciona agora. Com `false`, é a URL que o `jupyter connect` vai abrir: a porta fixa do projeto.
* `token_fixed`: o Jupyter usa a senha fixa do projeto. Com `true` e porta fixa, a `url` é a mesma sempre. Com `false` (iniciado antes da senha fixa, ou `tnrx` desatualizado no servidor), ela vale só para aquele Jupyter.
* `token` é a senha do Jupyter: não registre em logs.

### `tnrx-connect jupyter start --host H --project P --json`

Roda `tnrx uvslurm jupyter lab` em `P` no servidor (desacoplado: `nohup setsid`), e espera ele subir. **Não abre ponte**: depois do `ready`, chame `jupyter connect`.

```json
{"v":1,"event":"launching","host":"recod-headnode","project":"/home/marcos/x","log":"/home/marcos/x/.tnrx/jupyter/launch.log"}
{"v":1,"event":"waiting","phase":"queued","elapsed":0}
{"v":1,"event":"waiting","phase":"starting","elapsed":40}
{"v":1,"event":"ready","host":"recod-headnode","project":"/home/marcos/x","server":{ ...como no list... }}
```

* `waiting` sai a cada ~10 s. `phase`: `preparing` (antes do `srun`), `queued` (na fila do Slurm), `starting` (job alocado, Jupyter subindo).
* Não há limite de tempo: um job pode ficar horas na fila.
* **Cancelar:** mande `SIGTERM` ao processo. Ele cancela o job no servidor, emite `{"event":"cancelled"}` e sai com 130.
* Falha: evento `error` (`tnrx_failed` traz o fim do log em `message`), saída 1.

### `tnrx-connect jupyter connect --host H --project P [--job J] --json`

Abre a ponte para o Jupyter `J` do projeto (sem `--job`, o mais recente) na porta local fixa do projeto, e **fica rodando enquanto a ponte existir**. A ferramenta mantém esse processo vivo.

```json
{"v":1,"event":"bridge","host":"recod-headnode","project":"/home/marcos/x","fixed_port":true,
 "label_url":"http://dl-05.recod-headnode.localhost:18342/lab?token=...","server":{ ...bridge_open: true... }}
{"v":1,"event":"closed","reason":"server_stopped"}
```

* Depois do `bridge`, `server.url` (`127.0.0.1`) funciona. É a que o VS Code usa. `label_url` é para navegador (cookies separados por servidor).
* `fixed_port: false`: a porta fixa estava ocupada no laptop e a ponte usou outra; a URL mudou só desta vez.
* `closed.reason`: `server_stopped` (o Jupyter parou; checado a cada ~30 s), `connection_lost` (a conexão mestra caiu: sugira reconectar) ou `signal` (a ferramenta mandou `SIGTERM`, que é como se fecha a ponte).
* A ponte usa a conexão mestra: um `umount` não a derruba (ele vê a ponte e mantém a conexão).

## Arquivos que a ferramenta pode observar

Para atualizar a interface sem ficar consultando, observe mudanças em:

| Caminho | Muda quando |
| --- | --- |
| `~/.config/tnrx-connect/*.conf` | Uma pasta nova é montada pela primeira vez, ou a porta fixa do Jupyter é escolhida |
| `~/.local/share/tnrx-connect/locks/` | Uma pasta é montada ou desmontada |
| `~/.local/share/tnrx-connect/bridges/` | Uma ponte do Jupyter abre ou fecha |

A conexão (`connected`) e os Jupyters/jobs no servidor não geram eventos locais: consulte com `status --json` (barato) e `jupyter list --json`/`cluster --json` (uma chamada SSH cada) num intervalo razoável, de 30 s a alguns minutos. Lembre que o `cluster` roda `sinfo`/`scontrol` no headnode compartilhado.
