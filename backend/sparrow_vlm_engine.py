"""
Sparrow MLX-VLM Engine for Enhanced Vision-Language Processing
Integrates with Sparrow's VLLMExtractor for efficient MLX-based vision models
"""

import os
import asyncio
import logging
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass
import base64
from io import BytesIO
from PIL import Image
import tempfile
from pathlib import Path

# Sparrow imports
try:
    from sparrow_parse.vllm.inference_factory import InferenceFactory
    from sparrow_parse.extractors.vllm_extractor import VLLMExtractor
    SPARROW_AVAILABLE = True
except ImportError:
    SPARROW_AVAILABLE = False
    logging.warning("Sparrow not available. Please install: pip install sparrow-ml")

@dataclass
class VisionModelConfig:
    """Configuration for vision-language models"""
    model_name: str
    method: str = "mlx"
    max_tokens: int = 1024
    temperature: float = 0.7
    supports_vision: bool = True
    model_type: str = "vision-language"

class SparrowVLMEngine:
    """Enhanced Vision-Language Model Engine using Sparrow"""
    
    def __init__(self):
        self.current_model = None
        self.model_inference_instance = None
        self.extractor = None
        self.models_dir = self._get_models_directory()
        self.available_models = self._get_available_vision_models()
        self.logger = logging.getLogger(__name__)
        self.logger.setLevel(logging.DEBUG)
        
        if not SPARROW_AVAILABLE:
            self.logger.error("Sparrow not available. Vision capabilities will be limited.")
    
    def _get_models_directory(self) -> str:
        """Get the local models directory path from downloadManager"""
        try:
            # Try to import and use the downloadManager's models directory
            from downloadManager import download_manager
            return download_manager.get_models_directory()
        except ImportError:
            self.logger.warning("Could not import downloadManager, using fallback paths")
            
        # Fallback: Check for Models directory in the project root
        current_dir = Path(__file__).parent
        models_dir = current_dir.parent / "Models"
        
        if models_dir.exists():
            return str(models_dir)
        
        # Final fallback to default HF cache
        return os.path.expanduser("~/.cache/huggingface/hub")
    
    def _check_local_model(self, model_name: str) -> Optional[str]:
        """Check if a vision model exists locally"""
        self.logger.debug(f"Checking for local vision model: {model_name}")
        self.logger.debug(f"Models directory: {self.models_dir}")
        
        # Convert HF model name to local directory format
        local_name = model_name.replace("/", "--")
        
        # Common vision model naming patterns to check
        variations = [
            local_name,  # Direct conversion: mlx-community--Model-Name
            f"models--{local_name}",  # HF cache format
            local_name.replace("mlx-community--", ""),  # Without mlx-community prefix
            model_name.split("/")[-1] if "/" in model_name else model_name,  # Just the model name part
        ]
        
        # Also check subdirectory structure (mlx-community/ModelName)
        if "/" in model_name:
            org, model = model_name.split("/", 1)
            variations.append(f"{org}/{model}")  # mlx-community/Qwen2.5-VL-3B-Instruct-4bit
        
        self.logger.debug(f"Checking variations: {variations}")
        
        # First check the Models directory (this is the main purpose)
        for variation in variations:
            check_path = Path(self.models_dir) / variation
            self.logger.debug(f"Checking path: {check_path}")
            
            if check_path.exists() and check_path.is_dir():
                self.logger.debug(f"Directory exists: {check_path}")
                # List contents for debugging
                contents = list(check_path.iterdir())
                self.logger.debug(f"Directory contents: {[f.name for f in contents]}")
                
                # Verify it's a valid model directory (has config or safetensors files)
                has_config = any(check_path.glob("config.json"))
                has_model_files = any(check_path.glob("*.safetensors")) or any(check_path.glob("model.safetensors.index.json"))
                
                self.logger.debug(f"Has config: {has_config}, Has model files: {has_model_files}")
                
                if has_config and has_model_files:
                    self.logger.info(f"✅ Found valid local vision model: {check_path}")
                    return str(check_path)
                elif has_config or has_model_files:
                    self.logger.debug(f"Partial model found at {check_path} - may be incomplete")
                else:
                    self.logger.debug(f"Directory exists but invalid model structure: {check_path}")
        
        # Also check in HF cache directory if different from Models dir
        hf_cache = os.path.expanduser("~/.cache/huggingface/hub")
        if hf_cache != self.models_dir:
            self.logger.debug(f"Checking HF cache directory: {hf_cache}")
            
            # For HF cache, we need to check the actual HF naming convention
            hf_model_name = f"models--{local_name}"
            hf_path = Path(hf_cache) / hf_model_name
            
            if hf_path.exists() and hf_path.is_dir():
                self.logger.debug(f"Found HF cache directory: {hf_path}")
                # Look for snapshots directory
                snapshots_dir = hf_path / "snapshots"
                if snapshots_dir.exists():
                    self.logger.debug(f"Found snapshots directory: {snapshots_dir}")
                    snapshot_dirs = [d for d in snapshots_dir.iterdir() if d.is_dir()]
                    if snapshot_dirs:
                        # Get the latest snapshot
                        latest_snapshot = max(snapshot_dirs, key=lambda x: x.stat().st_mtime)
                        self.logger.info(f"✅ Found HF cached vision model: {latest_snapshot}")
                        return str(latest_snapshot)
        
        self.logger.info(f"❌ No local vision model found for: {model_name}")
        return None
    
    def _get_available_vision_models(self) -> Dict[str, VisionModelConfig]:
        """Get list of available vision-language models"""
        return {
            "qwen2.5-vl-7b": VisionModelConfig(
                model_name="mlx-community/Qwen2.5-VL-7B-Instruct-8bit",
                method="mlx",
                supports_vision=True,
                model_type="vision-language"
            ),
            "qwen2.5-vl-3b": VisionModelConfig(
                model_name="mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
                method="mlx",
                supports_vision=True,
                model_type="vision-language"
            ),
            "llava-1.5-7b": VisionModelConfig(
                model_name="mlx-community/llava-1.5-7b-hf-4bit",
                method="mlx",
                supports_vision=True,
                model_type="vision-language"
            ),
            "llava-v1.6-mistral-7b": VisionModelConfig(
                model_name="mlx-community/llava-v1.6-mistral-7b-hf-4bit",
                method="mlx",
                supports_vision=True,
                model_type="vision-language"
            )
        }
    
    async def load_model(self, model_key: str) -> bool:
        """Load a specific vision model"""
        if not SPARROW_AVAILABLE:
            self.logger.error("Cannot load model: Sparrow not available")
            return False
            
        if model_key not in self.available_models:
            self.logger.error(f"Model {model_key} not found in available models")
            return False
        
        try:
            model_config = self.available_models[model_key]
            self.logger.info(f"Loading vision model: {model_key} -> {model_config.model_name}")
            
            # Check for local model first
            local_model_path = self._check_local_model(model_config.model_name)
            
            if local_model_path:
                self.logger.info(f"✅ Using local vision model: {local_model_path}")
                model_name = local_model_path
            else:
                self.logger.warning(f"⚠️ Local model not found, using HuggingFace: {model_config.model_name}")
                self.logger.warning(f"⚠️ This will download the model from HuggingFace!")
                model_name = model_config.model_name
            
            # Initialize extractor
            self.extractor = VLLMExtractor()
            
            # Configure backend with potentially local path
            config = {
                "method": model_config.method,
                "model_name": model_name
            }
            
            # Create inference instance
            factory = InferenceFactory(config)
            self.model_inference_instance = factory.get_inference_instance()
            self.current_model = model_key
            
            self.logger.info(f"Successfully loaded vision model: {model_key} from {'local path' if local_model_path else 'HuggingFace'}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to load model {model_key}: {str(e)}")
            return False
    
    async def analyze_image_with_text(self, image_data: bytes, text_prompt: str) -> str:
        """Analyze image with text prompt using Sparrow VLM"""
        if not self.model_inference_instance or not self.extractor:
            return "Vision model not loaded. Please load a vision model first."
        
        try:
            # Save image data to temporary file
            temp_file = await self._save_temp_image(image_data)
            
            # Prepare input data for Sparrow
            input_data = [{
                "file_path": temp_file,
                "text_input": text_prompt
            }]
            
            # Run inference
            results, num_pages = self.extractor.run_inference(
                self.model_inference_instance,
                input_data,
                debug=False
            )
            
            # Clean up temp file
            os.unlink(temp_file)
            
            if results and len(results) > 0:
                return results[0]
            else:
                return "No analysis result generated"
                
        except Exception as e:
            self.logger.error(f"Vision analysis failed: {str(e)}")
            return f"Vision analysis failed: {str(e)}"
    
    async def analyze_screen_with_context(self, 
                                        image_data: bytes, 
                                        extracted_text: str, 
                                        user_question: str) -> str:
        """Enhanced screen analysis combining vision and extracted text"""
        
        enhanced_prompt = f"""
You are an expert screen analysis assistant. Analyze the provided screenshot and answer the user's question.

EXTRACTED TEXT FROM SCREEN:
{extracted_text}

USER'S QUESTION:
{user_question}

Please provide a comprehensive analysis that:
1. Describes what you see in the image
2. References the extracted text context
3. Directly answers the user's question
4. Provides actionable insights or suggestions

Focus on being helpful and specific in your response.
"""
        
        return await self.analyze_image_with_text(image_data, enhanced_prompt)
    
    async def _save_temp_image(self, image_data: bytes) -> str:
        """Save image data to temporary file"""
        try:
            # Create temporary file
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as temp_file:
                temp_file.write(image_data)
                return temp_file.name
        except Exception as e:
            self.logger.error(f"Failed to save temp image: {str(e)}")
            raise
    
    def get_model_info(self) -> Dict[str, Any]:
        """Get information about available and current models"""
        return {
            "current_model": self.current_model,
            "available_models": {
                key: {
                    "model_name": config.model_name,
                    "method": config.method,
                    "supports_vision": config.supports_vision,
                    "model_type": config.model_type
                }
                for key, config in self.available_models.items()
            },
            "sparrow_available": SPARROW_AVAILABLE
        }
    
    async def unload_model(self):
        """Unload current model to free memory"""
        self.model_inference_instance = None
        self.extractor = None
        self.current_model = None
        self.logger.info("Vision model unloaded")
    
    def is_model_loaded(self) -> bool:
        """Check if a vision model is currently loaded"""
        return self.model_inference_instance is not None and self.extractor is not None

