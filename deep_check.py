import sys

import torch

print("--- VERIFICAÇÃO DE INTEGRIDADE ---")
print(f"Python Path: {sys.executable}")
print(f"PyTorch Version: {torch.__version__}")

# Verifica se o binário do CUDA que o PyTorch usa é o da imagem ou do Conda
print(f"CUDA Available: {torch.cuda.is_available()}")

if torch.cuda.is_available():
    print(f"GPU Model: {torch.cuda.get_device_name(0)}")
    print(f"CUDA Runtime Version: {torch.version.cuda}")

    # Teste de Memória: Criar um tensor grande para forçar a comunicação com o Driver
    try:
        x = torch.randn(1000, 1000, device='cuda')
        print("✅ Teste de alocação de memória: OK")
    except Exception as e:
        print(f"❌ Erro na alocação: {e}")
else:
    print("❌ Erro: PyTorch não encontrou a GPU!")
