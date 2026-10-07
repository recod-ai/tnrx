# Desenvolvimento

Para quem mexe neste repositório. O uso das ferramentas está em [tnrx.md](tnrx.md) e [tnrx-connect.md](tnrx-connect.md).

## Princípios

* **Dois scripts `bash`, sem dependências além das do sistema.** O `tnrx` precisa só do runtime do container, do Slurm e do `uv`. O `tnrx-connect` precisa só de `ssh`, `rclone` e FUSE.
* **Nada instalado no servidor para o `tnrx-connect`.** Ele usa `ssh` e SFTP. Quando precisa de algo do servidor (registrar o Jupyter, ler a fila), quem faz é o `tnrx`, que já está lá, ou um comando do sistema (`squeue`, `sinfo`).
* **O que muda por servidor fica em arquivo, não no código:** [`tnrx_hosts.conf`](../tnrx_hosts.conf).
* **A lógica fica no `tnrx-connect`.** A extensão do VS Code só mostra o que o `tnrx-connect --json` devolve ([contrato](tnrx-connect-json.md)). Uma funcionalidade nova entra primeiro no script, com teste, e depois na extensão.
* **Senha e 2FA só num terminal.** Nenhum comando `--json` autentica nem pergunta nada.

## Organização

| Arquivo | O que é |
| --- | --- |
| [`install.sh`](../install.sh) | Instalador: clona (ou copia a pasta local, no `update-dev`) para `~/.local/share/tnrx`, troca a pasta de uma vez, cria os links e prepara o servidor ou o VS Code |
| [`tnrx`](../tnrx) | Script do servidor. `do_install`, `do_uv`, `do_slurm`, `do_uvslurm`, `do_huggingface`; o Jupyter é tratado dentro de `do_uvslurm` |
| [`tnrx-connect`](../tnrx-connect) | Script do laptop. Modo rsync no início; depois montagem, travas, snapshots, Jupyter e a interface `--json` |
| [`test_tnrx.sh`](../test_tnrx.sh), [`test_tnrx_connect.sh`](../test_tnrx_connect.sh) | Testes de cada script |
| [`vscode/`](../vscode/) | Extensão: `src/model.js` (JSON → árvores, funções puras), `src/cli.js` (chama o `tnrx-connect`), `src/extension.js` (vistas e comandos) |

## Instalar a sua cópia

Os comandos instalados (`~/.local/bin/tnrx` e os outros) apontam para `~/.local/share/tnrx`, e não para a pasta onde você desenvolve. Para experimentar uma mudança antes do commit, copie a sua pasta para lá:

```bash
cd ~/Documents/Apps/tnrx      # a sua cópia do repositório
tnrx update-dev               # ou: tnrx update-dev <pasta>; tnrx-connect update-dev também serve
```

* Vai tudo o que o git enxerga, inclusive mudanças não commitadas e arquivos novos. O que o `.gitignore` exclui (`.venv`, `*.sif`, `.tnrx_connect`) fica de fora.
* `tnrx version` mostra `dev:<pasta> (com mudanças não commitadas)`, para você saber que não está na versão do GitHub.
* Rode de novo a cada mudança. Para voltar à versão publicada: `tnrx update`.
* Ele instala os mesmos componentes da instalação atual. Para mudar: `tnrx update-dev --choose`. Com o `tnrx` num servidor, também roda o `tnrx install`; com a extensão, reinstala a extensão (pule com `TNRX_SKIP_VSCODE=1`).
* Para testar no servidor uma mudança feita no laptop, a pasta precisa estar no servidor: monte-a com o `tnrx-connect` e rode `tnrx update-dev` no terminal do servidor, dentro dela.

## Testes

```bash
TNRX_SKIP_RUNTIME_TEST=1 bash test_tnrx.sh    # tnrx
bash test_tnrx_connect.sh                     # tnrx-connect (~50 s)
bash test_tnrx.sh test_install_singularity    # um teste só
cd vscode && node --test test/                # extensão (precisa só do Node)
```

Os testes trocam `hostname`, `ssh`, `rclone`, `fusermount3`, `srun`, `singularity` e `uv` por versões falsas, que imprimem os argumentos que receberam. Assim eles conferem os comandos montados (muitas vezes pelo `--debug`), as mensagens e os fluxos completos sem servidor, GPU ou rede. O que só um servidor real mostra está em [validacao-manual.md](validacao-manual.md): atualize essa lista quando acrescentar algo que os fakes não cobrem.

* `TNRX_SKIP_RUNTIME_TEST=1` pula o `test_runtime_env_injection`, o único que submete um job de verdade.
* `TNRX_INTERACTIVE=1` faz o `tnrx` e o `install.sh` agirem como num terminal, para testar o menu de imagens e as perguntas do instalador com as respostas vindas de um `printf`. Para testar o caso sem terminal, o teste roda o instalador com `setsid`.
* `TNRX_COMPONENTS` escolhe os componentes do instalador sem perguntar.
* `TNRX_SIF_DIR` aponta o banco de imagens para uma pasta temporária, para os testes não tocarem o `~/.tnrx/sifs` de verdade.
* Testes que instalam ou desinstalam usam um `HOME` temporário: o `uninstall` apaga `~/.local/bin/tnrx*` e `~/.local/share/tnrx`. O `test_installer` usa um repositório git local (`TNRX_REPO=file://...`) no lugar do GitHub.

## Pre-commit

O [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) roda a cada commit:

| Hook | O que faz |
| --- | --- |
| `uv-lock-check` | `./tnrx uv lock --check`: o `uv.lock` está em dia com o `pyproject.toml` |
| `uv-format-toml` | Compila o `pyproject.toml` com `uv pip compile`, só para ver se ele resolve |
| `tnrx-test-suite`, `tnrx-connect-test-suite` | As duas baterias de testes |
| `tnrx-vscode-tests` | Os testes da extensão, quando algo em `vscode/` muda (pulado sem Node) |
| `black`, `isort`, checagens de YAML/TOML, arquivos acima de 10 MB | Formatação e higiene |

Os dois primeiros usam o container, então os commits deste repositório são feitos **no servidor** (num projeto montado, pelo terminal do `tnrx-connect ssh`). Para instalar, no servidor:

```bash
~/.local/bin/uv tool install pre-commit
pre-commit install
```

Se o `uv-lock-check` falhar, rode `tnrx uv lock` e inclua o `uv.lock` no commit.

O mesmo hook serve para qualquer projeto que usa o `tnrx`. Use `tnrx` em vez de `./tnrx`:

```yaml
repos:
  - repo: local
    hooks:
      - id: uv-lock-check
        name: uv.lock em dia com o pyproject.toml
        entry: tnrx uv lock --check
        language: system
        always_run: true
        pass_filenames: false
```

## Extensão do VS Code

Gerar e instalar: veja [vscode/README.md](../vscode/README.md). Para conferir as vistas sem abrir o VS Code, `node tools/print-tree.js` desenha no terminal os quatro blocos com os dados reais do laptop.
