"""API Key Management System for Ruma AI."""

import os
import json
import asyncio
from typing import Dict, Optional, List, Any
from datetime import datetime
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import aiohttp
from cryptography.fernet import Fernet
import base64

app = APIRouter()

# Get writable paths for bundled app (inline solution)
def get_writable_paths():
    """Get writable file paths for API key management"""
    import sys
    from pathlib import Path
    
    if sys.platform == "darwin":  # macOS
        home = Path.home()
        app_support = home / "Library" / "Application Support" / "Ruma"
        app_support.mkdir(parents=True, exist_ok=True)
        
        encryption_key_file = str(app_support / ".encryption_key")
        api_keys_file = str(app_support / "api_keys.json")
        
        print(f"✅ Using writable API key paths: {app_support}")
        return encryption_key_file, api_keys_file
    else:
        # Fallback for development/other platforms
        print("⚠️ Using local file paths (development mode)")
        return "./.encryption_key", "./api_keys.json"

# Get writable paths
ENCRYPTION_KEY_FILE, API_KEYS_FILE = get_writable_paths()

class APIKeyRequest(BaseModel):
    provider: str  # "llm_vin", "openai", "claude"
    api_key: str
    name: Optional[str] = None
    model: Optional[str] = None

class APIKeyInfo(BaseModel):
    provider: str
    name: str
    masked_key: str
    created_at: str
    last_tested: Optional[str] = None
    status: str  # "active", "invalid", "untested"
    model: Optional[str] = None

