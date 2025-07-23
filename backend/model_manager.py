"""Model Manager for handling both MLX and LlamaCpp engines."""

import os
import glob
from typing import Optional, Dict, Any, Union, List
from enum import Enum
from dotenv import load_dotenv

from MLXEngine import MLXLLM
from LlamaCppEngine import LlamaCppLLM
from api_model_wrapper import APIModelWrapper

# Import API key manager to check for available API keys
try:
    from api_key_manager import get_api_key_for_provider
except ImportError:
    get_api_key_for_provider = None

load_dotenv()

class ModelType(Enum):
    MLX = "mlx"
    GGUF = "gguf"
    API = "api"
    UNKNOWN = "unknown"

class ModelSource(Enum):
    LOCAL = "local"
    API = "api"

class ModelManager:
    """
    Unified model manager that can handle MLX, LlamaCpp, and API models.
    Automatically detects model type and uses the appropriate engine.
    Provides clear selection between local and API models.
    """
    
    def __init__(self):
        self.current_model = None
        self.current_engine = None
        self.current_model_type = None
        self.current_model_id = None
        self.current_model_source = None
        self.model_directory, self.base_dir = self._get_writable_model_paths()
        print(f"✅ Using model directory: {self.model_directory}")
        self.default_model = "mlx-community/Llama-3.2-3B-Instruct-4bit"
        self.model_selection_preference = ModelSource.LOCAL  # Default to local models
        
    def _get_writable_model_paths(self):
        """Get writable file paths for model storage"""
        import sys
        from pathlib import Path
        
        if sys.platform == "darwin":  # macOS
            home = Path.home()
            app_support = home / "Library" / "Application Support" / "Ruma"
            app_support.mkdir(parents=True, exist_ok=True)
            
            models_dir = str(app_support / "Models")
            base_dir = str(app_support)
            
            # Ensure Models subdirectory exists
            os.makedirs(models_dir, exist_ok=True)
            
            return models_dir, base_dir
        else:
            # Fallback for development/other platforms
            return "Models", os.path.dirname(os.path.abspath(__file__))
        
    def detect_model_type(self, model_id: str) -> ModelType:
        """
        Detect whether a model is MLX (safetensors) or GGUF format.
        
        Args:
            model_id: Model identifier or path
            
        Returns:
            ModelType enum indicating the detected type
        """
        # Check if it's a direct path to a GGUF file
        if model_id.endswith('.gguf') and os.path.exists(model_id):
            return ModelType.GGUF
            
        # Build possible model paths
        possible_paths = [
            os.path.join(self.base_dir, self.model_directory, model_id),
            model_id,
        ]
        
        for model_path in possible_paths:
            if os.path.exists(model_path):
                if os.path.isfile(model_path):
                    # Single file - check extension
                    if model_path.endswith('.gguf'):
                        return ModelType.GGUF
                elif os.path.isdir(model_path):
                    # Directory - check contents
                    files = os.listdir(model_path)
                    
                    # Check for GGUF files
                    gguf_files = [f for f in files if f.endswith('.gguf')]
                    if gguf_files:
                        return ModelType.GGUF
                    
                    # Check for MLX files (safetensors, config.json, tokenizer files)
                    mlx_indicators = [
                        'model.safetensors',
                        'model.safetensors.index.json',
                        'config.json',
                        'tokenizer.json'
                    ]
                    
                    if any(indicator in files for indicator in mlx_indicators):
                        return ModelType.MLX
        
        # Default assumption based on model_id format
        if '/' in model_id and any(mlx_prefix in model_id for mlx_prefix in ['mlx-community', 'mlx-']):
            return ModelType.MLX
        elif '.gguf' in model_id.lower():
            return ModelType.GGUF
        
        return ModelType.UNKNOWN
    
    def get_available_api_models(self) -> Dict[str, Dict[str, Any]]:
        """Get available API models from configured API keys."""
        if not get_api_key_for_provider:
            return {}
        
        api_models = {}
        providers = ["openai", "claude", "llm_vin"]
        
        for provider in providers:
            api_key = get_api_key_for_provider(provider)
            if api_key:
                # Get models for this provider from API key manager
                try:
                    from api_key_manager import api_key_manager
                    key_info = api_key_manager.get_api_key_info(provider)
                    if key_info and key_info.model:
                        api_models[f"{provider}:{key_info.model}"] = {
                            "provider": provider,
                            "model": key_info.model,
                            "api_key": api_key,
                            "type": "api",
                            "status": key_info.status
                        }
                except ImportError:
                    pass
        
        return api_models
    
    def set_model_preference(self, preference: ModelSource):
        """Set preference for local vs API models."""
        self.model_selection_preference = preference
        print(f"Model preference set to: {preference.value}")
    
    def get_model_path(self, model_id: str, model_type: ModelType) -> str:
        """
        Get the full path to a model based on its ID and type.
        
        Args:
            model_id: Model identifier
            model_type: Type of the model (MLX or GGUF)
            
        Returns:
            Full path to the model
        """
        if model_type == ModelType.GGUF:
            # For GGUF models, find the .gguf file
            possible_paths = [
                model_id,  # Direct path
                os.path.join(self.base_dir, self.model_directory, model_id),
                os.path.join(self.base_dir, self.model_directory, model_id, "*.gguf"),
            ]
            
            for path_pattern in possible_paths:
                if os.path.isfile(path_pattern) and path_pattern.endswith('.gguf'):
                    return path_pattern
                elif os.path.isdir(path_pattern):
                    gguf_files = glob.glob(os.path.join(path_pattern, "*.gguf"))
                    if gguf_files:
                        return gguf_files[0]
                else:
                    gguf_files = glob.glob(path_pattern)
                    if gguf_files:
                        gguf_files = [f for f in gguf_files if f.endswith('.gguf')]
                        if gguf_files:
                            return gguf_files[0]
        
        elif model_type == ModelType.MLX:
            # For MLX models, return the directory path
            possible_paths = [
                os.path.join(self.base_dir, self.model_directory, model_id),
                model_id,
            ]
            
            for path in possible_paths:
                if os.path.exists(path):
                    return path
        
        raise FileNotFoundError(f"Model not found: {model_id}")
    
    def is_model_available(self, model_id: str) -> Dict[str, Any]:
        """
        Check if a model is available locally.
        
        Args:
            model_id: Model identifier
            
        Returns:
            Dictionary with availability info
        """
        model_type = self.detect_model_type(model_id)
        
        if model_type == ModelType.UNKNOWN:
            return {
                "available": False,
                "model_type": "unknown",
                "reason": "Could not detect model type"
            }
        
        try:
            model_path = self.get_model_path(model_id, model_type)
            return {
                "available": True,
                "model_type": model_type.value,
                "model_path": model_path
            }
        except FileNotFoundError:
            return {
                "available": False,
                "model_type": model_type.value,
                "reason": "Model files not found"
            }
    
    async def load_model(self, model_id: str, force_source: Optional[ModelSource] = None, **kwargs) -> Any:
        """
        Load a model using the appropriate engine based on its type and user preference.
        
        Args:
            model_id: Model identifier (can be local model or API model in format "provider:model")
            force_source: Force using specific source (local or api)
            **kwargs: Additional arguments for model loading
            
        Returns:
            Loaded model instance
        """
        model_source = force_source or self.model_selection_preference
        
        # Check if this is an API model ID (format: "provider:model")
        if ":" in model_id and model_source == ModelSource.API:
            return await self._load_api_model(model_id, **kwargs)
        
        # Check if user prefers API models and has available API models
        if model_source == ModelSource.API:
            api_models = self.get_available_api_models()
            if api_models:
                # Try to find a matching API model or use the first available one
                api_model_id = next(iter(api_models.keys()))
                print(f"Using API model instead of local: {api_model_id}")
                return await self._load_api_model(api_model_id, **kwargs)
        
        # Fall back to local model loading
        return await self._load_local_model(model_id, **kwargs)
    
    async def _load_api_model(self, model_id: str, **kwargs) -> Any:
        """Load an API model."""
        if ":" not in model_id:
            raise ValueError(f"API model ID must be in format 'provider:model', got: {model_id}")
        
        provider, model = model_id.split(":", 1)
        
        if not get_api_key_for_provider:
            raise ValueError("API key manager not available")
        
        api_key = get_api_key_for_provider(provider)
        if not api_key:
            raise ValueError(f"No API key found for provider: {provider}")
        
        print(f"Loading API model: {provider}:{model}")
        engine = APIModelWrapper(provider=provider, api_key=api_key, model=model)
        
        # Store current model info
        self.current_model = engine
        self.current_engine = engine
        self.current_model_type = ModelType.API
        self.current_model_id = model_id
        self.current_model_source = ModelSource.API
        
        return engine
    
    async def _load_local_model(self, model_id: str, **kwargs) -> Any:
        """Load a local model (MLX or GGUF)."""
        # Detect model type
        model_type = self.detect_model_type(model_id)
        
        if model_type == ModelType.UNKNOWN:
            raise ValueError(f"Could not detect model type for: {model_id}")
        
        # Get model path
        model_path = self.get_model_path(model_id, model_type)
        
        # Load using appropriate engine
        if model_type == ModelType.MLX:
            print(f"Loading MLX model: {model_id}")
            engine = MLXLLM(model_id=model_path, **kwargs)
            model = await engine.load_model()
            
        elif model_type == ModelType.GGUF:
            print(f"Loading GGUF model: {model_id}")
            engine = LlamaCppLLM(model_path=model_path, **kwargs)
            model = await engine.load_model()
            
        else:
            raise ValueError(f"Unsupported model type: {model_type}")
        
        # Store current model info
        self.current_model = model
        self.current_engine = engine
        self.current_model_type = model_type
        self.current_model_id = model_id
        self.current_model_source = ModelSource.LOCAL
        
        return model
    
    def get_current_model_info(self) -> Optional[Dict[str, Any]]:
        """Get information about the currently loaded model."""
        if not self.current_model:
            return None
        
        engine_map = {
            ModelType.MLX: "mlx",
            ModelType.GGUF: "llamacpp", 
            ModelType.API: "api"
        }
        
        return {
            "model_id": self.current_model_id,
            "model_type": self.current_model_type.value if self.current_model_type else None,
            "model_source": self.current_model_source.value if self.current_model_source else None,
            "engine": engine_map.get(self.current_model_type, "unknown"),
            "loaded": True,
            "preference": self.model_selection_preference.value
        }
    
    def get_api_models(self) -> List[Dict[str, Any]]:
        """Get list of available API models from configured providers."""
        api_models = []
        
        # Get API models from the API key manager
        try:
            from api_key_manager import api_key_manager
            
            # Check each provider for configured API keys
            for provider in ["llm_vin", "openai", "claude"]:
                api_key = api_key_manager.get_api_key(provider)
                if api_key:
                    # Add placeholder models for each configured provider
                    # The actual model fetching happens in the FastAPI endpoints
                    provider_models = {
                        "llm_vin": [
                            "gpt-4o-mini", "gpt-4o", "claude-3-5-sonnet-20241022", 
                            "claude-3-5-haiku-20241022", "gemini-2.0-flash-exp"
                        ],
                        "openai": [
                            "gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo", 
                            "o1-preview", "o1-mini"
                        ],
                        "claude": [
                            "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022",
                            "claude-3-opus-20240229", "claude-3-sonnet-20240229", 
                            "claude-3-haiku-20240307"
                        ]
                    }
                    
                    for model_id in provider_models.get(provider, []):
                        api_models.append({
                            "model_id": f"{provider}:{model_id}",
                            "model_type": "api",
                            "model_source": "api",
                            "provider": provider,
                            "engine": f"api_{provider}",
                            "loaded": False,
                            "available": True,
                            "display_name": model_id
                        })
                        
        except ImportError:
            print("API key manager not available for API models")
        except Exception as e:
            print(f"Error fetching API models: {e}")
        
        return api_models
    
    def unload_model(self):
        """Unload the current model and free memory."""
        # Note: Both MLX and llama-cpp-python should handle memory management automatically
        # due to Apple's unified memory architecture, but we can clear our references
        self.current_model = None
        self.current_engine = None
        self.current_model_type = None
        self.current_model_id = None
        print("Model unloaded")
    
    def switch_model(self, model_id: str, **kwargs) -> Any:
        """
        Switch to a different model.
        
        Args:
            model_id: New model identifier
            **kwargs: Additional arguments for model loading
            
        Returns:
            Loaded model instance
        """
        # Unload current model
        if self.current_model:
            self.unload_model()
        
        # Load new model
        return self.load_model(model_id, **kwargs)