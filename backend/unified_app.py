"""Unified FastAPI application supporting both MLX and LlamaCpp models."""

import os
import time
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import json
import asyncio
import uvicorn
from contextlib import asynccontextmanager
from typing import Optional, Dict, Any, List

from model_manager import ModelManager, ModelSource
from downloadManager import download_manager
from default_model_installer import DefaultModelInstaller
from llm_provider import get_llm_provider

def extract_chunk_content(chunk, debug_prefix="chunk") -> str:
    """
    Universal chunk content extractor for LLM streaming responses.
    Handles all common chunk formats: objects, dicts, strings.
    """
    try:
        if hasattr(chunk, 'content'):
            return str(chunk.content)
        elif isinstance(chunk, dict):
            # Handle dict responses - try common keys
            if 'content' in chunk:
                return str(chunk['content'])
            elif 'text' in chunk:
                return str(chunk['text'])
            elif 'message' in chunk:
                return str(chunk['message'])
            elif 'data' in chunk:
                return str(chunk['data'])
            else:
                return str(chunk)
        elif isinstance(chunk, str):
            return chunk
        else:
            return str(chunk)
    except Exception as e:
        print(f"❌ Error extracting content from {debug_prefix}: {e}")
        return str(chunk) if chunk is not None else ""
from chat_manager import chat_manager

from simple_updater import simple_updater
from performance_monitor import performance_monitor
from server_config import server_config
import re

# NEW SMART MEMORY SYSTEM
from smart_memory_system import initialize_smart_memory, get_smart_memory, MemoryEntry
from background_learning_service import initialize_background_learning, get_background_learning_service, get_ui_status_tracker
from instant_memory_api import InstantMemoryAPI
from smart_memory_endpoints import add_smart_memory_endpoints
from hybrid_memory_endpoints import add_hybrid_memory_endpoints
from hybrid_memory_system import HybridMemorySystem
import uuid
from datetime import datetime

# AI Personality System Import
from ai_personality_manager import personality_manager, AIPersonality

# Smart Memory System Instances
smart_memory = None
background_learning = None
instant_memory_api = None
hybrid_memory = None
chat_session_cache = None
adaptive_system = None

# Fast Personality Mode for improved performance
class FastPersonalityMode:
    """Fast personality system with smart memory integration"""
    
    def __init__(self, personality_manager, chat_manager, instant_memory_api=None):
        self.personality_manager = personality_manager
        self.chat_manager = chat_manager
        self.instant_memory_api = instant_memory_api or InstantMemoryAPI()
        self.background_queue = asyncio.Queue()
    
    async def stream_fast_personality_response(self, user_id: str, message: str, personality_id: str, chat_id: str, llm_provider):
        """Fast streaming with smart memory integration"""
        import time
        start_time = time.time()
        
        # 1. Fast personality lookup (< 50ms)
        personality = await self._get_personality_fast(user_id, personality_id)
        
        # 2. Get personalized prompt with instant memory (< 10ms)
        personalized_prompt = self.instant_memory_api.get_personalization_prompt(user_id, message)
        
        # 3. Build final prompt with personality
        final_prompt = self._build_personality_prompt(personality, personalized_prompt)
        
        setup_time = (time.time() - start_time) * 1000
        print(f"⚡ Smart memory setup: {setup_time:.1f}ms")
        
        # 4. Stream immediately
        full_response = ""
        chunk_count = 0
        async for chunk in self._stream_with_llm(llm_provider, final_prompt):
            chunk_count += 1
            full_response += chunk
            yield chunk
        
        # 5. Save conversation
        self.chat_manager.save_message(chat_id, "human", message)
        self.chat_manager.save_message(chat_id, "ai", full_response)
        
        # 6. Queue for background learning (non-blocking)
        if background_learning:
            background_learning.notify_new_message(chat_id, user_id, {
                "role": "user", 
                "content": message
            })
        
        total_time = time.time() - start_time
        print(f"⚡ Total smart response time: {total_time:.2f}s")
    
    async def _get_personality_fast(self, user_id: str, personality_id: str):
        """Fast personality lookup"""
        try:
            personalities = await self.personality_manager.get_user_personalities(user_id)
            return next((p for p in personalities if p.id == personality_id), None)
        except Exception as e:
            print(f"⚠️ Fast personality lookup failed: {e}")
            return None
    
    def _build_personality_prompt(self, personality, personalized_prompt: str) -> str:
        """Combine personality traits with personalized prompt"""
        if personality and hasattr(personality, 'name'):
            personality_intro = f"You are {personality.name}."
            if hasattr(personality, 'description'):
                personality_intro += f" {personality.description}"
            
            # Add personality traits if available
            if hasattr(personality, 'personality_traits') and personality.personality_traits:
                traits = ", ".join(personality.personality_traits[:3])  # Top 3 traits
                personality_intro += f" Your key traits: {traits}."
                
        else:
            personality_intro = "You are a helpful AI assistant."
        
        # Combine personality with personalized prompt
        return f"{personality_intro}\n\n{personalized_prompt}"
    
    async def _stream_with_llm(self, llm_provider, prompt):
        """Stream response from LLM"""
        try:
            for chunk in llm_provider.stream(prompt):
                chunk_content = extract_chunk_content(chunk, "fast_personality")
                if chunk_content:
                    yield chunk_content
        except Exception as e:
            print(f"❌ Fast streaming error: {e}")
            yield "I apologize, there was an error generating my response."
    
# Initialize fast personality mode
fast_personality = None

# Sparrow VLM Integration
from sparrow_vlm_engine import sparrow_vlm_engine, analyze_image_with_sparrow

# Fast Vision Pipeline for performance optimization
from fast_vision_pipeline import FastVisionPipeline, initialize_fast_vision_pipeline

# Global instances
fast_vision_pipeline = None

# Shared state
model_ready = False
model_manager = None
current_llm = None

# Global stop signal
stop_stream = False

def extract_important_facts(user_message: str, ai_response: str) -> List[Dict[str, Any]]:
    """
    Enhanced NLP-based fact extraction for memory storage.
    Extracts various types of important information from user messages and AI responses.
    """
    facts = []
    user_lower = user_message.lower()
    ai_lower = ai_response.lower()
    
    # PERSONAL INFORMATION EXTRACTION
    personal_patterns = {
        "name": [
            r"my name is (\w+(?:\s+\w+)*)",
            r"i'm (\w+(?:\s+\w+)*)",
            r"i am (\w+(?:\s+\w+)*)",
            r"call me (\w+(?:\s+\w+)*)"
        ],
        "occupation": [
            r"i work (?:as|at) ([\w\s]+)",
            r"i'm a ([\w\s]+)",
            r"my job is ([\w\s]+)",
            r"i do ([\w\s]+) for work"
        ],
        "location": [
            r"i live in ([\w\s,]+)",
            r"i'm from ([\w\s,]+)",
            r"i'm based in ([\w\s,]+)",
            r"my city is ([\w\s,]+)"
        ],
        "age": [
            r"i am (\d+) years? old",
            r"i'm (\d+)",
            r"my age is (\d+)"
        ],
        "family": [
            r"my (?:wife|husband|partner|spouse) (?:is )?(\w+)",
            r"my (?:son|daughter|child) (?:is )?(\w+)",
            r"my (?:mother|father|mom|dad|parent) (?:is )?(\w+)"
        ]
    }
    
    for category, patterns in personal_patterns.items():
        for pattern in patterns:
            matches = re.findall(pattern, user_lower)
            for match in matches:
                facts.append({
                    "content": f"User's {category}: {match}",
                    "type": "personal",
                    "category": category,
                    "source": "user_statement",
                    "importance": "high",
                    "confidence": 0.9
                })
    
    # PREFERENCES AND INTERESTS
    preference_patterns = {
        "likes": [
            r"i like ([\w\s,]+)",
            r"i love ([\w\s,]+)",
            r"i enjoy ([\w\s,]+)",
            r"i'm interested in ([\w\s,]+)"
        ],
        "dislikes": [
            r"i don't like ([\w\s,]+)",
            r"i hate ([\w\s,]+)",
            r"i dislike ([\w\s,]+)"
        ],
        "favorites": [
            r"my favorite ([\w\s]+) is ([\w\s,]+)",
            r"i prefer ([\w\s,]+)"
        ]
    }
    
    for category, patterns in preference_patterns.items():
        for pattern in patterns:
            matches = re.findall(pattern, user_lower)
            for match in matches:
                content = match if isinstance(match, str) else " ".join(match)
                facts.append({
                    "content": f"User {category}: {content}",
                    "type": "personal",
                    "category": f"preferences_{category}",
                    "source": "user_statement",
                    "importance": "medium",
                    "confidence": 0.8
                })
    
    # GOALS AND ASPIRATIONS
    goal_patterns = [
        r"i want to ([\w\s,]+)",
        r"my goal is to ([\w\s,]+)",
        r"i plan to ([\w\s,]+)",
        r"i hope to ([\w\s,]+)",
        r"i'm trying to ([\w\s,]+)"
    ]
    
    for pattern in goal_patterns:
        matches = re.findall(pattern, user_lower)
        for match in matches:
            facts.append({
                "content": f"User goal: {match}",
                "type": "personal",
                "category": "goals",
                "source": "user_statement",
                "importance": "medium",
                "confidence": 0.7
            })
    
    # FACTUAL INFORMATION EXTRACTION
    factual_keywords = ["fact", "information", "data", "statistics", "research", "study", "report"]
    if any(keyword in user_lower for keyword in factual_keywords):
        facts.append({
            "content": f"Factual query: {user_message}",
            "type": "factual",
            "category": "information_request",
            "source": "user_query",
            "importance": "medium",
            "confidence": 0.6
        })
        
        # Extract key factual points from AI response
        if len(ai_response) > 100:  # Only for substantial responses
            facts.append({
                "content": f"Factual information provided: {ai_response[:200]}...",
                "type": "factual",
                "category": "knowledge_shared",
                "source": "ai_response",
                "importance": "low",
                "confidence": 0.5
            })
    
    # SKILLS AND EXPERTISE
    skill_patterns = [
        r"i know (?:how to )?([\w\s,]+)",
        r"i can ([\w\s,]+)",
        r"i'm good at ([\w\s,]+)",
        r"i'm skilled in ([\w\s,]+)",
        r"i have experience (?:with|in) ([\w\s,]+)"
    ]
    
    for pattern in skill_patterns:
        matches = re.findall(pattern, user_lower)
        for match in matches:
            facts.append({
                "content": f"User skill: {match}",
                "type": "personal",
                "category": "skills",
                "source": "user_statement",
                "importance": "medium",
                "confidence": 0.7
            })
    
    # REMEMBER REQUESTS (explicit memory requests)
    remember_patterns = [
        r"remember (?:that )?([\w\s,]+)",
        r"don't forget (?:that )?([\w\s,]+)",
        r"keep in mind (?:that )?([\w\s,]+)",
        r"note (?:that )?([\w\s,]+)"
    ]
    
    for pattern in remember_patterns:
        matches = re.findall(pattern, user_lower)
        for match in matches:
            facts.append({
                "content": f"Explicit memory request: {match}",
                "type": "working",
                "category": "explicit_memory",
                "source": "user_request",
                "importance": "high",
                "confidence": 0.95
            })
    
    # PROJECT AND WORK INFORMATION
    project_patterns = [
        r"i (?:am |'m )?working on (?:my )?(?:a )?project (?:called |named )?([\w\s]+)",
        r"my project (?:is |called |named )?([\w\s]+)",
        r"i (?:have|created|built|made|developed) (?:a )?project (?:called |named )?([\w\s]+)",
        r"i'm building (?:an? )?([\w\s]+)",
        r"i'm developing (?:an? )?([\w\s]+)",
        r"my (?:app|application|software|tool) (?:is |called |named )?([\w\s]+)"
    ]
    
    for pattern in project_patterns:
        matches = re.findall(pattern, user_lower)
        for match in matches:
            facts.append({
                "content": f"User project: {match.strip()}",
                "type": "personal",
                "category": "projects",
                "source": "user_statement",
                "importance": "high",
                "confidence": 0.9
            })
    
    # CONTEXTUAL INFORMATION
    context_indicators = ["currently", "right now", "today", "this week", "recently", "lately"]
    if any(indicator in user_lower for indicator in context_indicators):
        facts.append({
            "content": f"Current context: {user_message}",
            "type": "working",
            "category": "current_context",
            "source": "user_statement",
            "importance": "medium",
            "confidence": 0.6
        })
    
    # PROBLEMS AND CHALLENGES
    problem_patterns = [
        r"i have (?:a )?problem (?:with )?([\w\s,]+)",
        r"i'm struggling (?:with )?([\w\s,]+)",
        r"i need help (?:with )?([\w\s,]+)",
        r"i can't (?:figure out |understand )?([\w\s,]+)"
    ]
    
    for pattern in problem_patterns:
        matches = re.findall(pattern, user_lower)
        for match in matches:
            facts.append({
                "content": f"User challenge: {match}",
                "type": "working",
                "category": "problems",
                "source": "user_statement",
                "importance": "medium",
                "confidence": 0.8
            })
    
    # Filter out very short or generic extractions
    facts = [fact for fact in facts if len(fact["content"]) > 10 and not fact["content"].lower() in ["user", "me", "i", "my"]]
    
    # Limit to most important facts to avoid memory bloat
    facts = sorted(facts, key=lambda x: (
        {"high": 3, "medium": 2, "low": 1}[x["importance"]], 
        x["confidence"]
    ), reverse=True)[:10]
    
    return facts

