# TNRX para VS Code

Barra lateral com o estado do [`tnrx-connect`](../docs/tnrx-connect.md): o que está montado, a configuração Slurm de cada projeto, as GPUs livres no cluster e os Jupyters no ar. Ela só mostra o que o `tnrx-connect --json` informa ([contrato](../docs/tnrx-connect-json.md)): toda a lógica continua no `tnrx-connect`.

**Ela nunca pede senha nem 2FA.** Login, montagem e o terminal do servidor abrem num terminal integrado rodando o próprio `tnrx-connect`, e é lá que você digita a senha.

## Instalar

Requer o `tnrx-connect` instalado no laptop ([instruções](../docs/tnrx-connect.md#instalação)) e o VS Code 1.90 ou mais novo. Não precisa de Node nem npm.

```bash
cd vscode
python3 build-vsix.py                                  # gera dist/tnrx-0.1.0.vsix
code --install-extension dist/tnrx-0.1.0.vsix
```

Recarregue a janela (*Developer: Reload Window*). O ícone **TNRX** aparece na barra de atividades. Para atualizar, gere e instale de novo.

## Os quatro blocos

| Bloco | O que mostra | Botões |
| --- | --- | --- |
| **Montagens** | Cada pasta do `tnrx-connect`: ✔ montada, ⚠ montada sem conexão (rede caiu), ✖ montagem caiu (rclone parado), ○ desmontada | Terminal do servidor (`tnrx-connect ssh`), Reconectar ou Montar (terminal com `tnrx-connect mount`, onde vai a senha/2FA), Desmontar. No menu de contexto: abrir a pasta numa janela nova, ver o log. No título: **+** monta uma pasta nova |
| **Configuração Slurm** | Os valores efetivos do `tnrx_slurm.conf` de cada pasta montada; `(padrão)` quando a chave não está no arquivo e vale o padrão do `tnrx` | Editar (cria o arquivo com os valores atuais, se ainda não existir). Clicar numa chave também abre o arquivo |
| **Cluster** | Por servidor com pasta montada: cada partição com GPUs livres/total, nós livres e tempo máximo; e **Meus jobs** (rodando/na fila, com o projeto de cada um) | Reconectar, num servidor sem conexão |
| **Jupyter** | Por projeto: os Jupyters no ar (nó:porta, job, idade, se a ponte está aberta) | Terminal com `tnrx-connect jupyter` (listar, iniciar, conectar); copiar a URL de uma ponte aberta |

Montagens e Jupyter atualizam a cada 30 s (o Jupyter só com o bloco visível); montar e desmontar aparecem na hora. O Cluster roda `sinfo` no headnode compartilhado, então só atualiza com o bloco visível, a cada 5 minutos ou no botão ↻.

## Configurações

| Chave | Padrão | O que faz |
| --- | --- | --- |
| `tnrx.connectPath` | vazio | Caminho do `tnrx-connect`. Vazio: procura no `PATH` e em `~/.local/bin` (o VS Code aberto pelo menu do sistema nem sempre herda o `PATH` do shell) |
| `tnrx.refreshInterval` | `30` | Segundos entre atualizações de Montagens e Jupyter |
| `tnrx.clusterRefreshInterval` | `300` | Segundos entre consultas ao Cluster; `0` = só no botão |

Os erros do `tnrx-connect` aparecem no próprio bloco e no painel **Output → TNRX**.

## Desenvolvimento

* `node --test test/`: testes. Carregam o `extension.js` de verdade com um módulo `vscode` falso (`test/fake-vscode.js`) e um `tnrx-connect` falso; não precisam do VS Code nem de npm.
* `node tools/print-tree.js`: desenha no terminal os quatro blocos com os dados reais deste computador, para conferir sem abrir o VS Code.
* Código: `src/model.js` (JSON → itens das árvores, funções puras), `src/cli.js` (roda o `tnrx-connect`), `src/extension.js` (vistas, comandos, atualização).