# Global instance
sparrow_vlm_engine = SparrowVLMEngine()

async def analyze_image_with_sparrow(image_data: bytes, 
                                   extracted_text: str, 
                                   user_question: str) -> Tuple[str, bool]:
    """
    Main function to analyze images using Sparrow VLM
    Returns (analysis_result, success)
    """
    try:
        # Ensure a model is loaded
        if not sparrow_vlm_engine.is_model_loaded():
            logging.info("No vision model loaded, attempting to load default model...")
            
            # Try to load default model (using local if available)
            success = await sparrow_vlm_engine.load_model("qwen2.5-vl-3b")
            if not success:
                logging.error("Failed to load default vision model")
                return "Failed to load vision model. Please ensure Sparrow MLX-VLM models are available locally.", False
        
        # Log that we're performing analysis
        logging.info(f"Performing vision analysis with model: {sparrow_vlm_engine.current_model}")
        
        # Perform analysis
        result = await sparrow_vlm_engine.analyze_screen_with_context(
            image_data, extracted_text, user_question
        )
        
        return result, True
        
    except Exception as e:
        logging.error(f"Sparrow vision analysis failed: {str(e)}")
        return f"Vision analysis failed: {str(e)}", False

if __name__ == "__main__":
    # Test the engine
    async def test_engine():
        engine = SparrowVLMEngine()
        print("Available models:", engine.get_model_info())
        
        if SPARROW_AVAILABLE:
            success = await engine.load_model("qwen2.5-vl-3b")
            print(f"Model loaded: {success}")
        else:
            print("Sparrow not available for testing")
    
    asyncio.run(test_engine())