def map_legacy_memory_type(legacy_type: str) -> str:
    """Map legacy memory types to new hybrid memory system types"""
    type_mapping = {
        "factual": "fact",
        "personal": "preference", 
        "working": "fact",
        "conversational": "pattern",
        "project": "goal",
        "skills": "skill",
        "preference": "preference",
        "current_context": "temporal"
    }
    return type_mapping.get(legacy_type, "fact")  # Default to "fact" if unknown

def convert_importance_to_float(importance) -> float:
    """Convert string importance levels to float values"""
    if isinstance(importance, str):
        importance_mapping = {
            "high": 0.8,
            "medium": 0.5,
            "low": 0.2
        }
        return importance_mapping.get(importance.lower(), 0.5)
    elif isinstance(importance, (int, float)):
        return float(importance)
    else:
        return 0.5  # Default value

class ChatRequest(BaseModel):
    input: str
    user_id: str = "pradhumn"
    urgency_mode: str = "normal"  # instant, normal, comprehensive
    memory_types: Optional[List[str]] = None

class ModelSwitchRequest(BaseModel):
    model_id: str
    model_type: Optional[str] = None  # Optional: will be auto-detected
    model_source: Optional[str] = None  # "local" or "api"

class ModelCheckRequest(BaseModel):
    model_id: str

class ModelPreferenceRequest(BaseModel):
    preference: str  # "local" or "api"

class ChatHistoryRequest(BaseModel):
    user_id: str
    message: str
    chat_id: Optional[str] = None
    urgency_mode: str = "normal"  # instant, normal, comprehensive
    memory_types: Optional[List[str]] = None

class ChatInitializeRequest(BaseModel):
    user_id: str
    chat_id: Optional[str] = None
    message: Optional[str] = ""  # Optional empty message for initialization
    urgency_mode: str = "normal"

# Enhanced request class for image analysis with vision support
class ImageAnalysisRequest(BaseModel):
    question: str
    text_content: str
    user_id: str = "default"
    image_data: Optional[str] = None  # Base64 encoded image
    use_vision: Optional[bool] = False  # Whether to use vision models



class ImageGenerationRequest(BaseModel):
    prompt: str
    model_id: Optional[str] = None  # If not provided, use current model

# Advanced Memory Management Request Models
class MemoryStoreRequest(BaseModel):
    user_id: str
    content: str
    memory_type: str = "working"
    context: Optional[Dict[str, Any]] = None
    force_chunking: bool = False

class MemoryRetrieveRequest(BaseModel):
    user_id: str
    query: str
    memory_types: Optional[List[str]] = None
    limit: int = 10
    min_importance: float = 0.0

class MemoryDeleteRequest(BaseModel):
    user_id: str
    memory_ids: Optional[List[str]] = None
    memory_types: Optional[List[str]] = None
    older_than_days: Optional[int] = None
    importance_threshold: Optional[float] = None

# AI Personality Request Models
class CreatePersonalityRequest(BaseModel):
    name: str
    description: str
    personality_traits: List[str] = ["friendly", "helpful"]
    communication_style: str = "conversational"
    expertise_domains: List[str] = ["general"]
    formality_level: float = 0.5
    creativity_level: float = 0.5
    empathy_level: float = 0.5
    humor_level: float = 0.3
    custom_instructions: str = ""
    avatar_icon: str = "🤖"
    color_theme: str = "blue"
    
    # Optional field that may or may not be sent by frontend
    response_length: Optional[str] = "medium"
    
    class Config:
        # Allow extra fields that might be sent from frontend
        extra = "ignore"

class UpdatePersonalityRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    personality_traits: Optional[List[str]] = None
    communication_style: Optional[str] = None
    expertise_domains: Optional[List[str]] = None
    response_length: Optional[str] = None
    formality_level: Optional[float] = None
    creativity_level: Optional[float] = None
    empathy_level: Optional[float] = None
    humor_level: Optional[float] = None
    custom_instructions: Optional[str] = None
    avatar_icon: Optional[str] = None
    color_theme: Optional[str] = None

class SwitchPersonalityRequest(BaseModel):
    personality_id: str

class ChatWithPersonalityRequest(BaseModel):
    user_id: str
    message: str
    personality_id: Optional[str] = None
    chat_id: Optional[str] = None
    urgency_mode: str = "normal"  # instant, normal, comprehensive
    memory_types: Optional[List[str]] = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global model_manager, current_llm, model_ready
    
    print("🔄 Initializing Model Manager...")
    model_manager = ModelManager()
    
    # Initialize default model installer asynchronously in background
    print("🚀 Server starting - default model setup running in background...")
    asyncio.create_task(initialize_with_model())
    
    # Initialize fast vision pipeline (doesn't need model)
    asyncio.create_task(initialize_fast_vision())
    
    yield
    
    # Cleanup
    if model_manager:
        model_manager.unload_model()

async def initialize_with_model():
    """Initialize model first, then other systems that depend on it."""
    # First load the model
    await initialize_default_model()
    
    # Only after model is loaded, initialize systems that need it
    if current_llm:
        print("🧠 Model loaded, initializing dependent systems...")
        await initialize_smart_memory_system()
        await initialize_fast_personality()
    else:
        print("⚠️ Model not loaded, skipping dependent system initialization")

async def initialize_default_model():
    """Initialize default model asynchronously in the background."""
    global model_manager, current_llm, model_ready
    
    try:
        print("📦 Checking for default model...")
        installer = DefaultModelInstaller()
        
        # Ensure default model is available (download if needed)
        default_model_id = await installer.ensure_default_model()
        
        if default_model_id:
            availability = model_manager.is_model_available(default_model_id)
            
            if availability["available"]:
                print(f"🔄 Loading default model: {default_model_id}")
                try:
                    current_llm = await model_manager.load_model(default_model_id)
                    model_ready = True
                    # Update LLM provider for consistent access
                    get_llm_provider().set_llm(current_llm, model_ready)
                    # Connect chat manager to the loaded model
                    chat_manager.set_model(current_llm, model_ready)
                    print("✅ Default model loaded and ready.")
                except Exception as e:
                    print(f"❌ Failed to load default model: {e}")
                    print("⚠️ Server running without a loaded model.")
            else:
                print(f"⚠️ Default model not yet available: {availability['reason']}")
                print("📦 Model may still be downloading in the background.")
                print("💡 Use /status to check download progress or /switch_model to load a model.")
        else:
            print("⚠️ No default model could be ensured.")
            print("💡 Use the /switch_model endpoint to load a model.")
    except Exception as e:
        print(f"❌ Error initializing default model: {e}")
        print("⚠️ Server running without a loaded model.")

async def initialize_smart_memory_system():
    """Initialize the new smart memory system."""
    global smart_memory, background_learning, instant_memory_api, hybrid_memory
    
    try:
        print("🧠 Initializing Smart Memory System...")
        
        # Initialize smart memory (use global instance)
        smart_memory = get_smart_memory()
        
        # Initialize background learning service
        background_learning = initialize_background_learning()
        
        # Initialize instant memory API
        instant_memory_api = InstantMemoryAPI()
        
        # Initialize hybrid memory system
        print("🔗 Initializing Hybrid Memory System...")
        hybrid_memory = HybridMemorySystem()
        await hybrid_memory.initialize()
        print("✅ Hybrid Memory System initialized successfully")
        
        print("✅ Smart Memory System initialized successfully")
        
    except Exception as e:
        print(f"❌ Failed to initialize Smart Memory System: {e}")
        print("⚠️ Memory features will be limited")

async def initialize_fast_personality():
    """Initialize fast personality mode with smart memory integration."""
    global fast_personality, instant_memory_api, model_ready
    
    # Wait for model to be ready
    while not model_ready:
        await asyncio.sleep(1)
    
    try:
        print("⚡ Initializing Fast Personality Mode with Smart Memory...")
        fast_personality = FastPersonalityMode(
            personality_manager=personality_manager,
            chat_manager=chat_manager,
            instant_memory_api=instant_memory_api
        )
        print("✅ Fast Personality Mode initialized successfully!")
        print("🚀 Personality responses optimized with instant memory access")
    except Exception as e:
        print(f"❌ Failed to initialize fast personality mode: {e}")
        fast_personality = None

async def initialize_fast_vision():
    """Initialize fast vision pipeline for improved performance."""
    global fast_vision_pipeline, model_ready
    
    # Wait for system to be ready
    while not model_ready:
        await asyncio.sleep(1)
    
    try:
        print("🔥 Initializing Fast Vision Pipeline...")
        fast_vision_pipeline = initialize_fast_vision_pipeline(sparrow_vlm_engine)
        
        # Pre-warm the vision model in background
        asyncio.create_task(fast_vision_pipeline.warmup_model())
        
        print("✅ Fast Vision Pipeline initialized successfully!")
        print("⚡ Vision analysis optimized for < 5 second response time")
    except Exception as e:
        print(f"❌ Failed to initialize fast vision pipeline: {e}")
        fast_vision_pipeline = None


        print("⚠️ Server running without adaptive personalization")

        print("⚠️ Server running without persistent memory")

        print("⚠️ Server running without fast personalized streaming")

app = FastAPI(lifespan=lifespan)

# Add smart memory endpoints
add_smart_memory_endpoints(app)
add_hybrid_memory_endpoints(app)

# Add memory optimization endpoints
from memory_optimizer import get_memory_optimizer

