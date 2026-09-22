# Validação manual (o que os testes automatizados não cobrem)

Os testes de `test_tnrx.sh` e `test_tnrx_connect.sh` usam `ssh`, `rclone`, `srun` e `tnrx` **falsos**. Esta lista é o que só dá para conferir num servidor real. Marque conforme for validando; se algo falhar, anote a saída do terminal e o resultado de `squeue -u $USER`.

Antes de começar: o `tnrx` novo precisa estar no servidor (`git pull` lá). Ele gera o token do Jupyter e grava `.tnrx/jupyter/<job>.env` quando o Jupyter começa a responder.

## 1. `tnrx-connect jupyter` (descoberta automática)

Você inicia o Jupyter no servidor (`tnrx uvslurm jupyter lab`, na raiz do projeto, aba 1) e o `tnrx-connect jupyter` (aba 2, dentro da pasta montada) descobre qual está no ar e abre a ponte. Detalhes de uso: [tnrx-connect.md](tnrx-connect.md#jupyter-no-nó-de-computação).

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
| ☐ | Sessão de mount fecha antes | Abra o mount e o `jupyter` no mesmo host e **saia primeiro da sessão de mount** | **Limitação conhecida:** a sessão de mount fecha a conexão mestra e a ponte cai (o contador de sessões só conta sessões de mount). Confirme e me avise se incomoda |
| ☐ | `tnrx` antigo no servidor | Sem `git pull` no servidor | `Nenhum servidor Jupyter no ar` (não há registro). A forma manual `tnrx-connect jupyter <URL>` funciona |
| ☐ | Iniciado numa subpasta | Rode `tnrx uvslurm jupyter lab` dentro de uma subpasta do projeto | O registro fica na subpasta e o `tnrx-connect jupyter` não o acha (ele lê a raiz). Confirme e me avise se incomoda |

**Já validado no servidor real:**

| ☑ | Caso | Resultado |
| --- | --- | --- |
| ☑ | `Ctrl-C` chega ao servidor (2026-09-21, Headnode) | Chega ao `srun` (`interrupt (one more within 1 sec to abort)`); o job é cancelado (`STEP ... CANCELLED`). O prompt `y/n` do Jupyter **não** aparece: o `srun` intercepta. Falta conferir `squeue -u $USER` vazio depois |

## 2. Modo mount (`tnrx-connect`)

Já funcionou com o `rclone` real (v1.75.0) montando o Headnode. Falta validar:

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | Senha/2FA uma única vez | Abra o Abaporu (2FA) | O 2FA é pedido só uma vez; o `rclone` reaproveita a conexão pelo `ControlPath` |
| ☐ | Queda de rede com escrita pendente | Salve um arquivo na pasta montada, desligue a rede, religue e rode `tnrx-connect` de novo | O arquivo sobe na próxima montagem (o cache é persistente) |
| ☐ | Desempenho | `git status` e `grep -r` numa pasta grande montada | Tempo aceitável; anote se for lento |
| ☐ | Terminal aberto antes do mount | Rode `tnrx-connect` numa pasta em que o terminal já estava | O aviso pede `cd .`; depois disso o mount aparece |
| ☐ | macOS / macFUSE | Rodar num Mac | Ainda não suportado: `is_mounted` lê `/proc/mounts` e o desmonte usa `fusermount3` |

## 3. `tnrx` no servidor

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | Headnode com `apptainer` | No nó `ssh`/Headnode: `tnrx uv sync` e `tnrx install singularity` | Usa `apptainer exec` e `apptainer pull` (o nome do subcomando continua `singularity`) |
| ☐ | Runtime inexistente | Rode o `tnrx` numa máquina sem o runtime do `tnrx_hosts.conf` | Mensagem clara: `'<runtime>' não foi encontrado nesta máquina` |
| ☐ | `.sif` ausente | Rode `tnrx uv sync` numa pasta sem `.sif` | Aborta com `Nenhum arquivo .sif encontrado` (exit 1) |
| ☐ | Jupyter mostra o nó certo | `tnrx uvslurm jupyter lab` | A URL sai com `http://<nó>:<porta>` em vez de `http://hostname:8888` |
| ☐ | `TNRX_JUPYTER_PORT` chega ao job | `TNRX_JUPYTER_PORT=9000 tnrx uvslurm jupyter lab` | Ele usa a porta 9000; se não usar, a variável não atravessa o `srun`/container |
| ☐ | JAX (cuDNN) | `tnrx uv add "jax[cuda12]"` e `tnrx uvslurm python deep_check_jax.py` | Backend `gpu`, matmul e **convolução (cuDNN)** OK. Se só a convolução falhar, o cuDNN da imagem NGC (versão 8, se não me engano) pode estar em conflito com o do JAX: considere uma imagem sem CUDA embutido (`tnrx install singularity <nome>.sif <url-docker>`) |
