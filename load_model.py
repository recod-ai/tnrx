import torch
import argparse
import sys
import os
from transformers import AutoModel

def load_and_verify_model(model_path):
    try:
        # Verifica se o diretório existe antes de tentar carregar
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"O caminho especificado não existe: {model_path}")

        print(f"🔄 Carregando modelo de: {model_path}...")
        
        # Carrega o modelo (adicionado device_map="auto" para melhor gestão de memória)
        model = AutoModel.from_pretrained(
            model_path, 
            trust_remote_code=True
        )
        
        # --- VERIFICAÇÕES ---
        num_params = sum(p.numel() for p in model.parameters())
        print(f"✅ Sucesso! Modelo instanciado.")
        print(f"📊 Total de parâmetros: {num_params:,}")
        
        # Move para GPU se disponível
        device = "cuda" if torch.cuda.is_available() else "cpu"
        model.to(device)
        print(f"🚀 Modelo movido para: {device.upper()}")
        
        return model

    except Exception as e:
        print(f"❌ Erro ao carregar o modelo: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Configuração do Argument Parser
    parser = argparse.ArgumentParser(description="Carregar e verificar modelos do Hugging Face localmente.")
    
    # Define o argumento obrigatório
    parser.add_argument(
        "model_path", 
        type=str, 
        help="Caminho absoluto para a pasta do modelo no /data/"
    )

    args = parser.parse_args()

    # Executa a função
    model = load_and_verify_model(args.model_path)