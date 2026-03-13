Marcos, seu tutorial já está muito bom e prático. Para melhorá-lo, vou aplicar a honestidade que você pediu: o ponto fraco atual é a **confusão entre o Python do sistema e o do venv** que estávamos resolvendo.

Vou refinar o guia focando na **metodologia declarativa** do `uv` (usando `pyproject.toml`) e na correção definitiva do Kernel, que é onde a maioria dos usuários de HPC trava.

---

## 🚀 Guia Definitivo: ML no Slurm com Apptainer & UV

### 1. Preparação da Imagem Base (Headnode)

Imagens da NVIDIA NGC são pesadas. Baixe no Headnode para evitar estourar a RAM dos nós de computação.

```bash
# Baixa e converte para .sif
apptainer pull pytorch_latest.sif docker://nvcr.io/nvidia/pytorch:24.01-py3

```

### 2. O Wrapper Mágico: `uvapp.sh`

Em vez de comandos longos, use o script para garantir que o `uv` (no host) converse com o Python (no container).

```bash
# Instale o uv no host primeiro
./uvapp.sh install

# Inicialize o projeto (cria o pyproject.toml)
./uvapp.sh init

# Adicione suas libs (o uv resolve dependências e cria o .venv)
./uvapp.sh add jax jaxlib ipykernel lightning

```

---

### 3. Comandos Rápidos com `./uvapp.sh`

Agora que o wrapper está configurado, esqueça o `source .venv/bin/activate`. Use a sintaxe direta:

| Objetivo | Comando |
| --- | --- |
| **Instalar Lib** | `./uvapp.sh add nome-da-lib` |
| **Remover Lib** | `./uvapp.sh remove nome-da-lib` |
| **Sincronizar** | `./uvapp.sh sync` (Usa o `uv.lock` para recriar o ambiente) |
| **Rodar Script** | `./uvapp.sh run python train.py` |
| **Abrir Jupyter** | `./uvapp.sh run jupyter lab --ip=0.0.0.0 --no-browser` |

---

### 4. O Kernel do Jupyter

Instale o `ipykernel` usando uv e inicie o servidor jupyter dentro do slurm:

```bash
./uvapp.sh add ipykernel
srun --pty --gres=gpu:1 --mem=20G ./uvapp.sh run jupyter lab --ip=0.0.0.0 --no-browser
```

Caso o Jupyter esteja usando o Python errado (`/usr/bin/python`), registramos um kernel apontando para o caminho absoluto do seu projeto.

```bash
# 1. Registra o kernel
./uvapp.sh run python -m ipykernel install --user --name uv-ml --display-name "Python (Apptainer+UV)"
```

Você poderá selecionar o kernel `Python (Apptainer+UV)` nos notebooks.

**Criando ponte para a porta:** Para usar o notebook, primeiro crie uma ponte para a porta `ssh -L 8888:dl-01:8888 username@headnode`.

**No Jupyter do VS Code:** Ao abrir um `.ipynb`, mude o kernel no canto superior direito usando o `localhost:8888` e coloque a senha fornecida.

---

### 5. Desenvolvimento no VS Code (Remote-SSH)

Para ter autocomplete e não ver erros de "import not found":

1. No VS Code, `Ctrl+Shift+P` -> **Python: Select Interpreter**.
2. Escolha **Enter interpreter path...**.
3. Cole o caminho completo: `/home/marcos/.../projeto/.venv/bin/python`.

---

### 6. Execução em Produção (Slurm)

#### Interativo (Debug/Jupyter)

```bash
srun --pty --gres=gpu:1 --mem=20G ./uvapp.sh run jupyter lab --ip=0.0.0.0 --no-browser

```

#### Batch (Treino Longo) - `job.slurm`

```bash
#!/bin/bash
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=10

# O uvapp.sh run cuida de ativar o ambiente e usar a GPU
./uvapp.sh run python train.py --epochs 100

```

---

### Por que este fluxo é superior?

1. **Reprodutibilidade:** O arquivo `uv.lock` garante que seu colega terá as mesmas versões que você.
2. **Velocidade:** O `uv` instala bibliotecas em segundos, enquanto o `pip` levaria minutos.
3. **Isolamento:** Você nunca mexe no Python do sistema ou da imagem da NVIDIA.
4. **Simplicidade:** O `./uvapp.sh` esconde a complexidade do Apptainer, fazendo o container parecer um ambiente Python local comum.