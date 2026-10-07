# tnrx

Ferramentas para trabalhar em projetos de Python com GPU nos servidores do laboratório (Abaporu, Headnode). São duas, e cada uma roda numa máquina:

| | [`tnrx`](docs/tnrx.md) | [`tnrx-connect`](docs/tnrx-connect.md) |
| --- | --- | --- |
| **Onde roda** | No **servidor** | No **seu laptop** |
| **O que faz** | Executa o projeto: cria o container, instala as bibliotecas com o `uv` e submete os jobs no Slurm | Liga o laptop ao servidor: monta a pasta do projeto no laptop, abre o terminal do servidor e traz o Jupyter até o seu navegador ou VS Code |
| **Instala algo no servidor?** | Sim, é o próprio `tnrx` | Não. Usa só `ssh` e SFTP, que o servidor já tem |

```
   SEU LAPTOP (com internet)                     SERVIDOR
┌──────────────────────────┐                  ┌─────────────────────────────────┐
│ editor, Claude Code      │  pasta montada   │ headnode: arquivos do projeto,  │
│ na pasta montada         │ ◄──────────────► │ tnrx uv, tnrx hf (tem internet) │
│                          │                  │                                 │
│ terminal do servidor     │  ssh             │ nós Slurm: tnrx uvslurm,        │
│ (tnrx-connect ssh)       │ ───────────────► │ Jupyter, GPUs (sem internet)    │
│                          │                  │                                 │
│ navegador / VS Code      │  ponte do Jupyter│                                 │
└──────────────────────────┘ ◄─────────────── └─────────────────────────────────┘
```

**Por que duas ferramentas:** os nós de computação não têm internet, e ferramentas como o Claude Code precisam dela o tempo todo. Rodá-las no headnode sobrecarrega uma máquina compartilhada, e um proxy pelo headnode desfaria o isolamento de rede do cluster. Então o editor e o Claude Code rodam no laptop, o código roda no servidor, e o `tnrx-connect` liga os dois.

## Início rápido

**Instalação**, uma vez em cada máquina (servidores e laptop):

```bash
curl -fsSL https://raw.githubusercontent.com/recod-ai/tnrx/main/install.sh | bash
```

O mesmo comando serve para as duas. Ele pergunta o que instalar (`tnrx`, `download_huggingface`, `tnrx-connect` e a extensão do VS Code), já sugerindo o que faz sentido para a máquina: num servidor, o `tnrx`; num laptop, o `tnrx-connect`. Para atualizar depois: `tnrx update` (ou `tnrx-connect update`). Detalhes em [docs/tnrx.md](docs/tnrx.md#instalação).

**Para cada projeto**, no laptop:

```bash
mkdir -p ~/trabalho/meu-projeto && cd ~/trabalho/meu-projeto
tnrx-connect          # pergunta o servidor e a pasta remota, monta e abre o terminal do servidor
```

No terminal do servidor que abriu:

```bash
tnrx uv init                           # só se o projeto ainda não tem pyproject.toml
tnrx uv add torch                      # na primeira vez, pergunta qual imagem usar (Enter = a padrão)
tnrx uvslurm python deep_check.py      # roda na GPU
```

Em outra aba do laptop, na mesma pasta, abra o editor ou o Claude Code. O que você salva ali é o que roda no servidor.

## Documentação

| Documento | Para quê |
| --- | --- |
| [docs/tnrx.md](docs/tnrx.md) | Manual do `tnrx`: imagem do container, bibliotecas, Slurm, Jupyter, Hugging Face |
| [docs/tnrx-connect.md](docs/tnrx-connect.md) | Manual do `tnrx-connect`: montar o projeto, tarefas do dia a dia, Jupyter, snapshots |
| [vscode/README.md](vscode/README.md) | Extensão do VS Code: barra lateral com montagens, Slurm, cluster e Jupyter |
| [docs/tnrx-connect-json.md](docs/tnrx-connect-json.md) | Interface `--json` do `tnrx-connect`, para quem escreve ferramentas em cima dele |
| [docs/desenvolvimento.md](docs/desenvolvimento.md) | Para quem mexe neste repositório: testes, pre-commit, organização do código |
| [docs/validacao-manual.md](docs/validacao-manual.md) | O que ainda precisa ser conferido num servidor real |

> **Estado:** o `tnrx` está em uso no Abaporu e no Headnode. O `tnrx-connect` já monta o Headnode com o `rclone` real. Ainda falta conferir num servidor real o 2FA do Abaporu, escritas pendentes depois de uma queda de rede, o desempenho de `git status` na pasta montada, o build da imagem a partir do `tnrx.def` e o macOS. A lista completa está em [docs/validacao-manual.md](docs/validacao-manual.md).

## O que tem no repositório

| Arquivo | Ferramenta | O que é |
| --- | --- | --- |
| [`install.sh`](install.sh) | ambas | O instalador: instalar, atualizar, `update-dev` e desinstalar |
| [`tnrx`](tnrx) | `tnrx` | O script |
| [`tnrx_hosts.conf`](tnrx_hosts.conf) | `tnrx` | O que muda de um servidor para outro: bind path, runtime do container, pasta do Hugging Face |
| [`tnrx.def`](tnrx.def) | `tnrx` | Modelo da imagem do container, para copiar para um projeto que precise de pacotes do sistema |
| [`tnrx_slurm.conf`](tnrx_slurm.conf) | `tnrx` | Exemplo de configuração do Slurm de um projeto |
| [`download_huggingface`](download_huggingface) | `tnrx` | Usado por `tnrx hf` para baixar modelos e datasets |
| [`deep_check.py`](deep_check.py), [`deep_check_jax.py`](deep_check_jax.py), [`load_model.py`](load_model.py) | `tnrx` | Scripts de exemplo para conferir a GPU com PyTorch e JAX, e carregar um modelo baixado |
| [`tnrx-connect`](tnrx-connect) | `tnrx-connect` | O script |
| [`.tnrx_connect.example`](.tnrx_connect.example) | `tnrx-connect` | Modelo de configuração do modo rsync (o modo mount não usa) |
| [`vscode/`](vscode/) | `tnrx-connect` | A extensão do VS Code |
| [`test_tnrx.sh`](test_tnrx.sh), [`test_tnrx_connect.sh`](test_tnrx_connect.sh) | ambas | Testes; veja [docs/desenvolvimento.md](docs/desenvolvimento.md) |
