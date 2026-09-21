# Validação manual (o que os testes automatizados não cobrem)

Os testes de `test_tnrx.sh` e `test_tnrx_connect.sh` usam `ssh`, `rclone`, `srun` e `tnrx` **falsos**. Esta lista é o que só dá para conferir num servidor real. Marque conforme for validando; se algo falhar, anote a saída do terminal e o resultado de `squeue -u $USER`.

Antes de começar: o `tnrx` novo precisa estar no servidor (`git pull` lá). Ele gera o token do Jupyter e imprime a linha `TNRX_JUPYTER_READY`.

## 1. `tnrx-connect jupyter start`

Ponte automática até o Jupyter que roda num nó de computação. Detalhes de uso: [tnrx-connect.md](tnrx-connect.md#jupyter-no-nó-de-computação).

| ☐ | Caso | Como provocar | Resultado esperado |
| --- | --- | --- | --- |
| ☐ | Caminho feliz | `tnrx-connect jupyter start` | O link aparece, abre no navegador e um notebook executa uma célula |
| ☐ | **Job órfão** (o mais importante) | Com o Jupyter no ar: **(a)** fechar a janela do terminal; **(b)** `kill <pid do tnrx-connect>` em outro terminal; **(c)** `kill -9`; **(d)** desligar o wifi. Depois, `squeue -u $USER` | (a) e (b): o job some em segundos. (c) e (d): pode levar uns 2 min até o `sshd` perceber. **Se o job continuar depois disso, é falha real:** faça `scancel` e anote |
| ☐ | `Ctrl-C` chega ao servidor | Dentro do comando, `Ctrl-C` e depois `y` no prompt do Jupyter; repita com `Ctrl-C` duas vezes | O Jupyter encerra, a ponte fecha e o comando sai. Só se vê com terminal de verdade (a entrada do teclado passa pelo `ssh -tt`) |
| ☐ | Fila cheia | Peça mais GPUs do que há livres no `tnrx_slurm.conf` e rode | Depois de 2 min aparece a dica da fila; `Ctrl-C` na fila cancela o job (`squeue` vazio). Dica: `TNRX_JUPYTER_HINT_SECS=10` antecipa o aviso |
| ☐ | `tnrx` fora do PATH | Antes, `ssh <host> 'bash -lc "command -v tnrx"'` | Se não imprimir nada, o `jupyter start` mostra `command not found`, diz que não veio nó/porta e sai com erro |
| ☐ | `tnrx` desatualizado | Rode sem dar `git pull` no servidor | Sem marcador: dica após 2 min sugerindo atualizar; não abre ponte errada |
| ☐ | Porta local ocupada | Deixe uma ponte manual (`ssh -L 8889:...`) aberta e suba um Jupyter na 8889 | Usa a 8890 e avisa `já estava em uso; usando 8890` |
| ☐ | Duas pontes ao mesmo tempo | Dois `jupyter start` em terminais diferentes | Portas locais diferentes, sem conflito; um logout não desloga o outro |
| ☐ | Nome `*.localhost` | Abra o link com o nome e o link `127.0.0.1` | O nome abre no navegador; no VS Code (Existing Jupyter Server) use o `127.0.0.1` |
| ☐ | Sessão de mount + `jupyter start` | Abra as duas no mesmo host e **saia primeiro da sessão de mount** | **Limitação conhecida:** a sessão de mount fecha a conexão mestra e o Jupyter cai junto (o contador de sessões só conta sessões de mount). Confirme e me avise se incomoda |

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