class APIKeyManager:
    """Secure API key management with encryption."""
    
    def __init__(self):
        self.encryption_key = self._get_or_create_encryption_key()
        self.cipher = Fernet(self.encryption_key)
        self.api_keys = self._load_api_keys()
    
    def _get_or_create_encryption_key(self) -> bytes:
        """Get or create encryption key for API keys."""
        if os.path.exists(ENCRYPTION_KEY_FILE):
            with open(ENCRYPTION_KEY_FILE, 'rb') as f:
                return f.read()
        else:
            key = Fernet.generate_key()
            with open(ENCRYPTION_KEY_FILE, 'wb') as f:
                f.write(key)
            return key
    
    def _load_api_keys(self) -> Dict:
        """Load encrypted API keys from storage."""
        if os.path.exists(API_KEYS_FILE):
            try:
                with open(API_KEYS_FILE, 'r') as f:
                    encrypted_data = json.load(f)
                
                # Decrypt the data
                decrypted_data = {}
                for provider, data in encrypted_data.items():
                    if isinstance(data, dict) and 'encrypted_key' in data:
                        decrypted_key = self.cipher.decrypt(data['encrypted_key'].encode()).decode()
                        decrypted_data[provider] = {
                            **data,
                            'api_key': decrypted_key
                        }
                        del decrypted_data[provider]['encrypted_key']
                    else:
                        # Legacy format or corrupted data
                        continue
                
                return decrypted_data
            except Exception as e:
                print(f"Error loading API keys: {e}")
                return {}
        return {}
    
    def _save_api_keys(self):
        """Save API keys with encryption."""
        try:
            encrypted_data = {}
            for provider, data in self.api_keys.items():
                encrypted_key = self.cipher.encrypt(data['api_key'].encode()).decode()
                encrypted_data[provider] = {
                    **data,
                    'encrypted_key': encrypted_key
                }
                del encrypted_data[provider]['api_key']
            
            with open(API_KEYS_FILE, 'w') as f:
                json.dump(encrypted_data, f, indent=2)
        except Exception as e:
            print(f"Error saving API keys: {e}")
    
    def add_api_key(self, provider: str, api_key: str, name: Optional[str] = None, model: Optional[str] = None) -> bool:
        """Add or update an API key."""
        masked_key = self._mask_api_key(api_key)
        display_name = name or f"{provider.replace('_', '.').title()} Key"
        
        self.api_keys[provider] = {
            'api_key': api_key,
            'name': display_name,
            'masked_key': masked_key,
            'created_at': datetime.now().isoformat(),
            'last_tested': None,
            'status': 'untested',
            'model': model
        }
        
        self._save_api_keys()
        return True
    
    def get_api_key(self, provider: str) -> Optional[str]:
        """Get decrypted API key for a provider."""
        return self.api_keys.get(provider, {}).get('api_key')
    
    def get_api_key_info(self, provider: str) -> Optional[APIKeyInfo]:
        """Get API key information without the actual key."""
        data = self.api_keys.get(provider)
        print("api key data",data)
        if data:
            return APIKeyInfo(
                provider=provider,
                name=data['name'],
                masked_key=data['masked_key'],
                created_at=data['created_at'],
                last_tested=data.get('last_tested'),
                status=data.get('status', 'untested'),
                model=data.get('model')
            )
        return None
    
    def list_api_keys(self) -> List[APIKeyInfo]:
        """List all API keys (without actual keys)."""
        return [self.get_api_key_info(provider) for provider in self.api_keys.keys()]
    
    def remove_api_key(self, provider: str) -> bool:
        """Remove an API key."""
        if provider in self.api_keys:
            del self.api_keys[provider]
            self._save_api_keys()
            return True
        return False
    
    def _mask_api_key(self, api_key: str) -> str:
        """Mask API key for display."""
        if len(api_key) <= 8:
            return "*" * len(api_key)
        return api_key[:4] + "*" * (len(api_key) - 8) + api_key[-4:]
    
    async def test_api_key(self, provider: str) -> Dict[str, any]:
        """Test if an API key is valid."""
        api_key = self.get_api_key(provider)
        if not api_key:
            return {"valid": False, "error": "API key not found"}
        
        try:
            if provider == "llm_vin":
                result = await self._test_llm_vin_key(api_key)
            elif provider == "openai":
                result = await self._test_openai_key(api_key)
            elif provider == "claude":
                result = await self._test_claude_key(api_key)
            else:
                return {"valid": False, "error": "Unknown provider"}
            
            # Update status
            self.api_keys[provider]['last_tested'] = datetime.now().isoformat()
            self.api_keys[provider]['status'] = 'active' if result['valid'] else 'invalid'
            self._save_api_keys()
            
            return result
        except Exception as e:
            self.api_keys[provider]['status'] = 'invalid'
            self._save_api_keys()
            return {"valid": False, "error": str(e)}
    
    async def _test_llm_vin_key(self, api_key: str) -> Dict[str, any]:
        """Test LLM.vin API key."""
        async with aiohttp.ClientSession() as session:
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }
            
            try:
                # Test with a simple model list request
                async with session.get("https://api.llm.vin/v1/models", headers=headers) as response:
                    if response.status == 200:
                        data = await response.json()
                        return {
                            "valid": True, 
                            "message": "LLM.vin API key is valid",
                            "models_count": len(data.get("data", []))
                        }
                    else:
                        return {
                            "valid": False, 
                            "error": f"HTTP {response.status}: {await response.text()}"
                        }
            except Exception as e:
                return {"valid": False, "error": f"Connection error: {str(e)}"}

    async def get_llm_vin_models(self, api_key: str) -> List[Dict[str, Any]]:
        """Fetch available models from LLM.vin API."""
        try:
            async with aiohttp.ClientSession() as session:
                headers = {"Authorization": f"Bearer {api_key}"}
                async with session.get("https://api.llm.vin/v1/models", headers=headers) as response:
                    if response.status == 200:
                        data = await response.json()
                        models = data.get("data", [])
                        
                        # Enhance models with capability info
                        for model in models:
                            model_id = model.get("id", "")
                            # Identify text-to-image models based on model ID patterns
                            is_image_model = any(keyword in model_id.lower() for keyword in [
                                'flux', 'stable-diffusion', 'dalle', 'midjourney', 'imagen'
                            ])
                            model["is_image_model"] = is_image_model
                            model["supports_text"] = not is_image_model  # Most image models don't support text chat
                            
                        return models
                    return []
        except Exception as e:
            print(f"Error fetching LLM.vin models: {e}")
            return []

    async def get_openai_models(self, api_key: str) -> List[Dict[str, Any]]:
        """Fetch available models from OpenAI API."""
        try:
            async with aiohttp.ClientSession() as session:
                headers = {"Authorization": f"Bearer {api_key}"}
                async with session.get("https://api.openai.com/v1/models", headers=headers) as response:
                    if response.status == 200:
                        data = await response.json()
                        return data.get("data", [])
                    return []
        except Exception as e:
            print(f"Error fetching OpenAI models: {e}")
            return []

    async def get_claude_models(self, api_key: str) -> List[Dict[str, Any]]:
        """Claude doesn't have a models endpoint, return hardcoded list."""
        return [
            {"id": "claude-3-5-sonnet-20241022", "object": "model"},
            {"id": "claude-3-5-haiku-20241022", "object": "model"},
            {"id": "claude-3-opus-20240229", "object": "model"},
            {"id": "claude-3-sonnet-20240229", "object": "model"},
            {"id": "claude-3-haiku-20240307", "object": "model"}
        ]
    
    async def _test_openai_key(self, api_key: str) -> Dict[str, any]:
        """Test OpenAI API key."""
        async with aiohttp.ClientSession() as session:
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }
            
            try:
                async with session.get("https://api.openai.com/v1/models", headers=headers) as response:
                    if response.status == 200:
                        data = await response.json()
                        return {
                            "valid": True, 
                            "message": "OpenAI API key is valid",
                            "models_count": len(data.get("data", []))
                        }
                    else:
                        error_text = await response.text()
                        return {
                            "valid": False, 
                            "error": f"HTTP {response.status}: {error_text}"
                        }
            except Exception as e:
                return {"valid": False, "error": f"Connection error: {str(e)}"}
    
    async def _test_claude_key(self, api_key: str) -> Dict[str, any]:
        """Test Claude API key."""
        async with aiohttp.ClientSession() as session:
            headers = {
                "x-api-key": api_key,
                "Content-Type": "application/json",
                "anthropic-version": "2023-06-01"
            }
            
            try:
                # Test with a simple completion request
                payload = {
                    "model": "claude-3-haiku-20240307",
                    "max_tokens": 10,
                    "messages": [{"role": "user", "content": "Hello"}]
                }
                
                async with session.post("https://api.anthropic.com/v1/messages", 
                                       headers=headers, json=payload) as response:
                    if response.status == 200:
                        return {
                            "valid": True, 
                            "message": "Claude API key is valid"
                        }
                    else:
                        error_text = await response.text()
                        return {
                            "valid": False, 
                            "error": f"HTTP {response.status}: {error_text}"
                        }
            except Exception as e:
                return {"valid": False, "error": f"Connection error: {str(e)}"}

