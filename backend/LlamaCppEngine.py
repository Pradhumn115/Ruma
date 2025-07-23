from dotenv import load_dotenv
import os
import glob
from llamacpp_wrapper import ChatLlamaCpp

load_dotenv()  # Loads from .env

model_directory = os.getenv("HF_HOME", "Models")
base_dir = os.path.dirname(os.path.abspath(__file__))

class LlamaCppLLM:
    """
    A class to handle LlamaCpp model loading and interaction.
    
    This class provides methods to load a GGUF model from a specified model path,
    and generate text using the llama-cpp-python library.
    """
    
    def __init__(self, model_path=None, **kwargs):
        self.model_path = model_path
        self.model = None
        self.kwargs = kwargs
        print(f"LlamaCppLLM initialized with kwargs: {self.kwargs}")

    def find_gguf_model(self, model_id):
        """Find a GGUF model file in the specified directory."""
        if self.model_path and os.path.exists(self.model_path):
            return self.model_path
            
        # Try to find GGUF file in the model directory
        possible_paths = [
            os.path.join(base_dir, model_directory, model_id),
            os.path.join(base_dir, model_directory, model_id, "*.gguf"),
            model_id,
        ]
        
        for path_pattern in possible_paths:
            if os.path.isfile(path_pattern) and path_pattern.endswith('.gguf'):
                return path_pattern
            elif os.path.isdir(path_pattern):
                # Look for GGUF files in the directory
                gguf_files = glob.glob(os.path.join(path_pattern, "*.gguf"))
                if gguf_files:
                    return gguf_files[0]  # Return the first GGUF file found
            else:
                # Try glob pattern
                gguf_files = glob.glob(path_pattern)
                if gguf_files:
                    # Filter for .gguf files
                    gguf_files = [f for f in gguf_files if f.endswith('.gguf')]
                    if gguf_files:
                        return gguf_files[0]
        
        raise FileNotFoundError(f"No GGUF model found for: {model_id}")

    async def load_model(self, model_id=None):
        """Load the LlamaCpp model from the specified model path."""
        
        if model_id:
            model_path = self.find_gguf_model(model_id)
        elif self.model_path:
            model_path = self.model_path
        else:
            raise ValueError("Either model_id or model_path must be provided")
        
        # Initialize the ChatLlamaCpp wrapper
        llm = ChatLlamaCpp(
            model_path=model_path,
            **self.kwargs
        )
        
        self.llm = llm
        print(f"LlamaCpp model loaded successfully from: {model_path}")
        return llm

    def set_model_path(self, model_path):
        """Set the model path for this engine."""
        self.model_path = model_path

    def get_model_info(self):
        """Get information about the loaded model."""
        if self.model_path:
            return {
                "model_path": self.model_path,
                "model_type": "gguf",
                "engine": "llamacpp",
                "exists": os.path.exists(self.model_path) if self.model_path else False,
            }
        return None