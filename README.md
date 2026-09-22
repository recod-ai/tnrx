# tnrx

Este repositório tem **duas ferramentas independentes**, que rodam em máquinas diferentes:

| | [`tnrx`](docs/tnrx.md) | [`tnrx-connect`](docs/tnrx-connect.md) |
| --- | --- | --- |
| **Onde roda** | No **servidor** (Abaporu, Headnode) | No **seu laptop/desktop/notebook** |
| **Pra que serve** | Rodar código no cluster: unifica o isolamento do **Singularity**, a velocidade do **uv** e a orquestração do **Slurm** | Trabalhar com o projeto **do seu computador** (editor, Claude Code) enquanto os arquivos ficam no servidor |
| **Precisa de internet?** | Só no headnode (instalar pacotes, baixar modelos) | Sim, é o ponto: roda onde há internet plena |
| **Instalar algo no servidor?** | Sim: é o próprio `tnrx` | **Não**: usa só `ssh`/SFTP, que o servidor já tem |
| **Documentação** | [docs/tnrx.md](docs/tnrx.md) | [docs/tnrx-connect.md](docs/tnrx-connect.md) |

## Como as duas se encaixam

```
   SEU LAPTOP                                    SERVIDOR (Abaporu / Headnode)
┌──────────────────────┐                      ┌────────────────────────────────┐
│  editor, Claude Code │   tnrx-connect       │  arquivos do projeto           │
│  (com internet)      │ ───────────────────► │  tnrx slurm / tnrx uvslurm     │
│                      │  mount ou rsync      │  (nós Slurm: sem internet)     │
│  terminal SSH aberto │ ◄─────────────────── │  Jupyter, jobs de GPU, /data   │
└──────────────────────┘   terminal do        └────────────────────────────────┘
                           servidor
```

* O **`tnrx`** é o que **executa** o trabalho: cria o ambiente, submete jobs no Slurm, sobe o Jupyter e baixa modelos do Hugging Face. Ele só existe no servidor.
* O **`tnrx-connect`** é o que **liga o seu laptop ao servidor**: monta (ou sincroniza) a pasta do projeto no seu computador e abre um terminal SSH no servidor, onde você roda os comandos do `tnrx`.

Por que duas ferramentas? Os nós de computação do Slurm não têm internet, e o Claude Code precisa dela o tempo todo. Rodá-lo no headnode sobrecarrega uma máquina compartilhada, e um proxy pelo headnode reabriria o isolamento de rede que o cluster mantém de propósito. Então o Claude Code roda **no laptop**, e o `tnrx-connect` faz a ponte até os arquivos no servidor.

## Por onde começar

**Vou rodar jobs no servidor** → [docs/tnrx.md](docs/tnrx.md), no servidor:

```bash
chmod +x tnrx
ln -sf "$(pwd)/tnrx" ~/.local/bin/tnrx
tnrx install uv && tnrx install singularity
tnrx uvslurm python deep_check.py
```

**Quero editar no meu laptop (ex.: com o Claude Code)** → [docs/tnrx-connect.md](docs/tnrx-connect.md), no laptop:

```bash
chmod +x tnrx-connect
ln -sf "$(pwd)/tnrx-connect" ~/.local/bin/tnrx-connect
mkdir -p ~/trabalho/meu-projeto && cd ~/trabalho/meu-projeto
tnrx-connect
```

> O modo mount do `tnrx-connect` já montou o Headnode com o `rclone` real e funciona. Ainda não foram validados num servidor real: o 2FA do Abaporu, escritas pendentes após queda de rede, o desempenho de `git status`/buscas na pasta montada e o macOS; a lista de conferência está em [docs/validacao-manual.md](docs/validacao-manual.md). O manual com o passo a passo das tarefas do dia a dia está em [docs/tnrx-connect.md](docs/tnrx-connect.md#tarefas-do-dia-a-dia).

## O que tem no repositório

| Arquivo | Pertence a | O que é |
| --- | --- | --- |
| [`tnrx`](tnrx) | `tnrx` (servidor) | O wrapper Singularity + uv + Slurm |
| [`tnrx_hosts.conf`](tnrx_hosts.conf) | `tnrx` (servidor) | Particularidades de cada servidor (bind path, runtime, `HUB_ROOT`); veja [docs/tnrx.md](docs/tnrx.md#11-particularidades-de-cada-servidor-tnrx_hostsconf) |
| [`tnrx_slurm.conf`](tnrx_slurm.conf) | `tnrx` (servidor) | Partição, GPUs, CPUs, memória e tempo dos jobs |
| [`download_huggingface`](download_huggingface) | `tnrx` (servidor) | Utilitário de download do Hugging Face Hub, usado por `tnrx hf` |
| [`tnrx-connect`](tnrx-connect) | `tnrx-connect` (laptop) | Monta/sincroniza o projeto do servidor no laptop e abre o terminal SSH |
| [`.tnrx_connect.example`](.tnrx_connect.example) | `tnrx-connect` (laptop) | Template de config do modo rsync (o modo mount não usa) |
| [`test_tnrx.sh`](test_tnrx.sh), [`test_tnrx_connect.sh`](test_tnrx_connect.sh) | ambas | Testes de cada ferramenta; rodam a cada commit via pre-commit (ver [docs/tnrx.md](docs/tnrx.md#8-qualidade-de-código-e-pre-commit)) |
