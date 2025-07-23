"""API Model Wrapper for external API providers."""

import asyncio
import aiohttp
import json
from typing import Dict, Any, Optional, AsyncGenerator, Iterator
from pydantic import Field
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import BaseMessage, HumanMessage, AIMessage
from langchain_core.outputs import ChatGeneration, ChatResult

def get_default_base_url(provider: str) -> str:
    """Get default base URL for each provider."""
    urls = {
        "openai": "https://api.openai.com/v1",
        "claude": "https://api.anthropic.com/v1",
        "llm_vin": "https://api.llm.vin/v1"
    }
    return urls.get(provider, "")

class APIModelWrapper(BaseChatModel):
    """Wrapper for API-based models that mimics the local model interface."""
    
    provider: str = Field(...)
    api_key: str = Field(...)
    model: str = Field(...)
    base_url: str = Field(default="")
    
    def __init__(self, provider: str, api_key: str, model: str, base_url: Optional[str] = None, **kwargs):
        base_url_final = base_url or get_default_base_url(provider)
        super().__init__(
            provider=provider,
            api_key=api_key,
            model=model,
            base_url=base_url_final,
            **kwargs
        )
    
    def _get_headers(self) -> Dict[str, str]:
        """Get appropriate headers for each provider."""
        if self.provider == "openai" or self.provider == "llm_vin":
            return {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
        elif self.provider == "claude":
            return {
                "x-api-key": self.api_key,
                "Content-Type": "application/json",
                "anthropic-version": "2023-06-01"
            }
        return {}
    
    def _format_messages(self, messages) -> list:
        """Format messages for API call."""
        formatted = []
        for msg in messages:
            if isinstance(msg, HumanMessage):
                formatted.append({"role": "user", "content": msg.content})
            elif isinstance(msg, AIMessage):
                formatted.append({"role": "assistant", "content": msg.content})
            elif hasattr(msg, 'content'):
                formatted.append({"role": "user", "content": str(msg.content)})
            else:
                formatted.append({"role": "user", "content": str(msg)})
        return formatted
    
    def _create_payload(self, messages: list, stream: bool = False) -> Dict[str, Any]:
        """Create API payload based on provider."""
        formatted_messages = self._format_messages(messages)
        
        if self.provider == "claude":
            return {
                "model": self.model,
                "max_tokens": 4096,
                "messages": formatted_messages,
                "stream": stream
            }
        else:  # OpenAI-compatible (OpenAI, LLM.vin)
            return {
                "model": self.model,
                "messages": formatted_messages,
                "stream": stream
            }
    
    async def _call_api(self, payload: Dict[str, Any]) -> str:
        """Make API call and return response."""
        endpoint = f"{self.base_url}/chat/completions"
        if self.provider == "claude":
            endpoint = f"{self.base_url}/messages"
        
        async with aiohttp.ClientSession() as session:
            async with session.post(endpoint, headers=self._get_headers(), json=payload) as response:
                if response.status != 200:
                    error_text = await response.text()
                    raise Exception(f"API Error {response.status}: {error_text}")
                
                data = await response.json()
                
                if self.provider == "claude":
                    return data["content"][0]["text"]
                else:
                    return data["choices"][0]["message"]["content"]
    
    def _generate(self, messages, stop=None, run_manager=None, **kwargs):
        """Generate response (sync version for compatibility)."""
        import asyncio
        import concurrent.futures
        
        # Check if we're in an async context
        try:
            loop = asyncio.get_running_loop()
            # We're in an async context, use thread pool
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(self._sync_generate, messages, stop, run_manager, **kwargs)
                return future.result()
        except RuntimeError:
            # No running loop, create new one
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                result = loop.run_until_complete(self._agenerate(messages, stop, run_manager, **kwargs))
                return result
            finally:
                loop.close()
    
    def _sync_generate(self, messages, stop=None, run_manager=None, **kwargs):
        """Synchronous generate helper."""
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
        try:
            result = loop.run_until_complete(self._agenerate(messages, stop, run_manager, **kwargs))
            return result
        finally:
            loop.close()
    
    async def _agenerate(self, messages, stop=None, run_manager=None, **kwargs):
        """Generate response async."""
        payload = self._create_payload(messages, stream=False)
        response_text = await self._call_api(payload)
        
        message = AIMessage(content=response_text)
        generation = ChatGeneration(message=message)
        return ChatResult(generations=[generation])
    
    def stream(self, input_text: str) -> Iterator[Any]:
        """Stream response for compatibility with local models."""
        import requests
        import json
        import time
        
        class StreamResponse:
            def __init__(self, content):
                self.content = content
        
        try:
            # Use synchronous requests for streaming to avoid asyncio issues
            endpoint = f"{self.base_url}/chat/completions"
            if self.provider == "claude":
                endpoint = f"{self.base_url}/messages"
            
            messages = [{"role": "user", "content": input_text}]
            payload = self._create_payload_sync(messages, stream=True)
            
            response = requests.post(
                endpoint,
                headers=self._get_headers(),
                json=payload,
                stream=True,
                timeout=30
            )
            
            if response.status_code != 200:
                yield StreamResponse(f"API Error {response.status_code}: {response.text}")
                return
            
            # Handle streaming response
            if payload.get("stream", False):
                for line in response.iter_lines():
                    if line:
                        line = line.decode('utf-8').strip()
                        if line.startswith("data: "):
                            data = line[6:]  # Remove "data: " prefix
                            if data == "[DONE]":
                                break
                            
                            try:
                                json_data = json.loads(data)
                                if self.provider == "claude":
                                    # Handle Claude streaming format
                                    if json_data.get("type") == "content_block_delta":
                                        content = json_data.get("delta", {}).get("text", "")
                                        if content:
                                            yield StreamResponse(content)
                                else:
                                    # Handle OpenAI-compatible streaming format
                                    choices = json_data.get("choices", [])
                                    if choices:
                                        delta = choices[0].get("delta", {})
                                        content = delta.get("content", "")
                                        if content:
                                            yield StreamResponse(content)
                            except json.JSONDecodeError:
                                continue
            else:
                # Fallback to non-streaming
                data = response.json()
                if self.provider == "claude":
                    content = data["content"][0]["text"]
                else:
                    content = data["choices"][0]["message"]["content"]
                
                # Simulate streaming by yielding chunks
                words = content.split()
                for i, word in enumerate(words):
                    if i == 0:
                        yield StreamResponse(word)
                    else:
                        yield StreamResponse(" " + word)
                    time.sleep(0.05)  # Small delay for streaming effect
                    
        except Exception as e:
            yield StreamResponse(f"Streaming error: {str(e)}")
    
    def _create_payload_sync(self, messages: list, stream: bool = False) -> Dict[str, Any]:
        """Create API payload (sync version)."""
        if self.provider == "claude":
            return {
                "model": self.model,
                "max_tokens": 4096,
                "messages": messages,
                "stream": stream
            }
        else:  # OpenAI-compatible (OpenAI, LLM.vin)
            return {
                "model": self.model,
                "messages": messages,
                "stream": stream
            }
    
    async def _stream_async(self, input_text: str) -> AsyncGenerator[Any, None]:
        """Async streaming implementation."""
        messages = [HumanMessage(content=input_text)]
        formatted_messages = self._format_messages(messages)
        
        payload = self._create_payload(messages, stream=True)
        endpoint = f"{self.base_url}/chat/completions"
        if self.provider == "claude":
            endpoint = f"{self.base_url}/messages"
        
        class StreamResponse:
            def __init__(self, content):
                self.content = content
        
        async with aiohttp.ClientSession() as session:
            try:
                async with session.post(endpoint, headers=self._get_headers(), json=payload) as response:
                    if response.status != 200:
                        error_text = await response.text()
                        yield StreamResponse(f"API Error {response.status}: {error_text}")
                        return
                    
                    # Handle streaming response
                    if payload.get("stream", False):
                        async for line in response.content:
                            line = line.decode('utf-8').strip()
                            if line.startswith("data: "):
                                data = line[6:]  # Remove "data: " prefix
                                if data == "[DONE]":
                                    break
                                
                                try:
                                    json_data = json.loads(data)
                                    if self.provider == "claude":
                                        # Handle Claude streaming format
                                        if json_data.get("type") == "content_block_delta":
                                            content = json_data.get("delta", {}).get("text", "")
                                            if content:
                                                yield StreamResponse(content)
                                    else:
                                        # Handle OpenAI-compatible streaming format
                                        choices = json_data.get("choices", [])
                                        if choices:
                                            delta = choices[0].get("delta", {})
                                            content = delta.get("content", "")
                                            if content:
                                                yield StreamResponse(content)
                                except json.JSONDecodeError:
                                    continue
                    else:
                        # Fallback to non-streaming
                        data = await response.json()
                        if self.provider == "claude":
                            content = data["content"][0]["text"]
                        else:
                            content = data["choices"][0]["message"]["content"]
                        
                        # Simulate streaming by yielding chunks
                        words = content.split()
                        for i, word in enumerate(words):
                            if i == 0:
                                yield StreamResponse(word)
                            else:
                                yield StreamResponse(" " + word)
                            await asyncio.sleep(0.05)  # Small delay for streaming effect
                            
            except Exception as e:
                yield StreamResponse(f"Streaming error: {str(e)}")
    
    @property
    def _llm_type(self) -> str:
        return f"api_{self.provider}"
    
    @property
    def _identifying_params(self) -> Dict[str, Any]:
        return {
            "provider": self.provider,
            "model": self.model,
            "base_url": self.base_url
        }