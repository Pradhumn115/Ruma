"""
LLM Provider Interface
======================

Provides a consistent interface for accessing the current LLM across different 
execution contexts and startup methods.
"""

from typing import Optional, Any
import sys

class LLMProvider:
    """Singleton provider for accessing the current LLM instance."""
    
    _instance: Optional['LLMProvider'] = None
    _current_llm: Optional[Any] = None
    _model_ready: bool = False
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def set_llm(self, llm: Any, model_ready: bool = True):
        """Set the current LLM instance."""
        self._current_llm = llm
        self._model_ready = model_ready
        print(f"🔗 LLM Provider updated: model_ready={model_ready}, llm={llm is not None}")
    
    def get_llm(self) -> Optional[Any]:
        """Get the current LLM instance with fallback methods."""
        # Method 1: Use our stored instance
        if self._current_llm is not None and self._model_ready:
            return self._current_llm
        
        # Method 2: Try to get from unified_app module (fallback for existing code)
        try:
            if 'unified_app' in sys.modules:
                unified_app = sys.modules['unified_app']
                model_ready = getattr(unified_app, 'model_ready', False)
                if model_ready:
                    current_llm = getattr(unified_app, 'current_llm', None)
                    if current_llm:
                        # Update our cache
                        self._current_llm = current_llm
                        self._model_ready = True
                        return current_llm
                    
                    # Try model manager as backup
                    model_manager = getattr(unified_app, 'model_manager', None)
                    if model_manager:
                        current_model = getattr(model_manager, 'current_model', None)
                        if current_model:
                            self._current_llm = current_model
                            self._model_ready = True
                            return current_model
        except Exception as e:
            print(f"⚠️ LLM Provider fallback failed: {e}")
        
        return None
    
    def is_ready(self) -> bool:
        """Check if LLM is ready and available."""
        return self.get_llm() is not None
    
    def clear(self):
        """Clear the current LLM instance."""
        self._current_llm = None
        self._model_ready = False

# Global singleton instance
_llm_provider = LLMProvider()

def get_llm_provider() -> LLMProvider:
    """Get the global LLM provider instance."""
    return _llm_provider