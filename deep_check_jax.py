import os
import sys

import jax
import jax.numpy as jnp

print("--- VERIFICAÇÃO DE INTEGRIDADE (JAX) ---")
print(f"Python Path: {sys.executable}")
print(f"JAX Version: {jax.__version__}")
print(f"LD_LIBRARY_PATH: {os.environ.get('LD_LIBRARY_PATH', '(vazio)')}")

backend = jax.default_backend()
devices = jax.devices()
print(f"Backend: {backend}")
print(f"Devices: {devices}")

if backend != "gpu":
    print("❌ Erro: JAX não encontrou a GPU (rodando em CPU)!")
    print("   Instale a variante com CUDA: tnrx uv add 'jax[cuda12]'")
    sys.exit(1)

print(f"GPU Model: {devices[0].device_kind}")

try:
    x = jax.random.normal(jax.random.PRNGKey(0), (1000, 1000))
    (x @ x).block_until_ready()
    print("✅ Teste de alocação e matmul: OK")
except Exception as e:
    print(f"❌ Erro na alocação/matmul: {e}")
    sys.exit(1)

# Convolução exercita o cuDNN: é onde uma versão da imagem em conflito com a do
# wheel costuma aparecer (matmul sozinho passa mesmo com cuDNN quebrado).
try:
    img = jnp.ones((1, 3, 32, 32))
    kernel = jnp.ones((8, 3, 3, 3))
    out = jax.lax.conv(img, kernel, (1, 1), "SAME")
    out.block_until_ready()
    print("✅ Teste de convolução (cuDNN): OK")
except Exception as e:
    print(f"❌ Erro na convolução (cuDNN): {e}")
    sys.exit(1)