# Initialize the API key manager
api_key_manager = APIKeyManager()

# API Endpoints
@app.post("/add_api_key")
async def add_api_key(request: APIKeyRequest):
    """Add or update an API key."""
    try:
        success = api_key_manager.add_api_key(
            provider=request.provider,
            api_key=request.api_key,
            name=request.name,
            model=request.model
        )
        
        if success:
            return {
                "status": "success",
                "message": f"API key for {request.provider} added successfully"
            }
        else:
            raise HTTPException(status_code=500, detail="Failed to add API key")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api_keys")
async def list_api_keys():
    """List all stored API keys (masked)."""
    keys = api_key_manager.list_api_keys()
    return {
        "api_keys": [key.dict() for key in keys],
        "total": len(keys)
    }

@app.get("/api_key/{provider}")
async def get_api_key_info(provider: str):
    """Get information about a specific API key."""
    key_info = api_key_manager.get_api_key_info(provider)
    if key_info:
        return key_info.dict()
    else:
        raise HTTPException(status_code=404, detail="API key not found")

@app.delete("/api_key/{provider}")
async def remove_api_key(provider: str):
    """Remove an API key."""
    success = api_key_manager.remove_api_key(provider)
    if success:
        return {"status": "success", "message": f"API key for {provider} removed"}
    else:
        raise HTTPException(status_code=404, detail="API key not found")

@app.post("/test_api_key/{provider}")
async def test_api_key(provider: str):
    """Test if an API key is valid."""
    result = await api_key_manager.test_api_key(provider)
    return result