@app.get("/memory/size_stats")
async def get_memory_size_stats():
    """Get memory usage statistics and optimization recommendations"""
    try:
        optimizer = get_memory_optimizer()
        stats = optimizer.get_memory_size_stats()
        return {
            "success": True,
            "stats": stats
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get memory stats: {e}")

@app.post("/memory/optimize")
async def optimize_memory(user_id: str = None, force: bool = False):
    """Run memory optimization with multiple strategies"""
    try:
        optimizer = get_memory_optimizer()
        results = optimizer.optimize_memories(user_id=user_id, force=force)
        return {
            "success": True,
            "optimization_results": results
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Memory optimization failed: {e}")

@app.post("/memory/auto_optimize")
async def auto_optimize_memory(user_id: str = None):
    """Run automatic optimization if conditions are met"""
    try:
        optimizer = get_memory_optimizer()
        results = optimizer.auto_optimize_if_needed(user_id=user_id)
        
        if results:
            return {
                "success": True,
                "optimization_performed": True,
                "optimization_results": results
            }
        else:
            return {
                "success": True,
                "optimization_performed": False,
                "message": "No optimization needed at this time"
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Auto-optimization failed: {e}")

# Include download manager routes
from downloadManager import app as download_app
app.mount("/downloads", download_app)

# Include model hub search routes (if available)
try:
    from model_hub import app as search_app
    app.mount("/search", search_app)
    print("✅ Model search functionality enabled")
except ImportError as e:
    print(f"⚠️ Model search functionality disabled. Missing dependencies: {e}")
    print("💡 To enable search, install: pip install -r search_requirements.txt")

# Include API key management routes
try:
    from api_key_manager import app as api_keys_app
    app.mount("/api_keys", api_keys_app)
    print("✅ API key management enabled")
except ImportError as e:
    print(f"⚠️ API key management disabled. Missing dependencies: {e}")
    print("💡 To enable API keys, install: pip install cryptography aiohttp")

@app.get("/health")
def health():
    """Health check endpoint."""
    return {"status": "healthy", "service": "ruma-ai-server"}

@app.get("/status")
def status():
    """Get the current status of the model and server."""
    global model_ready, model_manager
    
    current_info = None
    if model_manager:
        current_info = model_manager.get_current_model_info()
    
    return {
        "ready": model_ready,
        "current_model": current_info
    }

@app.get("/")
def read_root():
    return {"message": "Welcome To Ruma AI - Unified MLX & LlamaCpp Engine"}

@app.get("/server_info")
def get_server_info():
    """Get server configuration information."""
    return {
        "host": server_config.host,
        "port": server_config.port,
        "url": server_config.get_server_url() if server_config.port else None,
        "available_ports": server_config.scan_available_ports(),
        "default_ports": server_config.DEFAULT_PORTS
    }

@app.post("/check_model")
async def check_model(request: ModelCheckRequest):
    """Check if a model is available locally."""
    global model_manager
    
    if not model_manager:
        raise HTTPException(status_code=500, detail="Model manager not initialized")
    
    availability = model_manager.is_model_available(request.model_id)
    return availability

@app.post("/switch_model")
async def switch_model(request: ModelSwitchRequest):
    """Switch to a different model."""
    global model_manager, current_llm, model_ready, stop_stream
    
    if not model_manager:
        raise HTTPException(status_code=500, detail="Model manager not initialized")
    
    # Stop any ongoing streams
    stop_stream = True
    await asyncio.sleep(0.1)  # Give time for streams to stop
    
    try:
        # Determine model source
        force_source = None
        if request.model_source:
            force_source = ModelSource.LOCAL if request.model_source == "local" else ModelSource.API
        
        # If this is an API model request, skip availability check for local models
        if force_source == ModelSource.API or ":" in request.model_id:
            # Direct load API model
            model_ready = False
            print(f"🔄 Switching to API model: {request.model_id}")
            
            current_llm = await model_manager.load_model(request.model_id, force_source=ModelSource.API)
            model_ready = True
            # Update LLM provider for consistent access
            get_llm_provider().set_llm(current_llm, model_ready)
            # Connect chat manager to the loaded model
            chat_manager.set_model(current_llm, model_ready)
            
            return {
                "status": "success",
                "message": f"Successfully switched to API model {request.model_id}",
                "model_info": model_manager.get_current_model_info()
            }
        
        # Check if local model is available
        availability = model_manager.is_model_available(request.model_id)
        
        if not availability["available"]:
            # Model not available, trigger download if needed
            model_type = request.model_type or availability.get("model_type", "mlx")
            
            # Start download using download manager
            if model_type == "gguf":
                # For GGUF, we need to specify the file name
                # This is a simplified approach - you might want to implement
                # a more sophisticated way to determine the GGUF file name
                files = [f"{request.model_id.split('/')[-1]}.gguf"]
            else:
                files = []  # MLX models - download manager will figure out files
            
            download_result = download_manager.start_download(
                request.model_id, 
                model_type, 
                files
            )
            
            return {
                "status": "download_required",
                "download_status": download_result,
                "message": f"Model {request.model_id} is being downloaded."
            }
        
        # Model is available, load it
        model_ready = False
        print(f"🔄 Switching to local model: {request.model_id}")
        
        current_llm = await model_manager.load_model(request.model_id, force_source=force_source)
        model_ready = True
        # Update LLM provider for consistent access
        get_llm_provider().set_llm(current_llm, model_ready)
        # Connect chat manager to the loaded model
        chat_manager.set_model(current_llm, model_ready)
        
        return {
            "status": "success",
            "message": f"Successfully switched to {request.model_id}",
            "model_info": model_manager.get_current_model_info()
        }
        
    except Exception as e:
        model_ready = False
        raise HTTPException(status_code=500, detail=f"Failed to switch model: {str(e)}")

@app.post("/chat")
async def chat_endpoint(request: ChatRequest):
    """Enhanced chat endpoint with hybrid memory integration and urgency modes."""
    global stop_stream, current_llm, model_ready, hybrid_memory
    
    if not model_ready or not current_llm:
        raise HTTPException(status_code=503, detail="No model loaded. Use /switch_model to load a model.")

    user_message = request.input
    user_id = request.user_id
    urgency_mode = request.urgency_mode
    memory_types = request.memory_types or ["fact", "preference", "pattern", "skill", "goal", "event"]
    stop_stream = False  # Reset stop before new chat

    async def generate_sse():
        global stop_stream
        try:
            # Get personalized prompt using hybrid memory system
            personalized_prompt = user_message
            relevant_memories = []
            
            if hybrid_memory:
                try:
                    # Use hybrid memory retrieval with urgency mode
                    print(f"🔗 Using hybrid memory retrieval (urgency: {urgency_mode})")
                    search_request = {
                        "user_id": user_id,
                        "query": user_message,
                        "urgency_mode": urgency_mode,
                        "memory_types": memory_types,
                        "limit": 15 if urgency_mode == "comprehensive" else 10 if urgency_mode == "normal" else 5
                    }
                    
                    retrieval_result = await hybrid_memory.retrieve_memories(
                        query=search_request["query"],
                        user_id=search_request["user_id"],
                        urgency=search_request["urgency_mode"],
                        memory_types=search_request["memory_types"],
                        limit=search_request["limit"]
                    )
                    
                    if retrieval_result.memories:
                        relevant_memories = retrieval_result.memories
                        print(f"🧠 Retrieved {len(relevant_memories)} memories using {retrieval_result.search_strategy} (latency: {retrieval_result.latency_ms:.1f}ms)")
                        
                        # Build context from retrieved memories
                        memory_context = "\n".join([
                            f"• {memory.content} (type: {memory.memory_type}, importance: {memory.importance:.2f})"
                            for memory in relevant_memories
                        ])
                        
                        personalized_prompt = f"""You are an AI assistant with access to relevant user memories. Use this context to provide personalized, informed responses.

=== RELEVANT USER MEMORIES ===
{memory_context}

=== CURRENT MESSAGE ===
User: {user_message}

Please provide a helpful response that takes into account the user's history, preferences, and context from their memories."""
                    
                except Exception as e:
                    print(f"⚠️ Hybrid memory failed, using basic prompt: {e}")
                    personalized_prompt = f"User: {user_message}"
            else:
                print("⚠️ Hybrid memory not available, using basic prompt")
                personalized_prompt = f"User: {user_message}"
            
            # Stream the personalized response
            full_response = ""
            start_time = time.time()
            
            for chunk in current_llm.stream(personalized_prompt):
                if stop_stream:
                    print("🛑 Stream manually stopped")
                    break
                
                # Use universal chunk content extractor
                chunk_content = extract_chunk_content(chunk, "hybrid_chat")
                full_response += chunk_content
                
                json_chunk = json.dumps({"content": chunk_content})
                yield f"data: {json_chunk}\n\n"
                await asyncio.sleep(0)  # allow cancellation
            
            response_time = (time.time() - start_time) * 1000
            print(f"⚡ Response generated in {response_time:.1f}ms with {len(relevant_memories)} memory context")
            
            # Store the new conversation in hybrid memory for future retrieval
            if hybrid_memory and full_response:
                try:
                    # Extract and store new memories from this conversation
                    conversation_memories = extract_important_facts(user_message, full_response)
                    
                    # Debug: Check what memories were extracted
                    print(f"🔍 Extracted {len(conversation_memories)} potential memories")
                    valid_memories = 0
                    
                    for memory_fact in conversation_memories:
                        # Skip memories with empty content
                        if not memory_fact.get("content") or not memory_fact["content"].strip():
                            continue
                            
                        # Create a MemoryEntry object for the hybrid memory system
                        memory_entry = MemoryEntry(
                            id=str(uuid.uuid4()),
                            user_id=user_id,
                            content=memory_fact["content"],
                            memory_type=map_legacy_memory_type(memory_fact["type"]),
                            importance=convert_importance_to_float(memory_fact.get("importance", 0.5)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=memory_fact.get("keywords", []),
                            context=f"Original message: {user_message}",
                            confidence=memory_fact.get("confidence", 0.7),
                            category=memory_fact.get("category", ""),
                            temporal_pattern="",
                            related_memories=[],
                            metadata={
                                "source": "chat_conversation",
                                "response_time": response_time,
                                "urgency_mode": urgency_mode
                            }
                        )
                        
                        await hybrid_memory.store_memory(memory_entry)
                        valid_memories += 1
                    
                    print(f"💾 Stored {valid_memories} new memories from conversation (extracted {len(conversation_memories)} total)")
                    
                except Exception as e:
                    print(f"⚠️ Failed to store conversation memories: {e}")
                    
            # Queue conversation for background learning (legacy system)
            if background_learning and full_response:
                try:
                    chat_id = f"chat_{int(time.time())}"
                    messages = [
                        {"role": "user", "content": user_message},
                        {"role": "assistant", "content": full_response}
                    ]
                    # Use original SmartMemorySystem background learning
                    print(f"🧠 Sending chat {chat_id} to background learning queue")
                    if smart_memory:
                        smart_memory.queue_chat_for_learning(user_id, chat_id, messages)
                except Exception as e:
                    print(f"⚠️ Failed to queue for learning: {e}")
                    
        except asyncio.CancelledError:
            print("⚠️ Streaming cancelled")
            raise
        except Exception as e:
            import traceback
            print(f"❌ Streaming error: {e}")
            print(f"❌ Stack trace: {traceback.format_exc()}")
            error_chunk = json.dumps({"error": str(e)})
            yield f"data: {error_chunk}\n\n"

    return StreamingResponse(generate_sse(), media_type="text/event-stream")

@app.post("/stop")
async def stop_generation():
    """Stop the current generation."""
    global stop_stream
    stop_stream = True
    return {"status": "stopping"}

def is_vision_model(model_name: str) -> bool:
    """Check if a model is a vision model by checking against known vision models."""
    # Get vision models from sparrow VLM engine
    vision_models = sparrow_vlm_engine.get_model_info().get("available_models", {})
    
    # Check if the model name matches any vision model
    for model_config in vision_models.values():
        if model_config.get("model_name") == model_name:
            return True
    
    # Also check common vision model patterns
    vision_patterns = [
        "VL-", "vl-", "vision", "Vision", "vlm", "VLM", 
        "Qwen2.5-VL", "LLaVA", "llava", "LLAVA"
    ]
    
    for pattern in vision_patterns:
        if pattern in model_name:
            return True
    
    return False

def clean_repetitive_response(text: str) -> str:
    """Clean repetitive patterns from model responses"""
    if not text or len(text) < 100:
        return text
    
    import re
    
    # Split into sentences for analysis
    sentences = text.split('.')
    cleaned_sentences = []
    seen_patterns = set()
    
    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue
        
        # Handle excessive comma-separated lists (like your example)
        comma_parts = sentence.split(',')
        if len(comma_parts) > 8:  # Likely repetitive list
            unique_parts = []
            seen_parts = set()
            
            for part in comma_parts:
                part = part.strip().strip('"').strip()
                if part and part not in seen_parts and len(unique_parts) < 8:
                    unique_parts.append(part)
                    seen_parts.add(part)
            
            if unique_parts:
                cleaned_sentence = ', '.join(unique_parts)
                if len(comma_parts) > len(unique_parts):
                    cleaned_sentence += " [and other repeated items]"
                cleaned_sentences.append(cleaned_sentence)
            continue
        
        # Check for sentence-level repetition
        words = sentence.split()
        if len(words) > 3:
            sentence_pattern = ' '.join(words[:4])  # First 4 words as pattern
            if sentence_pattern in seen_patterns:
                continue  # Skip repeated sentence patterns
            seen_patterns.add(sentence_pattern)
        
        cleaned_sentences.append(sentence)
    
    # Reconstruct text
    cleaned_text = '. '.join(cleaned_sentences)
    
    # Remove excessive whitespace and newlines
    cleaned_text = re.sub(r'\n\s*\n\s*\n+', '\n\n', cleaned_text)
    cleaned_text = re.sub(r'[ \t]+', ' ', cleaned_text)
    
    # If we cleaned up significantly, add a note
    if len(cleaned_text) < len(text) * 0.6:
        cleaned_text += "\n\n[Note: Repetitive content was automatically cleaned up for better readability]"
    
    return cleaned_text

@app.get("/models")
async def list_available_models():
    """List all available models (local and API), excluding vision models."""
    global model_manager
    
    if not model_manager:
        raise HTTPException(status_code=500, detail="Model manager not initialized")
    
    # Get local models
    models_dir = model_manager.model_directory
    base_dir = model_manager.base_dir
    full_models_path = os.path.join(base_dir, models_dir)
    
    local_models = []
    
    if os.path.exists(full_models_path):
        for item in os.listdir(full_models_path):
            item_path = os.path.join(full_models_path, item)
            
            if os.path.isdir(item_path):
                # Skip vision models - they should only appear in /vision_models
                if is_vision_model(item):
                    continue
                
                # Check what type of model this is
                model_type = model_manager.detect_model_type(item)
                availability = model_manager.is_model_available(item)
                
                local_models.append({
                    "model_id": item,
                    "model_type": model_type.value,
                    "model_source": "local",
                    "available": availability["available"],
                    "path": item_path
                })
    
    # Get API models with real IDs
    api_models = await get_real_api_models()
    
    # Combine all models
    all_models = local_models + api_models
    
    return {
        "models": all_models,
        "local_models": len(local_models),
        "api_models": len(api_models),
        "total": len(all_models),
        "current_model": model_manager.get_current_model_info()
    }

async def get_real_api_models():
    """Get real API models from providers."""
    api_models = []
    
    try:
        from api_key_manager import api_key_manager
        
        # Check each provider for configured API keys
        for provider in ["llm_vin", "openai", "claude"]:
            api_key = api_key_manager.get_api_key(provider)
            if api_key:
                try:
                    if provider == "llm_vin":
                        models = await api_key_manager.get_llm_vin_models(api_key)
                        for model in models:
                            api_models.append({
                                "model_id": f"llm_vin:{model['id']}",
                                "model_type": "api",
                                "model_source": "api",
                                "provider": "llm_vin",
                                "engine": "api_llm_vin",
                                "loaded": False,
                                "available": True,
                                "display_name": model['id'],
                                "raw_id": model['id'],  # Original ID from API
                                "is_image_model": model.get("is_image_model", False),
                                "supports_text": model.get("supports_text", True),
                                "capabilities": ["image_generation"] if model.get("is_image_model", False) else ["text_chat"]
                            })
                    elif provider == "openai":
                        models = await api_key_manager.get_openai_models(api_key)
                        for model in models:
                            model_id = model['id']
                            is_image_model = "dall-e" in model_id.lower()
                            api_models.append({
                                "model_id": f"openai:{model_id}",
                                "model_type": "api", 
                                "model_source": "api",
                                "provider": "openai",
                                "engine": "api_openai",
                                "loaded": False,
                                "available": True,
                                "display_name": model_id,
                                "raw_id": model_id,
                                "is_image_model": is_image_model,
                                "supports_text": not is_image_model,
                                "capabilities": ["image_generation"] if is_image_model else ["text_chat"]
                            })
                    elif provider == "claude":
                        models = await api_key_manager.get_claude_models(api_key)
                        for model in models:
                            model_id = model['id']
                            api_models.append({
                                "model_id": f"claude:{model_id}",
                                "model_type": "api",
                                "model_source": "api", 
                                "provider": "claude",
                                "engine": "api_claude",
                                "loaded": False,
                                "available": True,
                                "display_name": model_id,
                                "raw_id": model_id,
                                "is_image_model": False,  # Claude doesn't generate images
                                "supports_text": True,
                                "capabilities": ["text_chat"]
                            })
                except Exception as e:
                    print(f"Error fetching {provider} models: {e}")
    except ImportError:
        print("API key manager not available for API models")
    except Exception as e:
        print(f"Error fetching API models: {e}")
    
    return api_models

@app.get("/api_models_only")
async def get_api_models_only():
    """Get only API models with real IDs from providers."""
    api_models = await get_real_api_models()
    return {
        "api_models": api_models,
        "total": len(api_models),
        "providers": list(set([model["provider"] for model in api_models]))
    }

@app.get("/download_status")
async def get_download_status():
    """Get status of all downloads."""
    return download_manager.get_all_downloads()

@app.post("/set_model_preference")
async def set_model_preference(request: ModelPreferenceRequest):
    """Set preference for local vs API models."""
    global model_manager
    
    if not model_manager:
        raise HTTPException(status_code=500, detail="Model manager not initialized")
    
    if request.preference not in ["local", "api"]:
        raise HTTPException(status_code=400, detail="Preference must be 'local' or 'api'")
    
    preference = ModelSource.LOCAL if request.preference == "local" else ModelSource.API
    model_manager.set_model_preference(preference)
    
    return {
        "status": "success",
        "preference": request.preference,
        "message": f"Model preference set to {request.preference}"
    }

@app.get("/all_models")
async def get_all_available_models():
    """Get all available models (local and API)."""
    global model_manager
    
    if not model_manager:
        raise HTTPException(status_code=500, detail="Model manager not initialized")
    
    # Get local models
    local_models = []
    models_dir = model_manager.model_directory
    base_dir = model_manager.base_dir
    full_models_path = os.path.join(base_dir, models_dir)
    
    if os.path.exists(full_models_path):
        for item in os.listdir(full_models_path):
            item_path = os.path.join(full_models_path, item)
            
            if os.path.isdir(item_path):
                model_type = model_manager.detect_model_type(item)
                availability = model_manager.is_model_available(item)
                
                local_models.append({
                    "model_id": item,
                    "model_type": model_type.value,
                    "model_source": "local",
                    "available": availability["available"],
                    "path": item_path
                })
    
    # Get API models with real IDs
    api_models = await get_real_api_models()
    
    current_info = model_manager.get_current_model_info()
    
    return {
        "local_models": local_models,
        "api_models": api_models,
        "total_local": len(local_models),
        "total_api": len(api_models),
        "current_model": current_info,
        "model_preference": model_manager.model_selection_preference.value
    }

# Chat History Endpoints
@app.post("/chat_history")
async def chat_with_history(request: ChatHistoryRequest):
    """Enhanced chat endpoint with history and memory management."""
    try:
        result = await chat_manager.process_message(
            user_id=request.user_id,
            message=request.message,
            chat_id=request.chat_id
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Chat processing failed: {str(e)}")

@app.post("/chat_history_stream")
async def chat_with_history_stream(request: ChatHistoryRequest):
    """Enhanced streaming chat endpoint with hybrid memory integration."""
    global stop_stream, hybrid_memory
    
    if not model_ready or not current_llm:
        raise HTTPException(status_code=503, detail="No model loaded. Use /switch_model to load a model.")
    
    stop_stream = False  # Reset stop before new chat
    
    async def generate_history_sse():
        try:
            # Ensure we have a valid chat_id for message storage
            actual_chat_id = request.chat_id
            if not actual_chat_id:
                actual_chat_id = chat_manager.create_chat_session(request.user_id)
                print(f"✅ Created new chat session: {actual_chat_id}")
            
            # Get hybrid memory retrieval with urgency mode
            user_message = request.message
            user_id = request.user_id
            urgency_mode = request.urgency_mode
            memory_types = request.memory_types or ["fact", "preference", "pattern", "skill", "goal", "event"]
            
            # Build context with hybrid memory and chat history
            personalized_prompt = user_message
            relevant_memories = []
            
            if hybrid_memory:
                try:
                    print(f"🔗 Memory retrieval: '{user_message}' | Mode: {urgency_mode} | Strategy: hybrid")
                    search_request = {
                        "user_id": user_id,
                        "query": user_message,
                        "urgency_mode": urgency_mode,
                        "memory_types": memory_types,
                        "limit": 15 if urgency_mode == "comprehensive" else 10 if urgency_mode == "normal" else 5
                    }
                    
                    retrieval_result = await hybrid_memory.retrieve_memories(
                        query=search_request["query"],
                        user_id=search_request["user_id"],
                        urgency=search_request["urgency_mode"],
                        memory_types=search_request["memory_types"],
                        limit=search_request["limit"]
                    )
                    
                    if retrieval_result.memories:
                        relevant_memories = retrieval_result.memories
                        print(f"🧠 Retrieved {len(relevant_memories)} memories using {retrieval_result.search_strategy} (latency: {retrieval_result.latency_ms:.1f}ms)")
                        
                        # Build context from retrieved memories
                        memory_context = "\n".join([
                            f"• {memory.content} (type: {memory.memory_type}, importance: {memory.importance:.2f})"
                            for memory in relevant_memories
                        ])
                        
                        # Enhanced personalized prompt with memory context
                        personalized_prompt = f"""[MEMORY CONTEXT - What you know about this user]
{memory_context}

[USER MESSAGE]
{user_message}

Please respond naturally while being aware of the context above. Don't explicitly mention that you retrieved memories unless directly relevant."""
                    else:
                        print(f"ℹ️ No relevant memories found for user {user_id}")
                        
                except Exception as e:
                    print(f"⚠️ Hybrid memory failed, using message without memory: {e}")
                    
            # Get recent chat history
            history = chat_manager.get_chat_history(actual_chat_id, limit=10)
            
            # Build conversation context
            if history:
                conversation_parts = []
                for msg in history:
                    if hasattr(msg, 'content'):
                        role = "User" if "Human" in str(type(msg)) else "Assistant"
                        conversation_parts.append(f"{role}: {msg.content}")
                
                if conversation_parts:
                    conversation_context = "\n".join(conversation_parts)
                    personalized_prompt = f"""[RECENT CONVERSATION HISTORY]
{conversation_context}

{personalized_prompt}"""
            
            # Stream response using the personalized prompt
            full_response = ""
            for chunk in current_llm.stream(personalized_prompt):
                if stop_stream:
                    print("🛑 Stream manually stopped")
                    break
                
                # Use universal chunk content extractor
                chunk_content = extract_chunk_content(chunk, "chat_history_stream")
                
                full_response += chunk_content
                json_chunk = json.dumps({"content": chunk_content})
                yield f"data: {json_chunk}\n\n"
                await asyncio.sleep(0)  # allow cancellation
            
            # STEP 4: Save conversation to chat history
            chat_manager.save_message(actual_chat_id, "human", request.message)
            chat_manager.save_message(actual_chat_id, "ai", full_response)
            
            # STEP 4: Store conversation memories using hybrid system
            if request.user_id and full_response:
                try:
                    # Store conversation in smart memory system for background learning
                    if smart_memory:
                        messages = [
                            {"role": "user", "content": request.message},
                            {"role": "assistant", "content": full_response}
                        ]
                        # Use original SmartMemorySystem background learning
                        print(f"🧠 Sending chat {actual_chat_id} to background learning queue")
                        if smart_memory:
                            smart_memory.queue_chat_for_learning(request.user_id, actual_chat_id, messages)
                    
                except Exception as e:
                    print(f"⚠️ Memory storage failed: {e}")
            
        except asyncio.CancelledError:
            print("⚠️ Streaming cancelled")
            raise
        except Exception as e:
            print(f"❌ Streaming error: {e}")
            error_chunk = json.dumps({"error": str(e)})
            yield f"data: {error_chunk}\n\n"

    return StreamingResponse(generate_history_sse(), media_type="text/event-stream")



@app.get("/chat_sessions/{user_id}")
async def get_user_chat_sessions(user_id: str):
    """Get all chat sessions for a user."""
    sessions = chat_manager.get_user_sessions(user_id)
    return {"sessions": sessions}

@app.post("/chat_sessions/{chat_id}/update_title")
async def update_chat_session_title(chat_id: str, request: dict):
    """Update chat session title based on first user message."""
    try:
        first_message = request.get("first_message", "")
        if not first_message:
            raise HTTPException(status_code=400, detail="first_message is required")
        
        success = chat_manager.update_chat_session_title(chat_id, first_message)
        if success:
            return {"success": True, "message": "Chat session title updated"}
        else:
            raise HTTPException(status_code=500, detail="Failed to update chat session title")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating title: {str(e)}")

@app.get("/chat_history/{chat_id}")
async def get_chat_history_endpoint(chat_id: str, limit: int = 500):
    """Get chat history for a specific session."""
    history = chat_manager.get_chat_history(chat_id, limit)
    formatted_history = []
    for msg in history:
        if hasattr(msg, 'content'):
            role = "human" if "Human" in str(type(msg)) else "ai"
            formatted_history.append({
                "role": role,
                "content": msg.content
            })
    return {"history": formatted_history}

@app.get("/chat_sessions/{user_id}/{chat_id}/history")
async def get_chat_session_history(user_id: str, chat_id: str, limit: int = 500):
    """Get chat history for a specific session (alternative endpoint format)."""
    history = chat_manager.get_chat_history(chat_id, limit)
    formatted_history = []
    for msg in history:
        if hasattr(msg, 'content'):
            role = "human" if "Human" in str(type(msg)) else "ai"
            formatted_history.append({
                "role": role,
                "content": msg.content
            })
    return {"history": formatted_history}


@app.get("/user_memory/{user_id}")
async def get_user_memory_endpoint(user_id: str, memory_type: str = "short_term"):
    """Get user memory."""
    memories = chat_manager.get_user_memory(user_id, memory_type)
    return {"memories": memories}

@app.get("/user_preferences/{user_id}")
async def get_user_preferences_endpoint(user_id: str):
    """Get user preferences."""
    preferences = chat_manager.get_user_preferences(user_id)
    return {"preferences": preferences}

@app.put("/user_preferences/{user_id}")
async def update_user_preferences_endpoint(user_id: str, preferences: dict):
    """Update user preferences."""
    chat_manager.update_user_preferences(user_id, preferences)
    return {"status": "updated"}

@app.get("/context_info")
async def get_context_info_endpoint():
    """Get dynamic context management information."""
    from context_manager import get_context_info
    return get_context_info()

@app.delete("/chat_session/{chat_id}")
async def delete_chat_session(chat_id: str):
    """Delete a chat session and all its messages."""
    try:
        import sqlite3
        conn = sqlite3.connect(chat_manager.db_path)
        cursor = conn.cursor()
        
        # Delete messages first (foreign key constraint)
        cursor.execute("DELETE FROM messages WHERE chat_id = ?", (chat_id,))
        
        # Delete session
        cursor.execute("DELETE FROM chat_sessions WHERE id = ?", (chat_id,))
        
        conn.commit()
        conn.close()
        
        return {"status": "deleted", "chat_id": chat_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete session: {str(e)}")

@app.post("/summarize_session/{chat_id}")
async def summarize_chat_session(chat_id: str, keep_recent: int = 20):
    """Summarize old messages in a chat session to optimize context."""
    try:
        chat_manager.summarize_old_messages(chat_id, keep_recent)
        return {"status": "summarized", "chat_id": chat_id, "kept_recent": keep_recent}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to summarize session: {str(e)}")

# Enhanced Image Analysis Endpoint with Sparrow VLM Support
@app.post("/analyze_image")
async def analyze_image(request: ImageAnalysisRequest):
    """Enhanced endpoint supporting both text-only and vision-based analysis."""
    try:
        if not model_ready or not current_llm:
            raise HTTPException(status_code=503, detail="No model loaded")
        
        processing_method = "text_only"
        
        # Try Fast Vision Pipeline if vision is requested and image data is provided
        if request.use_vision and request.image_data and fast_vision_pipeline:
            try:
                import base64
                
                # Decode base64 image data
                image_bytes = base64.b64decode(request.image_data)
                
                # Use Fast Vision Pipeline for optimized analysis
                vision_result, vision_success, response_time = await fast_vision_pipeline.analyze_image_fast(
                    image_bytes, request.text_content, request.question, timeout_seconds=40.0
                )
                print(f"🔍 Fast vision analysis result: {vision_result}")
                
                if vision_success:
                    # Additional cleanup for any remaining repetitive patterns
                    cleaned_result = clean_repetitive_response(vision_result)
                    
                    return {
                        "success": True,
                        "analysis": cleaned_result,
                        "processing_method": "fast_vision_pipeline",
                        "vision_model": sparrow_vlm_engine.current_model or "default",
                        "response_time_seconds": round(response_time, 2)
                    }
                else:
                    # Fall back to text-only analysis
                    print(f"⚠️ Fast vision pipeline failed: {vision_result}")
                    processing_method = "text_fallback"
                    
            except Exception as e:
                print(f"⚠️ Fast vision processing error: {str(e)}")
                processing_method = "text_fallback"
        elif request.use_vision and request.image_data:
            # Fallback to original Sparrow if fast pipeline not available
            try:
                import base64
                image_bytes = base64.b64decode(request.image_data)
                vision_result, vision_success = await analyze_image_with_sparrow(
                    image_bytes, request.text_content, request.question
                )
                
                if vision_success:
                    # Clean repetitive patterns from sparrow fallback too
                    cleaned_result = clean_repetitive_response(vision_result)
                    
                    return {
                        "success": True,
                        "analysis": cleaned_result,
                        "processing_method": "sparrow_vlm_fallback",
                        "vision_model": sparrow_vlm_engine.current_model or "default"
                    }
                else:
                    processing_method = "text_fallback"
            except Exception as e:
                print(f"⚠️ Fallback vision processing error: {str(e)}")
                processing_method = "text_fallback"
        
        # Text-only analysis using main LLM
        prompt = f"""You are an expert screen analysis assistant. The user has captured their screen and extracted text using Apple Vision.

EXTRACTED TEXT FROM SCREEN:
{request.text_content}

USER'S QUESTION:
{request.question}

Analyze the screen content and provide a helpful, specific response to the user's question. Focus on:
1. What application or interface they're looking at
2. Actionable elements they can interact with
3. Specific next steps they can take
4. Reference actual visible text and interface elements"""

        # Stream response from main LLM
        response_chunks = []
        for chunk in current_llm.stream(prompt):
            # Use universal chunk content extractor
            chunk_content = extract_chunk_content(chunk, "analyze_image")
            response_chunks.append(chunk_content)
        
        full_response = "".join(response_chunks)
        
        # Clean repetitive patterns from text-only analysis
        cleaned_response = clean_repetitive_response(full_response)
        
        return {
            "success": True,
            "analysis": cleaned_response,
            "processing_method": processing_method
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Image analysis failed: {str(e)}")

# Vision Model Management Endpoints

@app.get("/vision_models")
async def get_vision_models():
    """Get information about available vision models"""
    try:
        # Get models from Sparrow VLM Engine only
        sparrow_models = sparrow_vlm_engine.get_model_info()
        
        # Convert Sparrow models to the expected format
        vision_models = []
        
        # Add Sparrow VLM models
        for model_key, model_info in sparrow_models.get("available_models", {}).items():
            # Check if model exists locally
            is_local = sparrow_vlm_engine._check_local_model(model_info["model_name"]) is not None
            
            vision_models.append({
                "id": model_key,
                "name": model_info["model_name"].split("/")[-1] if "/" in model_info["model_name"] else model_info["model_name"],
                "description": f"Sparrow VLM - {model_info['model_type']} model",
                "size": "~4-7GB",
                "recommended": model_key in ["qwen2.5-vl-3b", "llava-1.5-7b"],
                "is_local": is_local,
                "is_loaded": sparrow_models.get("current_model") == model_key,
                "status": "ready" if sparrow_models.get("current_model") == model_key else ("available" if is_local else "downloadable"),
                "engine": "sparrow",
                "full_model_name": model_info["model_name"]  # Add full model name for downloads
            })
        
        return vision_models
        
    except Exception as e:
        print(f"Error getting vision models: {e}")
        return {"error": f"Failed to get vision models: {str(e)}"}

@app.get("/vision_performance")
async def get_vision_performance():
    """Get vision pipeline performance statistics"""
    if fast_vision_pipeline:
        stats = fast_vision_pipeline.get_performance_stats()
        return {
            "fast_pipeline_available": True,
            "performance_stats": stats,
            "model_warmed_up": fast_vision_pipeline.model_warmed_up
        }
    else:
        return {
            "fast_pipeline_available": False,
            "message": "Fast vision pipeline not initialized"
        }

@app.get("/memory_analysis_stats")
async def get_memory_analysis_stats():
    """Get intelligent memory analysis performance statistics"""
    if intelligent_memory:
        stats = intelligent_memory.get_analysis_stats()
        return {
            "intelligent_memory_available": True,
            "analysis_stats": stats,
            "processor_running": intelligent_memory.processor_running
        }
    else:
        return {
            "intelligent_memory_available": False,
            "message": "Intelligent memory analyzer not initialized"
        }

@app.get("/langgraph_memory_stats")
async def get_langgraph_memory_stats():
    """Get LangGraph memory system performance statistics"""
    if langgraph_memory:
        stats = langgraph_memory.get_memory_stats()
        return {
            "langgraph_memory_available": True,
            "memory_stats": stats,
            "checkpointer_enabled": True
        }
    else:
        return {
            "langgraph_memory_available": False,
            "message": "LangGraph memory system not initialized"
        }

@app.get("/user_memory_summary/{user_id}")
async def get_user_memory_summary(user_id: str):
    """Get comprehensive memory summary for a user"""
    if langgraph_memory:
        summary = await langgraph_memory.get_user_memory_summary(user_id)
        return summary
    else:
        return {"error": "LangGraph memory system not available"}

@app.post("/vision_models/{model_key}/load")
async def load_vision_model(model_key: str):
    """Load a specific vision model"""
    try:
        # Load via Sparrow VLM Engine
        success = await sparrow_vlm_engine.load_model(model_key)
        if success:
            return {
                "success": True,
                "message": f"Sparrow vision model {model_key} loaded successfully",
                "current_model": model_key,
                "engine": "sparrow"
            }
        else:
            raise HTTPException(status_code=500, detail=f"Failed to load vision model {model_key}")
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error loading vision model: {str(e)}")

@app.post("/vision_models/unload")
async def unload_vision_model():
    """Unload current vision model to free memory"""
    try:
        # Unload Sparrow VLM engine
        await sparrow_vlm_engine.unload_model()
        
        return {
            "success": True,
            "message": "Vision model unloaded successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error unloading vision model: {str(e)}")

@app.get("/vision_models/status")
async def get_vision_model_status():
    """Get current vision model status"""
    try:
        # Get status from Sparrow VLM engine
        model_info = sparrow_vlm_engine.get_model_info()
        
        return {
            "model_loaded": sparrow_vlm_engine.is_model_loaded(),
            "current_model": sparrow_vlm_engine.current_model,
            "sparrow_available": model_info.get("sparrow_available", True)
        }
    except Exception as e:
        print(f"Error getting vision model status: {e}")
        return {
            "model_loaded": False,
            "current_model": None,
            "sparrow_available": False
        }






# Simplified Update Endpoints
class UpdateRequest(BaseModel):
    download_url: str
    auto_install: bool = False

class InstallRequest(BaseModel):
    file_path: str
    auto_install: bool = False

@app.get("/check_updates")
async def check_updates():
    """Check for available updates."""
    result = await simple_updater.check_for_updates()
    if "error" in result:
        raise HTTPException(status_code=500, detail=result["error"])
    return result

@app.post("/download_update")
async def download_update(request: UpdateRequest):
    """Start downloading an update."""
    if simple_updater.is_downloading:
        raise HTTPException(status_code=400, detail="Download already in progress")
    
    # Cancel any existing task first
    if simple_updater.download_task and not simple_updater.download_task.done():
        simple_updater.download_task.cancel()
    
    # Start download in background with auto_install parameter and store task reference
    simple_updater.download_task = asyncio.create_task(
        simple_updater.download_update(request.download_url, request.auto_install)
    )
    return {"message": "Download started", "url": request.download_url, "auto_install": request.auto_install}

@app.post("/install_update")
async def install_update(request: InstallRequest):
    """Install a downloaded update."""
    result = await simple_updater.install_update(request.file_path, request.auto_install)
    if "error" in result:
        raise HTTPException(status_code=500, detail=result["error"])
    return result

@app.get("/download_progress")
async def get_download_progress():
    """Get current download progress."""
    return simple_updater.get_download_progress()

@app.post("/pause_update_download")
async def pause_download():
    """Pause current download."""
    simple_updater.pause_download()
    return {"message": "Download paused"}

@app.post("/resume_update_download")
async def resume_download():
    """Resume paused download."""
    if not simple_updater.resume_download():
        raise HTTPException(status_code=400, detail="Cannot resume download")
    
    state = simple_updater._load_state()
    if state:
        # Cancel any existing task first
        if simple_updater.download_task and not simple_updater.download_task.done():
            simple_updater.download_task.cancel()
        
        # Resume with auto_install=False by default (user can manually install) and store task reference
        simple_updater.download_task = asyncio.create_task(
            simple_updater.download_update(state["url"], auto_install=False)
        )
    
    return {"message": "Download resumed"}

@app.post("/cancel_update_download")
async def cancel_download():
    """Cancel current download."""
    simple_updater.cancel_download()
    return {"message": "Download cancelled"}

@app.get("/app_version")
async def get_app_version():
    """Get current application version."""
    return {
        "version": simple_updater.current_version,
        "platform": os.name,
        "architecture": os.uname().machine if hasattr(os, 'uname') else 'unknown',
        "repo": f"{simple_updater.repo_owner}/{simple_updater.repo_name}"
    }

# App Backup Management Endpoints
class RestoreRequest(BaseModel):
    backup_name: str

class DeleteBackupRequest(BaseModel):
    backup_name: str

@app.get("/app_backups")
async def get_app_backups():
    """Get list of available app version backups."""
    result = simple_updater.get_available_backups()
    if "error" in result:
        raise HTTPException(status_code=500, detail=result["error"])
    return result

@app.post("/restore_backup")
async def restore_from_backup(request: RestoreRequest):
    """Restore app from a specific backup version."""
    result = await simple_updater.restore_from_backup(request.backup_name)
    if "error" in result:
        raise HTTPException(status_code=500, detail=result["error"])
    return result

@app.post("/delete_backup")
async def delete_backup(request: DeleteBackupRequest):
    """Delete a specific backup."""
    result = simple_updater.delete_backup(request.backup_name)
    if "error" in result:
        raise HTTPException(status_code=500, detail=result["error"])
    return result

# Performance Monitoring Endpoints
@app.get("/performance/current")
async def get_current_performance():
    """Get current performance metrics."""
    metrics = performance_monitor.get_current_metrics()
    return {"metrics": metrics} if metrics else {"error": "No metrics available"}

@app.get("/performance/history")
async def get_performance_history(count: int = 100):
    """Get performance metrics history."""
    history = performance_monitor.get_metrics_history(count)
    return {"history": history}

@app.get("/performance/alerts")
async def get_performance_alerts():
    """Get current performance alerts."""
    alerts = performance_monitor.get_alerts()
    recommendations = performance_monitor.get_recommendations()
    return {
        "alerts": alerts,
        "recommendations": recommendations
    }

@app.get("/performance/system_info")
async def get_system_info():
    """Get system information."""
    system_info = performance_monitor.get_system_info()
    return {"system_info": system_info}

@app.post("/performance/optimize")
async def optimize_performance():
    """Perform automatic performance optimizations."""
    result = performance_monitor.optimize_performance()
    return result

@app.post("/performance/export")
async def export_performance_metrics(filename: str = "performance_metrics.json", count: int = 1000):
    """Export performance metrics to file."""
    success = performance_monitor.export_metrics(filename, count)
    return {
        "success": success,
        "filename": filename if success else None,
        "message": "Metrics exported successfully" if success else "Export failed"
    }

# Image Generation Endpoint
@app.post("/generate_image")
async def generate_image(request: ImageGenerationRequest):
    """Generate image using text-to-image models."""
    global model_manager, current_llm
    
    if not model_manager:
        raise HTTPException(status_code=500, detail="Model manager not initialized")
    
    # Check if we have a current model loaded and if it supports image generation
    current_model_info = model_manager.get_current_model_info()
    
    # If a specific model is requested, load it
    if request.model_id:
        try:
            # Check if this is an image model
            api_models = await get_real_api_models()
            target_model = next((m for m in api_models if m["model_id"] == request.model_id), None)
            
            if not target_model:
                raise HTTPException(status_code=404, detail="Model not found")
            
            if not target_model.get("is_image_model", False):
                raise HTTPException(status_code=400, detail="This model does not support image generation")
            
            # Load the image model
            current_llm = await model_manager.load_model(request.model_id, force_source=ModelSource.API)
            # Update LLM provider for consistent access
            get_llm_provider().set_llm(current_llm, True)
            
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to load model: {str(e)}")
    
    # Check if current model supports image generation
    elif current_model_info and current_model_info.get("model_source") == "api":
        # Get model capabilities
        api_models = await get_real_api_models()
        current_model = next((m for m in api_models if m["model_id"] == current_model_info["model_id"]), None)
        
        if not current_model or not current_model.get("is_image_model", False):
            raise HTTPException(status_code=400, detail="Current model does not support image generation. Please switch to an image generation model.")
    else:
        raise HTTPException(status_code=400, detail="No image generation model loaded. Please specify a text-to-image model.")
    
    # Generate image using the API wrapper
    if not current_llm:
        raise HTTPException(status_code=500, detail="No model loaded for image generation")
    
    try:
        # Call the image generation API
        result = await generate_image_with_api(request.prompt, current_llm)
        print(f"Image generation result: {result}")
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Image generation failed: {str(e)}")



async def generate_image_with_api(prompt: str, api_wrapper) -> Dict[str, Any]:
    import requests
    import base64
    import concurrent.futures
    """Generate image using API wrapper (supports llm.vin and OpenAI DALL·E)."""
    provider = api_wrapper.provider
    model    = api_wrapper.model
    api_key  = api_wrapper.api_key

    # Common headers & payload fields
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type":  "application/json",
        "User-Agent": "Ruma-AI/1.0"
    }
    payload = {
        "model":           model,
        "prompt":          prompt,
        "n":               1,
        "size":            "1024x1024",
        "response_format": "b64_json",
    }

    # Pick endpoint
    if provider == "llm_vin":
        url = "https://api.llm.vin/v1/images/generations"
    elif provider == "openai" and "dall-e" in model.lower():
        url = "https://api.openai.com/v1/images/generations"
    else:
        return {
            "success": False,
            "error":   f"Image generation not supported for provider: {provider}",
            "prompt":  prompt,
        }

    def make_request():
        """Make the HTTP request in a thread to avoid blocking the event loop"""
        try:
            # Configure requests session for better reliability
            session = requests.Session()
            session.headers.update(headers)
            
            # Make the request with timeout
            response = session.post(url, json=payload, timeout=120)
            
            if response.status_code != 200:
                return {
                    "success": False,
                    "error": f"API Error {response.status_code}: {response.text}",
                    "prompt": prompt,
                }
            
            return {
                "success": True,
                "data": response.json()
            }
            
        except requests.exceptions.Timeout:
            return {
                "success": False,
                "error": "Request timed out after 120 seconds",
                "prompt": prompt,
            }
        except requests.exceptions.ConnectionError as e:
            return {
                "success": False,
                "error": f"Connection error: {str(e)}",
                "prompt": prompt,
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Network error: {str(e)}",
                "prompt": prompt,
            }
    
    # Run the blocking request in a thread pool
    loop = asyncio.get_event_loop()
    with concurrent.futures.ThreadPoolExecutor() as executor:
        try:
            result = await loop.run_in_executor(executor, make_request)
            
            if not result["success"]:
                return result
                
            response_data = result["data"]
            
            # Process the response data here within the try block
            data = response_data.get("data", [])
            if not data:
                return {
                    "success": False,
                    "error":   "No image data received from API",
                    "prompt":  prompt,
                }

            item = data[0]

            # Case A: b64_json field
            if "b64_json" in item:
                b64 = item["b64_json"]

            # Case B: url field (data URI)
            elif "url" in item and item["url"].startswith("data:"):
                # Strip off the "data:image/...;base64," prefix
                _, b64 = item["url"].split(",", 1)

            else:
                return {
                    "success": False,
                    "error":   "API returned unsupported image format",
                    "prompt":  prompt,
                }

            return {
                "success":    True,
                "image_data": b64,
                "format":     "png",
                "prompt":     prompt,
                "model":      model,
                "provider":   provider,
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Executor error: {str(e)}",
                "prompt": prompt,
            }
# Mount sub-applications
# app.mount("/downloads", download_manager.app)  # Commented out for now

# Try to import and mount search app
try:
    from search_models import app as search_app
    app.mount("/search", search_app)
except ImportError:
    print("Warning: Search models not available")

# Chat Session Cache Performance Endpoint
@app.get("/cache/stats")
async def get_cache_stats():
    """Get chat session cache statistics."""
    try:
        if chat_session_cache:
            stats = chat_session_cache.get_cache_stats()
            return {
                "success": True,
                "cache_stats": stats,
                "message": "Cache statistics retrieved successfully"
            }
        else:
            return {
                "success": False,
                "error": "Chat session cache not initialized"
            }
    except Exception as e:
        return {
            "success": False,
            "error": f"Failed to get cache stats: {e}"
        }

# Chat Session Initialization Endpoint
@app.post("/chat/initialize")
async def initialize_chat_session(request: ChatInitializeRequest):
    """Initialize a new chat session with pre-loaded cache and personalization context."""
    try:
        # Ensure valid chat_id
        actual_chat_id = request.chat_id
        if not actual_chat_id:
            actual_chat_id = chat_manager.create_chat_session(request.user_id)
            print(f"✅ Created new chat session: {actual_chat_id}")
        
        # Pre-load memory cache for this session
        if chat_session_cache:
            print(f"📋 Pre-loading memory cache for chat session {actual_chat_id}")
            await chat_session_cache.get_cached_memories(
                request.user_id, actual_chat_id, "user information preferences facts"
            )
            print(f"💾 Memory cache pre-loaded for session {actual_chat_id}")
        
        # Pre-build personalization context if adaptive system is available
        if adaptive_system:
            try:
                print(f"🎯 Pre-building personalization context for session {actual_chat_id}")
                if chat_session_cache:
                    await chat_session_cache.get_cached_personalization_context(
                        request.user_id, actual_chat_id, adaptive_system.personalization_engine, build_if_missing=True
                    )
                print(f"🎭 Personalization context pre-built for session {actual_chat_id}")
            except Exception as e:
                print(f"⚠️ Failed to pre-build personalization context: {e}")
        
        # Get cache statistics to return
        cache_stats = {}
        if chat_session_cache:
            cache_stats = chat_session_cache.get_cache_stats()
        
        return {
            "success": True,
            "chat_id": actual_chat_id,
            "message": "Chat session initialized with pre-loaded cache",
            "cache_stats": cache_stats,
            "memory_preloaded": bool(chat_session_cache),
            "personalization_preloaded": bool(adaptive_system and chat_session_cache)
        }
        
    except Exception as e:
        print(f"❌ Error initializing chat session: {e}")
        return {
            "success": False,
            "error": f"Failed to initialize chat session: {str(e)}"
        }

# Advanced Memory Management Endpoints
@app.post("/memory/store")
async def store_memory(request: MemoryStoreRequest):
    """Store content in advanced memory with map-reduce processing for large documents."""
    try:
        global hybrid_memory
        if not hybrid_memory:
            raise HTTPException(status_code=503, detail="Memory system not initialized")
        
        memory_ids = await hybrid_memory.store_memory(
            user_id=request.user_id,
            content=request.content,
            memory_type=request.memory_type,
            context=request.context,
            force_chunking=request.force_chunking
        )
        
        return {
            "success": True,
            "memory_ids": memory_ids,
            "count": len(memory_ids),
            "processing_type": "map_reduce" if len(memory_ids) > 1 else "single",
            "message": f"Stored as {len(memory_ids)} memory entries"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to store memory: {str(e)}")

@app.post("/memory/retrieve")
async def retrieve_memories(request: MemoryRetrieveRequest):
    """Retrieve relevant memories based on semantic query."""
    try:
        global hybrid_memory
        if not hybrid_memory:
            raise HTTPException(status_code=503, detail="Memory system not initialized")
        
        memories = await hybrid_memory.retrieve_relevant_memories(
            user_id=request.user_id,
            query=request.query,
            memory_types=request.memory_types,
            limit=request.limit,
            min_importance=request.min_importance
        )
        
        return {
            "success": True,
            "memories": memories,
            "count": len(memories),
            "query": request.query
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to retrieve memories: {str(e)}")

@app.post("/memory/delete")
async def delete_memories(request: MemoryDeleteRequest):
    """Delete memories with advanced filtering options."""
    try:
        global hybrid_memory
        if not hybrid_memory:
            raise HTTPException(status_code=503, detail="Memory system not initialized")
        
        result = await hybrid_memory.delete_memories(
            user_id=request.user_id,
            memory_ids=request.memory_ids,
            memory_types=request.memory_types,
            older_than_days=request.older_than_days,
            importance_threshold=request.importance_threshold
        )
        
        return {
            "success": True,
            "deleted_count": result["deleted_count"],
            "criteria": result["criteria"],
            "timestamp": result["timestamp"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete memories: {str(e)}")

@app.get("/memory/statistics/{user_id}")
async def get_memory_statistics(user_id: str):
    """Get comprehensive memory usage statistics."""
    try:
        smart_memory = get_smart_memory()
        if not smart_memory:
            raise HTTPException(status_code=503, detail="Smart memory system not initialized.")
        
        stats = smart_memory.get_memory_stats(user_id)
        return {"success": True, "statistics": stats}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get memory statistics: {str(e)}")

@app.get("/memory/insights/{user_id}")
async def get_memory_insights(user_id: str):
    """Get insights about user's memory patterns and usage."""
    try:
        global hybrid_memory
        if not hybrid_memory:
            raise HTTPException(status_code=503, detail="Memory system not initialized")
        
        insights = await hybrid_memory.get_memory_insights(user_id)
        return {"success": True, "insights": insights}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get memory insights: {str(e)}")

@app.post("/memory/cleanup/{user_id}")
async def cleanup_user_memory(user_id: str):
    """Perform intelligent memory cleanup and optimization."""
    try:
        global hybrid_memory
        if not hybrid_memory:
            raise HTTPException(status_code=503, detail="Memory system not initialized")
        
        await hybrid_memory._check_and_cleanup_memory(user_id)
        stats = await hybrid_memory.get_memory_statistics(user_id)
        return {
            "success": True,
            "message": "Memory cleanup completed",
            "updated_statistics": stats
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to cleanup memory: {str(e)}")

# ==============================================
# AI PERSONALITY MANAGEMENT ENDPOINTS
# ==============================================

@app.post("/personalities")
async def create_personality(request: CreatePersonalityRequest, user_id: str = "pradhumn"):
    """Create a new AI personality for a user."""
    try:
        print(f"🎭 Creating personality for user: {user_id}")
        print(f"🎭 Request data: {request}")
        
        personality_data = request.dict()
        print(f"🎭 Personality data: {personality_data}")
        
        personality = await personality_manager.create_personality(user_id, personality_data)
        print(f"🎭 Created personality: {personality.name} (ID: {personality.id})")
        
        return {
            "success": True,
            "personality": {
                "id": personality.id,
                "name": personality.name,
                "description": personality.description,
                "personality_traits": personality.personality_traits,
                "communication_style": personality.communication_style,
                "expertise_domains": personality.expertise_domains,
                "avatar_icon": personality.avatar_icon,
                "color_theme": personality.color_theme,
                "is_active": personality.is_active,
                "usage_count": personality.usage_count,
                "created_at": personality.created_at.isoformat()
            },
            "message": None
        }
    except Exception as e:
        print(f"❌ Failed to create personality: {e}")
        print(f"❌ Exception type: {type(e)}")
        import traceback
        print(f"❌ Full traceback: {traceback.format_exc()}")
        
        # Return error in expected format instead of raising HTTPException
        return {
            "success": False,
            "personality": None,
            "message": f"Failed to create personality: {str(e)}"
        }

@app.get("/personalities/{user_id}")
async def get_user_personalities(user_id: str):
    """Get all personalities for a user."""
    try:
        personalities = await personality_manager.get_user_personalities(user_id)
        
        return {
            "success": True,
            "personalities": [
                {
                    "id": p.id,
                    "name": p.name,
                    "description": p.description,
                    "personality_traits": p.personality_traits,
                    "communication_style": p.communication_style,
                    "expertise_domains": p.expertise_domains,
                    "avatar_icon": p.avatar_icon,
                    "color_theme": p.color_theme,
                    "is_active": p.is_active,
                    "usage_count": p.usage_count,
                    "created_at": p.created_at.isoformat()
                }
                for p in personalities
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get personalities: {str(e)}")

@app.get("/personalities/{user_id}/active")
async def get_active_personality(user_id: str):
    """Get the currently active personality for a user."""
    try:
        personality = await personality_manager.get_active_personality(user_id)
        
        if personality:
            return {
                "success": True,
                "personality": {
                    "id": personality.id,
                    "name": personality.name,
                    "description": personality.description,
                    "personality_traits": personality.personality_traits,
                    "communication_style": personality.communication_style,
                    "expertise_domains": personality.expertise_domains,
                    "avatar_icon": personality.avatar_icon,
                    "color_theme": personality.color_theme,
                    "is_active": personality.is_active,
                    "usage_count": personality.usage_count
                }
            }
        else:
            return {"success": False, "message": "No active personality found"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get active personality: {str(e)}")

@app.post("/personalities/{user_id}/switch")
async def switch_personality(user_id: str, request: SwitchPersonalityRequest):
    """Switch to a different personality."""
    try:
        # Normalize username to lowercase for consistency
        user_id = user_id.lower()
        success = await personality_manager.switch_personality(user_id, request.personality_id)
        
        if success:
            return {"success": True, "message": f"Switched to personality {request.personality_id}"}
        else:
            return {"success": False, "message": "Failed to switch personality"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to switch personality: {str(e)}")

@app.put("/personalities/{user_id}/{personality_id}")
async def update_personality(user_id: str, personality_id: str, request: UpdatePersonalityRequest):
    """Update an existing personality."""
    try:
        updates = {k: v for k, v in request.model_dump().items() if v is not None}
        success = await personality_manager.update_personality(user_id, personality_id, updates)
        
        if success:
            return {"success": True, "message": "Personality updated successfully"}
        else:
            return {"success": False, "message": "Personality not found or no changes made"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update personality: {str(e)}")

@app.delete("/personalities/{user_id}/{personality_id}")
async def delete_personality(user_id: str, personality_id: str):
    """Delete a personality."""
    try:
        success = await personality_manager.delete_personality(user_id, personality_id)
        
        if success:
            return {"success": True, "message": "Personality deleted successfully"}
        else:
            return {"success": False, "message": "Cannot delete - personality not found or is the only personality"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete personality: {str(e)}")

@app.post("/chat_with_personality_stream")
async def chat_with_personality_stream(request: ChatWithPersonalityRequest):
    """Chat with a specific AI personality using streaming with hybrid memory."""
    global stop_stream, fast_personality, hybrid_memory, background_learning, smart_memory
    
    if not model_ready or not current_llm:
        raise HTTPException(status_code=503, detail="No model loaded. Use /switch_model to load a model.")
    
    stop_stream = False
    
    async def generate_personality_sse():
        try:
            # Normalize username to lowercase for consistency
            normalized_user_id = request.user_id.lower()
            
            # Get the personality to use
            if request.personality_id:
                personalities = await personality_manager.get_user_personalities(normalized_user_id)
                personality = next((p for p in personalities if p.id == request.personality_id), None)
                if not personality:
                    print(f"❌ Personality {request.personality_id} not found for user {normalized_user_id}")
                    print(f"📋 Available personalities: {[p.id for p in personalities]}")
                    # Fallback to active personality or create default
                    personality = await personality_manager.get_active_personality(normalized_user_id)
                    if not personality:
                        print("💡 No active personality found, falling back to default behavior")
                        # Continue without personality-specific prompts
                        personality = None
                else:
                    print(f"✅ Using personality: {personality.name} (ID: {personality.id})")
            else:
                personality = await personality_manager.get_active_personality(normalized_user_id)
                if personality:
                    print(f"✅ Using active personality: {personality.name} (ID: {personality.id})")
                else:
                    print("💡 No active personality set, using default behavior")
            
            # Ensure valid chat_id
            actual_chat_id = request.chat_id
            if not actual_chat_id:
                actual_chat_id = chat_manager.create_chat_session(normalized_user_id)
                print(f"✅ Created new chat session: {actual_chat_id}")
            
            # Log personality usage (only if personality exists)
            if personality:
                await personality_manager.log_personality_usage(
                    normalized_user_id, personality.id, actual_chat_id
                )
                
                # Build personality-specific system prompt
                personality_prompt = await personality_manager.build_personality_prompt(personality)
                personality_name = personality.name
            else:
                # Use default system behavior without personality
                personality_prompt = ""
                personality_name = "Default"
            
            # print(f"🎭 Personality Prompt : {personality_prompt}")
            # Build prompt with personality and hybrid memory context
            urgency_mode = getattr(request, 'urgency_mode', 'normal')
            memory_types = getattr(request, 'memory_types', None) or ["fact", "preference", "pattern", "skill", "goal", "event"]
            
            if hybrid_memory:
                print(f"🎭 Using personality '{personality_name}' with hybrid memory integration (urgency: {urgency_mode})")
                
                # Get chat history for context
                chat_history = chat_manager.get_chat_history(actual_chat_id, limit=10)
                print(f"📚 Retrieved {len(chat_history)} messages from chat history")
                
                try:
                    print(f"🔗 Memory retrieval: '{request.message}' | Mode: {urgency_mode} | Strategy: hybrid")
                    # Use hybrid memory retrieval with urgency mode
                    search_request = {
                        "user_id": request.user_id,
                        "query": request.message,
                        "urgency_mode": urgency_mode,
                        "memory_types": memory_types,
                        "limit": 15 if urgency_mode == "comprehensive" else 10 if urgency_mode == "normal" else 5
                    }
                    
                    retrieval_result = await hybrid_memory.retrieve_memories(
                        query=search_request["query"],
                        user_id=search_request["user_id"],
                        urgency=search_request["urgency_mode"],
                        memory_types=search_request["memory_types"],
                        limit=search_request["limit"]
                    )
                    # print(retrieval_result)
                    memory_context = ""
                    if retrieval_result.memories:
                        print(f"🧠 Retrieved {len(retrieval_result.memories)} memories using {retrieval_result.search_strategy} (latency: {retrieval_result.latency_ms:.1f}ms)")
                        
                        # Build memory context for personality
                        memory_context = "\n".join([
                            f"• {memory.content} (type: {memory.memory_type}, importance: {memory.importance:.2f})"
                            for memory in retrieval_result.memories
                        ])
                    
                    # Combine personality prompt with hybrid memory context
                    final_prompt = f"""System: {personality_prompt}

                                    === USER MEMORY CONTEXT ===
                                    {memory_context if memory_context else "No specific user memories found for this query."}

                                    === CURRENT MESSAGE ===
                                    User: {request.message}

                                    Instructions: Respond as {personality.name} while incorporating both your personality traits and the user's memory context above. Reference relevant facts, preferences, and conversation history naturally in your personality's voice and style."""
                    
                except Exception as e:
                    print(f"⚠️ Hybrid memory failed, using personality without memory: {e}")
                    final_prompt = f"{personality_prompt}\n\nUser: {request.message}"
                
                print(f"🧠 Using comprehensive prompt with {len(chat_history)} history messages")
                # Stream response using current model
                full_response = ""
                chunk_count = 0
                
                for chunk in current_llm.stream(final_prompt):
                    if stop_stream:
                        print("🛑 Stream manually stopped")
                        break
                    
                    # Use universal chunk content extractor
                    chunk_content = extract_chunk_content(chunk, "personality_stream")
                    full_response += chunk_content
                    chunk_count += 1
                    
                    json_chunk = json.dumps({"content": chunk_content})
                    yield f"data: {json_chunk}\n\n"
                    await asyncio.sleep(0)
                
                print(f"🎭 Personality streaming completed, chunk_count={chunk_count}")
                
                # Save conversation
                chat_manager.save_message(actual_chat_id, "human", request.message)
                chat_manager.save_message(actual_chat_id, "ai", full_response)
                print(f"💾 Saved personality chat for '{personality.name}'")
                
                # Store conversation in hybrid memory for future retrieval
                if hybrid_memory and full_response:
                    try:
                        # Extract and store new memories from this personality conversation
                        conversation_memories = extract_important_facts(request.message, full_response)
                        
                        # Debug: Check what memories were extracted
                        print(f"🔍 Personality chat extracted {len(conversation_memories)} potential memories")
                        valid_memories = 0
                        
                        for memory_fact in conversation_memories:
                            # Skip memories with empty content
                            if not memory_fact.get("content") or not memory_fact["content"].strip():
                                continue
                                
                            # Create a MemoryEntry object for the hybrid memory system
                            memory_entry = MemoryEntry(
                                id=str(uuid.uuid4()),
                                user_id=request.user_id,
                                content=memory_fact["content"],
                                memory_type=map_legacy_memory_type(memory_fact["type"]),
                                importance=convert_importance_to_float(memory_fact.get("importance", 0.5)),
                                created_at=datetime.now().isoformat(),
                                last_accessed=datetime.now().isoformat(),
                                access_count=0,
                                keywords=memory_fact.get("keywords", []),
                                context=f"Personality chat with {personality.name}: {request.message}",
                                confidence=memory_fact.get("confidence", 0.7),
                                category=memory_fact.get("category", ""),
                                temporal_pattern="",
                                related_memories=[],
                                metadata={
                                    "source": "personality_chat",
                                    "personality_name": personality.name,
                                    "personality_id": personality.id,
                                    "chat_id": actual_chat_id,
                                    "urgency_mode": urgency_mode
                                }
                            )
                            
                            await hybrid_memory.store_memory(memory_entry)
                            valid_memories += 1
                        
                        print(f"💾 Stored {valid_memories} new memories from personality conversation (extracted {len(conversation_memories)} total)")
                        
                    except Exception as e:
                        print(f"⚠️ Failed to store personality conversation memories: {e}")
                
                # Queue for smart memory background learning (legacy)
                if smart_memory and request.user_id and full_response:
                    try:
                        formatted_conversation = [
                            {"role": "user", "content": request.message},
                            {"role": "assistant", "content": full_response}
                        ]
                        
                        # Use original SmartMemorySystem background learning
                        print(f"🧠 Sending personality chat {actual_chat_id} to background learning queue")
                        if smart_memory:
                            smart_memory.queue_chat_for_learning(request.user_id, actual_chat_id, formatted_conversation)
                        
                    except Exception as memory_e:
                        print(f"⚠️ Smart memory queuing failed: {memory_e}")
                        # Don't let memory errors break the main response flow
                
            else:
                print("❌ hybrid_memory not available, using fallback")
                
                # Fallback: Direct personality mode without memory
                final_prompt = f"{personality_prompt}\n\nUser: {request.message}"
                
                # Stream response
                full_response = ""
                for chunk in current_llm.stream(final_prompt):
                    if stop_stream:
                        print("🛑 Stream manually stopped")
                        break
                    
                    # Use universal chunk content extractor
                    chunk_content = extract_chunk_content(chunk, "personality_fallback")
                    full_response += chunk_content
                    
                    json_chunk = json.dumps({"content": chunk_content})
                    yield f"data: {json_chunk}\n\n"
                    await asyncio.sleep(0)
                
                # Save conversation
                chat_manager.save_message(actual_chat_id, "human", request.message)
                chat_manager.save_message(actual_chat_id, "ai", full_response)
                print(f"💾 Saved fallback personality chat")
                
        except Exception as e:
            print(f"❌ Personality streaming failed: {e}")
            error_chunk = json.dumps({"error": f"Streaming failed: {str(e)}"})
            yield f"data: {error_chunk}\n\n"
    
    return StreamingResponse(generate_personality_sse(), media_type="text/event-stream")

@app.post("/chat_with_personality_fast")
async def chat_with_personality_fast(request: ChatWithPersonalityRequest):
    """Fast personality chat endpoint optimized for < 2 second response time."""
    global stop_stream, fast_personality, current_llm, model_ready
    
    if not model_ready or not current_llm:
        raise HTTPException(status_code=503, detail="No model loaded. Use /switch_model to load a model.")
    
    if not fast_personality:
        raise HTTPException(status_code=503, detail="Fast personality mode not initialized.")
    
    stop_stream = False
    
    async def generate_fast_personality_sse():
        try:
            # Ensure valid chat_id
            actual_chat_id = request.chat_id
            if not actual_chat_id:
                actual_chat_id = chat_manager.create_chat_session(request.user_id)
                print(f"✅ Created new chat session: {actual_chat_id}")
            
            # Fast streaming with background processing
            async for chunk in fast_personality.stream_fast_personality_response(
                user_id=request.user_id,
                message=request.message,
                personality_id=request.personality_id or "default",
                chat_id=actual_chat_id,
                llm_provider=current_llm
            ):
                if stop_stream:
                    print("🛑 Fast stream manually stopped")
                    break
                    
                json_chunk = json.dumps({"content": chunk})
                yield f"data: {json_chunk}\n\n"
                await asyncio.sleep(0)
                
        except Exception as e:
            print(f"❌ Fast personality streaming error: {e}")
            error_chunk = json.dumps({"error": str(e)})
            yield f"data: {error_chunk}\n\n"
    
    return StreamingResponse(generate_fast_personality_sse(), media_type="text/event-stream")

@app.post("/chat_with_memory_fast")
async def chat_with_memory_fast(request: ChatHistoryRequest):
    """Fast chat endpoint with optimized LangGraph long-term memory integration."""
    global stop_stream, langgraph_memory, current_llm, model_ready
    
    if not model_ready or not current_llm:
        raise HTTPException(status_code=503, detail="No model loaded. Use /switch_model to load a model.")
    
    if not langgraph_memory:
        raise HTTPException(status_code=503, detail="LangGraph memory system not initialized.")
    
    stop_stream = False
    
    async def generate_memory_fast_sse():
        try:
            # Ensure valid chat_id
            actual_chat_id = request.chat_id
            if not actual_chat_id:
                actual_chat_id = chat_manager.create_chat_session(request.user_id)
                print(f"✅ Created new chat session: {actual_chat_id}")
            
            # Stream with LangGraph memory integration
            full_response = ""
            async for chunk in langgraph_memory.stream_with_memory(
                user_id=request.user_id,
                message=request.message,
                chat_id=actual_chat_id,
                llm_provider=current_llm
            ):
                if stop_stream:
                    print("🛑 Memory stream manually stopped")
                    break
                    
                full_response += chunk
                json_chunk = json.dumps({"content": chunk})
                yield f"data: {json_chunk}\n\n"
                await asyncio.sleep(0)
            
            # Save to chat manager
            chat_manager.save_message(actual_chat_id, "human", request.message)
            chat_manager.save_message(actual_chat_id, "ai", full_response)
            print(f"💾 Saved LangGraph memory conversation for user {request.user_id}")
                
        except Exception as e:
            print(f"❌ LangGraph memory streaming error: {e}")
            error_chunk = json.dumps({"error": str(e)})
            yield f"data: {error_chunk}\n\n"
    
    return StreamingResponse(generate_memory_fast_sse(), media_type="text/event-stream")

# Legacy fast_streaming endpoints removed - functionality replaced by smart memory system

@app.get("/persistent_memory_stats")
async def get_persistent_memory_stats():
    """Get smart memory system statistics."""
    smart_memory = get_smart_memory()
    
    if not smart_memory:
        raise HTTPException(status_code=503, detail="Smart memory system not initialized.")
    
    try:
        # Get stats from smart memory system
        system_stats = {
            "total_users": len(smart_memory.ready_memories),
            "background_processor_active": smart_memory.background_processor is not None,
            "ui_active": smart_memory.is_ui_active
        }
        streaming_stats = {}
        
        return {
            "success": True,
            "system_stats": system_stats,
            "streaming_stats": streaming_stats
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get stats: {str(e)}")

@app.get("/user_memory_profile/{user_id}")
async def get_user_memory_profile(user_id: str):
    """Get comprehensive memory profile for a user."""
    smart_memory = get_smart_memory()
    
    if not smart_memory:
        raise HTTPException(status_code=503, detail="Smart memory system not initialized.")
    
    try:
        profile = smart_memory.get_user_profile(user_id)
        memories = smart_memory.get_user_memories(user_id, limit=20)
        activity_stats = {}
        
        return {
            "success": True,
            "profile": profile.__dict__ if profile else None,
            "recent_memories": [memory.__dict__ for memory in memories],
            "activity_stats": activity_stats
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get user profile: {str(e)}")

@app.get("/personalities/{user_id}/stats")
async def get_personality_stats(user_id: str):
    """Get personality usage statistics."""
    try:
        stats = await personality_manager.get_personality_stats(user_id)
        return {"success": True, "stats": stats}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get personality stats: {str(e)}")

def cleanup_on_startup():
    """Clean up resources before starting server"""
    import subprocess
    import psutil
    from pathlib import Path
    
    print("🧹 Performing startup cleanup...")
    
    try:
        # Kill any background learning processes
        subprocess.run(["pkill", "-f", "background_learning_worker"], 
                      capture_output=True, timeout=5)
        print("✅ Cleaned up background workers")
    except:
        pass
    
    try:
        # Clear MLX cache to prevent corruption issues
        mlx_cache = Path.home() / ".cache" / "mlx"
        if mlx_cache.exists():
            import shutil
            shutil.rmtree(mlx_cache)
            print("✅ Cleared MLX cache")
    except Exception as e:
        print(f"⚠️ Cache cleanup warning: {e}")

def start_server_with_protection(preferred_port: Optional[int] = None):
    """Start the server with crash protection and recovery."""
    import signal
    import atexit
    
    # Cleanup on startup
    cleanup_on_startup()
    
    def signal_handler(signum, frame):
        print(f"\n🛑 Received signal {signum}, shutting down gracefully...")
        # Cleanup background processes
        import subprocess
        try:
            subprocess.run(["pkill", "-f", "background_learning_worker"], 
                          capture_output=True, timeout=3)
        except:
            pass
        exit(0)
    
    def cleanup_on_exit():
        print("🧹 Cleaning up on exit...")
        import subprocess
        try:
            subprocess.run(["pkill", "-f", "background_learning_worker"], 
                          capture_output=True, timeout=3)
        except:
            pass
    
    # Register cleanup handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    atexit.register(cleanup_on_exit)
    
    try:
        port = server_config.find_available_port(preferred_port)
        server_url = server_config.get_server_url()
        
        print(f"🚀 Starting Ruma AI Server on {server_url}")
        print(f"📊 Server Info: GET {server_url}/server_info")
        print(f"🔧 API Docs: {server_url}/docs")
        print(f"🛡️ Crash protection enabled")
        
        uvicorn.run(
            app, 
            host=server_config.host, 
            port=port,
            access_log=False,
            log_level="info",
        )
    except Exception as e:
        print(f"❌ Server crashed: {e}")
        cleanup_on_exit()
        raise

def start_server(preferred_port: Optional[int] = None):
    """Legacy start function - redirects to protected version"""
    start_server_with_protection(preferred_port)

if __name__ == "__main__":
    start_server_with_protection()
