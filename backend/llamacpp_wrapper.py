"""LlamaCpp Chat Wrapper."""
import os
from typing import (
    Any,
    Callable,
    Dict,
    Iterator,
    List,
    Literal,
    Optional,
    Sequence,
    Type,
    Union,
)

from langchain_core.callbacks.manager import (
    AsyncCallbackManagerForLLMRun,
    CallbackManagerForLLMRun,
)
from langchain_core.language_models import LanguageModelInput
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import (
    AIMessage,
    AIMessageChunk,
    BaseMessage,
    HumanMessage,
    SystemMessage,
)
from langchain_core.outputs import (
    ChatGeneration,
    ChatGenerationChunk,
    ChatResult,
    LLMResult,
)
from langchain_core.runnables import Runnable
from langchain_core.tools import BaseTool
from langchain_core.utils.function_calling import convert_to_openai_tool

DEFAULT_SYSTEM_PROMPT = """You are a helpful, respectful, and honest assistant."""


class ChatLlamaCpp(BaseChatModel):
    """LlamaCpp chat models.

    Works with `llama-cpp-python` models.

    To use, you should have the ``llama-cpp-python`` python package installed.

    Example:
        .. code-block:: python

            from llamacpp_wrapper import ChatLlamaCpp
            
            model_path = "./Models/model.gguf"
            chat = ChatLlamaCpp(model_path=model_path)

    """

    model_path: str
    model: Any = None
    system_message: SystemMessage = SystemMessage(content=DEFAULT_SYSTEM_PROMPT)
    n_ctx: int = 131072  # Maximum context for high-memory system (128k tokens)
    n_gpu_layers: int = -1  # Use all available GPU layers
    verbose: bool = False
    temperature: float = 0.1
    max_tokens: int = 8192  # Increased max response tokens for longer outputs
    top_p: float = 0.95
    top_k: int = 40

    def __init__(self, **kwargs: Any):
        super().__init__(**kwargs)
        self._initialize_model()

    def _initialize_model(self):
        """Initialize the llama-cpp-python model."""
        try:
            from llama_cpp import Llama
        except ImportError:
            raise ImportError(
                "Could not import llama-cpp-python package. "
                "Please install it with `pip install llama-cpp-python`."
            )
        
        if not os.path.exists(self.model_path):
            raise FileNotFoundError(f"Model file not found: {self.model_path}")
        
        self.model = Llama(
            model_path=self.model_path,
            n_ctx=self.n_ctx,
            n_gpu_layers=self.n_gpu_layers,
            verbose=self.verbose,
        )

    def _generate(
        self,
        messages: List[BaseMessage],
        stop: Optional[List[str]] = None,
        run_manager: Optional[CallbackManagerForLLMRun] = None,
        **kwargs: Any,
    ) -> ChatResult:

        prompt = self._to_chat_prompt(messages)
        
        response = self.model(
            prompt,
            max_tokens=kwargs.get("max_tokens", self.max_tokens),
            temperature=kwargs.get("temperature", self.temperature),
            top_p=kwargs.get("top_p", self.top_p),
            top_k=kwargs.get("top_k", self.top_k),
            stop=stop,
            stream=False,
        )
        
        text = response["choices"][0]["text"]
        message = AIMessage(content=text)
        generation = ChatGeneration(message=message)
        
        return ChatResult(generations=[generation])

    async def _agenerate(
        self,
        messages: List[BaseMessage],
        stop: Optional[List[str]] = None,
        run_manager: Optional[AsyncCallbackManagerForLLMRun] = None,
        **kwargs: Any,
    ) -> ChatResult:
        # For now, just call the sync version
        return self._generate(messages, stop, run_manager, **kwargs)

    def _to_chat_prompt(self, messages: List[BaseMessage]) -> str:
        """Convert a list of messages into a prompt format expected by llama.cpp."""
        if not messages:
            raise ValueError("At least one HumanMessage must be provided!")

        if not isinstance(messages[-1], HumanMessage):
            raise ValueError("Last message must be a HumanMessage!")

        # Build the prompt using a simple format
        prompt_parts = []
        
        for message in messages:
            if isinstance(message, SystemMessage):
                prompt_parts.append(f"System: {message.content}")
            elif isinstance(message, HumanMessage):
                prompt_parts.append(f"User: {message.content}")
            elif isinstance(message, AIMessage):
                prompt_parts.append(f"Assistant: {message.content}")
        
        prompt_parts.append("Assistant:")
        return "\n".join(prompt_parts)

    @property
    def _llm_type(self) -> str:
        return "llamacpp-chat-wrapper"

    def _stream(
        self,
        messages: List[BaseMessage],
        stop: Optional[List[str]] = None,
        run_manager: Optional[CallbackManagerForLLMRun] = None,
        **kwargs: Any,
    ) -> Iterator[ChatGenerationChunk]:
        
        prompt = self._to_chat_prompt(messages)
        
        stream = self.model(
            prompt,
            max_tokens=kwargs.get("max_tokens", self.max_tokens),
            temperature=kwargs.get("temperature", self.temperature),
            top_p=kwargs.get("top_p", self.top_p),
            top_k=kwargs.get("top_k", self.top_k),
            stop=stop,
            stream=True,
        )
        
        for token_data in stream:
            if "choices" in token_data and len(token_data["choices"]) > 0:
                token = token_data["choices"][0].get("text", "")
                if token:
                    chunk = ChatGenerationChunk(message=AIMessageChunk(content=token))
                    if run_manager:
                        run_manager.on_llm_new_token(token, chunk=chunk)
                    yield chunk

    def bind_tools(
        self,
        tools: Sequence[Union[Dict[str, Any], Type, Callable, BaseTool]],
        *,
        tool_choice: Optional[Union[dict, str, Literal["auto", "none"], bool]] = None,
        **kwargs: Any,
    ) -> Runnable[LanguageModelInput, BaseMessage]:
        """Bind tool-like objects to this chat model.

        Note: Tool calling with llama.cpp is limited and experimental.
        """
        
        formatted_tools = [convert_to_openai_tool(tool) for tool in tools]
        if tool_choice is not None and tool_choice:
            if len(formatted_tools) != 1:
                raise ValueError(
                    "When specifying `tool_choice`, you must provide exactly one "
                    f"tool. Received {len(formatted_tools)} tools."
                )
            if isinstance(tool_choice, str):
                if tool_choice not in ("auto", "none"):
                    tool_choice = {
                        "type": "function",
                        "function": {"name": tool_choice},
                    }
            elif isinstance(tool_choice, bool):
                tool_choice = formatted_tools[0]
            elif isinstance(tool_choice, dict):
                if (
                    formatted_tools[0]["function"]["name"]
                    != tool_choice["function"]["name"]
                ):
                    raise ValueError(
                        f"Tool choice {tool_choice} was specified, but the only "
                        f"provided tool was {formatted_tools[0]['function']['name']}."
                    )
            else:
                raise ValueError(
                    f"Unrecognized tool_choice type. Expected str, bool or dict. "
                    f"Received: {tool_choice}"
                )
            kwargs["tool_choice"] = tool_choice
            print("tool running and binding")
            print(super().bind(tools=formatted_tools, **kwargs))
        return super().bind(tools=formatted_tools, **kwargs)