@app.get("/supported_providers")
async def get_supported_providers():
    """Get list of supported API providers."""
    return {
        "providers": [
            {
                "id": "llm_vin",
                "name": "LLM.vin",
                "description": "Multi-model API service",
                "website": "https://llm.vin",
                "default_models": [
                    "gpt-4o-mini",
                    "gpt-4o",
                    "claude-3-5-sonnet-20241022",
                    "claude-3-5-haiku-20241022",
                    "gemini-2.0-flash-exp"
                ]
            },
            {
                "id": "openai",
                "name": "OpenAI",
                "description": "GPT models and API",
                "website": "https://openai.com",
                "default_models": [
                    "gpt-4o",
                    "gpt-4o-mini",
                    "gpt-4-turbo",
                    "gpt-3.5-turbo",
                    "o1-preview",
                    "o1-mini"
                ]
            },
            {
                "id": "claude",
                "name": "Anthropic Claude",
                "description": "Claude AI models",
                "website": "https://anthropic.com",
                "default_models": [
                    "claude-3-5-sonnet-20241022",
                    "claude-3-5-haiku-20241022",
                    "claude-3-opus-20240229",
                    "claude-3-sonnet-20240229",
                    "claude-3-haiku-20240307"
                ]
            }
        ]
    }

@app.get("/provider_models/{provider_id}")
async def get_provider_models(provider_id: str):
    """Get available models for a specific provider."""
    # Try to get real models from API if key exists
    api_key = api_key_manager.get_api_key(provider_id)
    
    if api_key:
        try:
            if provider_id == "llm_vin":
                models = await api_key_manager.get_llm_vin_models(api_key)
                return {
                    "provider_id": provider_id,
                    "models": [model["id"] for model in models],
                    "source": "api"
                }
            elif provider_id == "openai":
                models = await api_key_manager.get_openai_models(api_key)
                return {
                    "provider_id": provider_id,
                    "models": [model["id"] for model in models],
                    "source": "api"
                }
            elif provider_id == "claude":
                models = await api_key_manager.get_claude_models(api_key)
                return {
                    "provider_id": provider_id,
                    "models": [model["id"] for model in models],
                    "source": "hardcoded"
                }
        except Exception as e:
            print(f"Error fetching models for {provider_id}: {e}")
    
    # Fallback to default models
    providers = await get_supported_providers()
    provider = next((p for p in providers["providers"] if p["id"] == provider_id), None)
    
    if not provider:
        raise HTTPException(status_code=404, detail="Provider not found")
    
    return {
        "provider_id": provider_id,
        "models": provider.get("default_models", []),
        "source": "default"
    }

@app.get("/api_models")
async def get_api_models():
    """Get all available API models from configured providers."""
    result = {
        "providers": [],
        "total_models": 0
    }
    
    for provider_id in ["llm_vin", "openai", "claude"]:
        api_key = api_key_manager.get_api_key(provider_id)
        if api_key:
            provider_info = {
                "provider_id": provider_id,
                "models": [],
                "status": "configured"
            }
            
            try:
                if provider_id == "llm_vin":
                    models = await api_key_manager.get_llm_vin_models(api_key)
                    provider_info["models"] = [{"id": model["id"], "object": model.get("object", "model")} for model in models]
                elif provider_id == "openai":
                    models = await api_key_manager.get_openai_models(api_key)
                    provider_info["models"] = [{"id": model["id"], "object": model.get("object", "model")} for model in models]
                elif provider_id == "claude":
                    models = await api_key_manager.get_claude_models(api_key)
                    provider_info["models"] = models
                
                provider_info["status"] = "active"
            except Exception as e:
                provider_info["status"] = "error"
                provider_info["error"] = str(e)
            
            result["providers"].append(provider_info)
            result["total_models"] += len(provider_info["models"])
    
    return result

# Utility function to get API key for use in other parts of the application
def get_api_key_for_provider(provider: str) -> Optional[str]:
    """Utility function to get API key for other modules."""
    return api_key_manager.get_api_key(provider)
