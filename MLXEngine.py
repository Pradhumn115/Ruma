

from dotenv import load_dotenv
import os
from mlx_wrapper import ChatMLX
from langchain_community.llms.mlx_pipeline import MLXPipeline





load_dotenv()  # Loads from .env

model_directory = os.getenv("HF_HOME")

base_dir = os.path.dirname(os.path.abspath(__file__))

# model_id = f"{model_directory}/Llama-3.2-3B-Instruct-4bit"
model_id = os.path.join(base_dir, model_directory, "Llama-3.2-3B-Instruct-4bit")



class MLXLLM:
    """
    A class to handle MLX model loading and interaction.
    
    This class provides methods to load a model from a specified model ID,
    bind tools, and generate text using the MLX pipeline.
    """
    
    
    def __init__(self, model_id = model_id, **kwargs):
        
        
        self.model_id = model_id
        self.model = None
        self.kwargs = kwargs
        print(self.kwargs)
        # self.load_model()

    async def load_model(self):
        """Load the MLX model from the specified model ID."""
        
        # model = MLXPipeline.from_model_id(model_id=self.model_id,pipeline_kwargs=self.kwargs)
        model = MLXPipeline.from_model_id(model_id=self.model_id)
        llm = ChatMLX(llm = model)
        self.llm = llm
        print(f"Model loaded successfully: {self.model_id}")
        return llm
    


