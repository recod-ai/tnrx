# Validação manual (o que os testes automatizados não cobrem)

Os testes de `test_tnrx.sh` e `test_tnrx_connect.sh` usam `ssh`, `rclone`, `srun` e `tnrx` **falsos**. Esta lista é o que só dá para conferir num servidor real. Marque conforme for validando; se algo falhar, anote a saída do terminal e o resultado de `squeue -u $USER`.

Antes de começar: o `tnrx` novo precisa estar no servidor (`git pull` lá). Ele gera o token do Jupyter e grava `.tnrx/jupyter/<job>.env` quando o Jupyter começa a responder.

## 1. `tnrx-connect jupyter` (descoberta automática)

Você inicia o Jupyter no servidor (`tnrx uvslurm jupyter lab`, na raiz do projeto, aba 1) e o `tnrx-connect jupyter` (aba 2, dentro da pasta montada) descobre qual está no ar e abre a ponte. Detalhes de uso: [tnrx-connect.md](tnrx-connect.md#jupyter).

**O que o servidor real precisa confirmar (o que os fakes não provam):**

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | Caminho feliz | Aba 1: `tnrx uvslurm jupyter lab`. Aba 2: `tnrx-connect jupyter` | Sem perguntas, a ponte abre e o link funciona no navegador; um notebook executa uma célula |
| ☐ | O container escreve na pasta do projeto | Depois de subir o Jupyter, no servidor: `ls -la .tnrx/ .tnrx/jupyter/` | Existem `.tnrx/.gitignore` (`*`) e `.tnrx/jupyter/<job>.env` com permissão `-rw-------`; `git status` no projeto **não** mostra `.tnrx` |
| ☐ | `$SLURM_JOB_ID` chega ao container | Compare o nome do arquivo `.tnrx/jupyter/<job>.env` com `squeue -u $USER` | O nome é o id do job. Se for um número estranho, a variável não atravessou o `srun`/container e o `tnrx` caiu para o PID |
| ☐ | Registro só depois da porta responder | Com o job ainda na fila (ou o Jupyter subindo), rode `tnrx-connect jupyter` | `Nenhum servidor Jupyter no ar neste projeto`; depois que o Jupyter subir, o mesmo comando acha |
| ☐ | Visibilidade pelo NFS | Rode `tnrx-connect jupyter` logo depois de aparecer `Jupyter Server ... is running at` | Acha em poucos segundos. Se demorar (cache do NFS), anote quanto tempo |
| ☐ | Nenhum servidor | Sem nenhum Jupyter no ar, rode `tnrx-connect jupyter` | Só avisa que não há servidor e sai; não pede URL |
| ☐ | Vários servidores | Dois `tnrx uvslurm jupyter lab` no mesmo projeto (dois terminais do servidor) | Menu com os dois (mais recente primeiro), com nó, porta e idade; a escolha conecta no certo |
| ☐ | Servidor que já terminou | Encerre o Jupyter (aba 1: `Ctrl-C` duas vezes em menos de 1 segundo, ou `scancel <job>`) e rode `tnrx-connect jupyter` | Não lista o servidor parado (a porta não responde); o arquivo de registro é apagado depois de 1 dia |
| ☐ | A ponte fecha quando o Jupyter para | Com a ponte aberta, encerre o Jupyter no servidor | Em até ~30 s o comando avisa `terminou; a ponte foi fechada` e sai |
| ☐ | `Ctrl-C` na aba da ponte | `Ctrl-C` no `tnrx-connect jupyter` | Fecha só a ponte; o Jupyter continua no servidor (`squeue -u $USER` ainda mostra o job) |
| ☐ | Porta local ocupada | Deixe uma ponte manual (`ssh -L 8889:...`) aberta e suba um Jupyter na 8889 | Usa a 8890 e avisa `já estava em uso; usando 8890` |
| ☐ | Duas pontes ao mesmo tempo | Dois `tnrx-connect jupyter` (dois servidores) | Portas locais diferentes, sem conflito; um logout não desloga o outro |
| ☐ | Nome `*.localhost` | Abra o link com o nome e o link `127.0.0.1` | O nome abre no navegador; no VS Code (Existing Jupyter Server) use o `127.0.0.1` |
| ☐ | `umount` com a ponte aberta | Abra o mount e o `jupyter` no mesmo host e rode `tnrx-connect umount` com a ponte ainda aberta | A ponte **não** cai: o `umount` vê o `tnrx-connect jupyter` vivo e mantém a conexão mestra (ela fecha quando a ponte fechar) |
| ☐ | `tnrx` antigo no servidor | Sem `git pull` no servidor | `Nenhum servidor Jupyter no ar` (não há registro). A forma manual `tnrx-connect jupyter <URL>` funciona |
| ☐ | Iniciado numa subpasta | Rode `tnrx uvslurm jupyter lab` dentro de uma subpasta do projeto | O registro fica na subpasta e o `tnrx-connect jupyter` não o acha (ele lê a raiz). Confirme e me avise se incomoda |

**Iniciar pelo laptop e URL fixa (desde 2026-10-04):**

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | Iniciar um novo | `tnrx-connect jupyter`, `n` (ou Enter sem nenhum no ar) | Mostra `job na fila`/`subindo`, conecta sozinho quando o Jupyter sobe. Confira no servidor que o `tnrx` foi achado com `bash` não interativo (`PATH` ou `~/.local/bin/tnrx`) |
| ☐ | `Ctrl-C` enquanto espera | Inicie um novo e aperte `Ctrl-C` com o job na fila | O job some do `squeue -u $USER` (o `srun` recebe TERM) |
| ☐ | Fechar a aba depois de conectado | Feche a aba da ponte | O Jupyter continua no servidor (`squeue`); `tnrx-connect jupyter` reconecta na **mesma URL** |
| ☐ | URL fixa no VS Code | Configure o servidor no VS Code, `scancel` o job, inicie outro (pode cair em outro nó) | O VS Code reconecta no servidor salvo sem colar URL de novo; só escolher o kernel se ele pedir |
| ☐ | Senha fixa num Jupyter iniciado à mão | Depois de um `mount`, rode `tnrx uvslurm jupyter lab` no terminal do servidor | O `tnrx-connect jupyter` diz `Esta URL é fixa` (o `tnrx` leu `.tnrx/jupyter/token`) |
| ☐ | Outros projetos na lista | Dois projetos montados no mesmo host, um Jupyter em cada | Os dois aparecem, com o nome do projeto; o atual marcado |

**Já validado no servidor real:**

| ☑ | Caso | Resultado |
| --- | --- | --- |
| ☑ | `Ctrl-C` chega ao servidor (2026-09-21, Headnode) | Chega ao `srun` (`interrupt (one more within 1 sec to abort)`); o job é cancelado (`STEP ... CANCELLED`). O prompt `y/n` do Jupyter **não** aparece: o `srun` intercepta. Falta conferir `squeue -u $USER` vazio depois |

## 2. Modo mount (`tnrx-connect`)

Já funcionou com o `rclone` real (v1.75.0) montando o Headnode. Desde 2026-10-02 a montagem é independente dos terminais (`mount` / `ssh` / `umount`). Falta validar:

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | Montagem sobrevive ao terminal | `tnrx-connect mount`, depois **feche a aba** (não `exit`: feche a janela) | Em outra aba, `tnrx-connect status` mostra `Montada: sim` e `Conexão: ativa`; os arquivos continuam acessíveis e os snapshots seguem (`tnrx-connect history`) |
| ☐ | `ssh` abre e fecha sem desmontar | `tnrx-connect ssh`, `exit`, `tnrx-connect ssh` de novo, inclusive a partir de uma subpasta | Cada vez abre na pasta remota certa, sem 2FA; a pasta continua montada |
| ☐ | Conexão caída com a pasta montada | Com a pasta montada, desligue a rede (ou hiberne o laptop), religue e rode `tnrx-connect ssh` | Recusa com `A conexão ... caiu`; `tnrx-connect mount` pede 2FA de novo e o `rclone` **volta a funcionar sem remontar** (abra/salve um arquivo). Se ele não se recuperar, anote: o plano B é `umount -f` + `mount` |
| ☐ | `umount` com terminal `ssh` aberto | Com um `tnrx-connect ssh` aberto em outra aba, rode `tnrx-connect umount` | Desmonta, mas o terminal do servidor **não** cai; ao sair dele, a conexão mestra é encerrada |
| ☐ | Senha/2FA uma única vez | Abra o Abaporu (2FA) | O 2FA é pedido só uma vez; o `rclone` reaproveita a conexão pelo `ControlPath` |
| ☐ | Queda de rede com escrita pendente | Salve um arquivo na pasta montada, desligue a rede, religue e rode `tnrx-connect mount` de novo | O arquivo sobe depois de reconectar (ou na próxima montagem; o cache é persistente) |
| ☐ | Desempenho | `git status` e `grep -r` numa pasta grande montada | Tempo aceitável; anote se for lento |
| ☐ | Terminal aberto antes do mount | Rode `tnrx-connect mount` numa pasta em que o terminal já estava | O aviso pede `cd .`; depois disso o mount aparece |
| ☐ | Recuperação com algo ainda aberto (2026-09-23, Nautilus/terminal deixados abertos, real) | `kill -9` no `rclone` da montagem (PID em `tnrx-connect status`), deixar o Nautilus/um terminal navegando dentro da pasta antiga, rodar `tnrx-connect mount` de novo | Detecta a sessão anterior, desmonta (lazy) e remonta **sem pedir pra fechar nada**; se o `rclone` antigo não morrer em ~5s, o comando o encerra (`kill`, depois `kill -9`). **Validado com fakes; falta confirmar com `rclone` real** que o processo antigo realmente responde ao `kill`/`kill -9` e que os dois mounts (antigo detached + novo) não colidem no mesmo cache-dir |
| ☐ | macOS / macFUSE | Rodar num Mac | Ainda não suportado: `is_mounted` lê `/proc/mounts` e o desmonte usa `fusermount3` |

## 3. Interface `--json` (base da extensão do VS Code)

Já conferido no Headnode real (2026-10-05): `status --json`, `cluster` (partições somadas, GPUs livres, meus jobs) e `jupyter list` (registros velhos no mesmo `nó:porta` descartados pelo `squeue`). Falta:

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | GPUs livres batem com o cluster | Compare `tnrx-connect cluster` com `sinfo -o '%P %G'` e `scontrol show node` no servidor | Mesmo total; livres = total − alocadas − as de nós em drain/down |
| ☐ | Abaporu | `tnrx-connect cluster --host <abaporu>` com uma pasta montada lá | Partições e GPUs coerentes (outra versão do Slurm pode mudar o `scontrol`) |
| ☐ | `jupyter start --json` + `connect --json` | Rode os dois em sequência e abra a `url` do evento `bridge` | Eventos `launching` → `waiting` → `ready` → `bridge`; a URL abre |
| ☐ | Cancelar `start` com `SIGTERM` | `kill -TERM` no processo do `jupyter start --json` com o job na fila | Evento `cancelled`; o job some do `squeue` |

## 4. Extensão do VS Code (`vscode/`)

Os testes carregam a extensão com um `vscode` falso, e o `.vsix` foi aceito pelo `code --install-extension`; a interface em si ainda não foi vista num VS Code de verdade.

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | Instala e aparece | `python3 build-vsix.py`, `code --install-extension dist/tnrx-0.1.0.vsix`, recarregar a janela | Ícone TNRX na barra de atividades; os quatro blocos com os mesmos dados de `node tools/print-tree.js` |
| ☐ | `tnrx-connect` fora do PATH do VS Code | Abra o VS Code pelo menu do sistema (não pelo terminal) | Acha o `~/.local/bin/tnrx-connect` sozinho; senão, os blocos dizem para configurar `tnrx.connectPath` |
| ☐ | Montar pelo **+** | Escolha uma pasta vazia | Terminal com `tnrx-connect mount`; 2FA no terminal; o bloco mostra ✔ logo depois de montar |
| ☐ | Reconectar | Derrube a rede com a pasta montada | ⚠ "montada, sem conexão"; Reconectar abre o terminal e, depois do 2FA, volta a ✔ |
| ☐ | Desmontar com a pasta aberta no próprio VS Code | Desmontar a pasta do workspace atual | Falha com o motivo e oferece `-f` |
| ☐ | Ícones e cores | Tema claro e escuro | Estados legíveis nos dois |

## 5. `tnrx` no servidor

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | Headnode com `apptainer` | No nó `ssh`/Headnode: `tnrx install singularity` e `tnrx uv sync` | Usa `apptainer pull` e `apptainer exec` (o nome do subcomando continua `singularity`) |
| ☐ | Instalação por `curl` | Num servidor: `curl -fsSL https://raw.githubusercontent.com/recod-ai/tnrx/main/install.sh | bash` | Comandos em `~/.local/bin` apontando para `~/.local/share/tnrx`, `uv` instalado e `~/.tnrx/sifs/nvidia_cuda_12.6.3-cudnn-runtime-ubuntu24.04.sif` baixado. Se o repositório for privado, anote o que foi preciso |
| ☐ | Perguntas do instalador por `curl` | `curl ... | bash` num terminal, no servidor e no laptop | As perguntas aparecem e leem a resposta do teclado (mesmo com a entrada do script vindo do `curl`); as sugestões batem com a máquina |
| ☐ | Extensão escolhida e depois desmarcada | No laptop: instale com a extensão, depois `tnrx-connect update --choose` respondendo não para ela | A extensão aparece no VS Code e depois é removida |
| ☐ | `tnrx update` com uma montagem ativa | Com uma pasta montada pelo `tnrx-connect` no laptop, rode `tnrx-connect update` | Atualiza e mostra o que mudou; a montagem e os snapshots continuam (`tnrx-connect status`) |
| ☐ | Migração da instalação antiga | Num servidor com `~/.local/bin/tnrx` apontando para `~/tnrx`, rode o `curl` | Os links passam a apontar para `~/.local/share/tnrx`; depois disso a pasta `~/tnrx` pode ser apagada |
| ☐ | Menu numa pasta sem imagem | Num projeto sem `.sif`: `tnrx uv sync` e Enter | Cria o link para a imagem padrão e o `uv sync` segue |
| ☐ | Build do `tnrx.def` | Num projeto com `tnrx.def` (copiado do modelo): `tnrx install singularity` no Abaporu e no Headnode | Gera a imagem no banco com `build --fakeroot` (nome `..._def-<hash>.sif`). Se o servidor não permitir fakeroot, a mensagem sugere gerar em outra máquina |
| ☐ | Banco fora do `/home` | `export TNRX_SIF_DIR=/hadatasets/$USER/sifs` e `tnrx install` | A imagem vai para lá, e o job no nó de GPU a encontra pelo link |
| ☐ | Imagem padrão nova | Depois do menu, `tnrx uvslurm python deep_check.py` (com `torch` no `.venv`) | A GPU aparece no PyTorch |
| ☐ | Python baixado pelo `uv` | Num projeto novo com a imagem padrão: `tnrx uv sync`, depois `tnrx uvslurm python -c "import sys; print(sys.executable)"` | O caminho aponta para o `.venv` do projeto, e o Python por trás dele fica em `~/.local/share/uv/python/` (o nó de GPU enxerga o `$HOME`) |
| ☐ | Jupyter com a imagem padrão | `tnrx uv add jupyterlab ipykernel` e `tnrx-connect jupyter` → `n` | O Jupyter sobe do `.venv` (a imagem não tem Jupyter próprio) e o kernel `Python (TNRX-<pasta>)` aparece |
| ☐ | `tnrx hf` com a imagem padrão | `tnrx uv add huggingface-hub` e `tnrx hf model <repo pequeno>` | Baixa para o `HUB_ROOT` do servidor |
| ☐ | Runtime inexistente | Rode o `tnrx` numa máquina sem o runtime do `tnrx_hosts.conf` | Mensagem clara: `'<runtime>' não foi encontrado nesta máquina` |
| ☐ | `.sif` ausente | Rode `tnrx uv sync` numa pasta sem `.sif` | Aborta com `Nenhum arquivo .sif encontrado` (exit 1) |
| ☐ | Jupyter mostra o nó certo | `tnrx uvslurm jupyter lab` | A URL sai com `http://<nó>:<porta>` em vez de `http://hostname:8888` |
| ☐ | `TNRX_JUPYTER_PORT` chega ao job | `TNRX_JUPYTER_PORT=9000 tnrx uvslurm jupyter lab` | Ele usa a porta 9000; se não usar, a variável não atravessa o `srun`/container |
| ☐ | JAX (cuDNN) | `tnrx uv add "jax[cuda12]"` e `tnrx uvslurm python deep_check_jax.py` | Backend `gpu`, matmul e **convolução (cuDNN)** OK. A imagem padrão traz o cuDNN 9; se só a convolução falhar, o JAX pode estar pedindo outra versão |
