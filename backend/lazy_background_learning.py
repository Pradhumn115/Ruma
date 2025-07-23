"""
Lazy Background Learning with MLX
=================================

Uses MLX's built-in lazy loading to create a lightweight background learning system
that doesn't conflict with the main UI model by loading model weights on-demand.
"""

import threading
import time
import json
from typing import List, Dict, Any, Optional
from datetime import datetime


class LazyMLXBackgroundLearning:
    """Background learning using MLX lazy loading - memory efficient and conflict-free"""
    
    def __init__(self):
        self.pending_chats = []
        self.processing_lock = threading.Lock()
        self.lazy_model = None
        self.lazy_tokenizer = None
        self.is_processing = False
        self.ui_active = False
        
    def queue_chat_for_learning(self, user_id: str, chat_id: str, messages: List[Dict]):
        """Queue a chat for lazy background learning"""
        with self.processing_lock:
            chat_data = {
                "user_id": user_id,
                "chat_id": chat_id,
                "messages": messages,
                "queued_at": datetime.now().isoformat()
            }
            self.pending_chats.append(chat_data)
            print(f"📚 Queued chat {chat_id} for lazy learning ({len(self.pending_chats)} pending)")
            
            # Start processing if not active and UI is not active
            if not self.is_processing and not self.ui_active:
                self.start_background_processing()
    
    def on_ui_opened(self):
        """Handle UI opening - set flag but don't forcefully stop"""
        with self.processing_lock:
            self.ui_active = True
            print("🔴 UI opened - background learning will pause after current operation")
    
    def on_ui_closed(self):
        """Handle UI closing - can start background processing"""
        with self.processing_lock:
            self.ui_active = False
            print("🟢 UI closed - background learning can resume")
            
            # Start processing if we have pending chats
            if self.pending_chats and not self.is_processing:
                # Small delay to ensure UI is fully closed
                threading.Timer(3.0, self.start_background_processing).start()
    
    def start_background_processing(self):
        """Start background processing in a separate thread"""
        if self.is_processing:
            return
            
        with self.processing_lock:
            self.is_processing = True
        
        # Run processing in background thread
        thread = threading.Thread(target=self._background_worker, daemon=True)
        thread.start()
    
    def _background_worker(self):
        """Background worker that processes chats with lazy model loading"""
        try:
            print("🧠 Starting lazy background learning worker")
            
            # Initialize lazy model (only loads weights when actually used)
            if not self._initialize_lazy_model():
                return
            
            while True:
                with self.processing_lock:
                    # Stop if UI becomes active or no pending chats
                    if self.ui_active or not self.pending_chats:
                        break
                    
                    # Get next chat to process
                    chat_data = self.pending_chats.pop(0)
                
                # Process the chat (this is where model weights get loaded on-demand)
                try:
                    self._process_chat_lazy(chat_data)
                    time.sleep(1)  # Brief pause between chats
                except Exception as e:
                    print(f"❌ Error processing chat {chat_data['chat_id']}: {e}")
            
            print("✅ Lazy background learning worker finished")
            
        except Exception as e:
            print(f"❌ Background worker failed: {e}")
        finally:
            with self.processing_lock:
                self.is_processing = False
    
    def _initialize_lazy_model(self) -> bool:
        """Initialize lazy MLX model (doesn't load weights until first use)"""
        try:
            # Import here to avoid conflicts
            from langchain_community.llms.mlx_pipeline import MLXPipeline
            from model_manager import ModelManager
            
            # Get current model path
            model_manager = ModelManager()
            current_model_id = model_manager.current_model_id
            
            # Fallback to default model if no current model
            if not current_model_id:
                current_model_id = model_manager.default_model
                print(f"⚠️ No current model, using default: {current_model_id}")
            
            # Build full model path
            import os
            model_path = os.path.join(model_manager.model_directory, current_model_id)
            
            print(f"🔄 Initializing lazy MLX model: {model_path}")
            
            # Check if model exists before trying to load
            if not os.path.exists(model_path):
                print(f"❌ Model path does not exist: {model_path}")
                return False
            
            # Create lazy pipeline - weights not loaded yet!
            self.lazy_model = MLXPipeline.from_model_id(
                model_id=model_path,
                lazy=True  # This is the key! Only loads weights when needed
            )
            
            print("✅ Lazy MLX model initialized (weights not loaded yet)")
            return True
            
        except Exception as e:
            print(f"❌ Failed to initialize lazy model: {e}")
            return False
    
    def _process_chat_lazy(self, chat_data: Dict):
        """Process a single chat using lazy model loading"""
        try:
            user_id = chat_data["user_id"]
            chat_id = chat_data["chat_id"]
            messages = chat_data["messages"]
            
            print(f"🧠 Processing chat {chat_id} with lazy loading")
            
            # Check if UI became active before expensive operation
            if self.ui_active:
                print("⏹️ UI became active - postponing chat processing")
                # Put chat back in queue for later
                with self.processing_lock:
                    self.pending_chats.insert(0, chat_data)
                return
            
            # Use existing smart memory system for extraction
            from smart_memory_system import get_smart_memory
            smart_memory = get_smart_memory()
            
            # Extract memories using the existing system
            # Note: The lazy model weights will be loaded here on first use
            memories = smart_memory._extract_memories_from_chat(user_id, messages)
            
            # Check again after processing
            if self.ui_active:
                print("⏹️ UI became active during processing - stopping")
                return
            
            # Store memories
            for memory in memories:
                smart_memory._store_memory(memory)
            
            # Update user profile
            smart_memory._update_user_profile(user_id, messages)
            
            print(f"✅ Processed chat {chat_id} with lazy loading - extracted {len(memories)} memories")
            
        except Exception as e:
            print(f"❌ Error in lazy chat processing: {e}")
    
    def get_status(self) -> Dict[str, Any]:
        """Get current status of lazy background learning"""
        with self.processing_lock:
            return {
                "pending_chats": len(self.pending_chats),
                "is_processing": self.is_processing,
                "ui_active": self.ui_active,
                "lazy_model_initialized": self.lazy_model is not None,
                "model_weights_loaded": False  # MLX lazy loading makes this hard to detect
            }
    
    def clear_pending(self):
        """Clear all pending chats"""
        with self.processing_lock:
            cleared = len(self.pending_chats)
            self.pending_chats.clear()
            print(f"🗑️ Cleared {cleared} pending chats")
    
    def force_process_now(self):
        """Force process all pending chats immediately (for testing)"""
        print("🚨 Force processing with lazy loading")
        self.ui_active = False
        self.start_background_processing()


# Global instance
_lazy_learning = None

def get_lazy_learning() -> LazyMLXBackgroundLearning:
    """Get the global lazy learning instance"""
    global _lazy_learning
    if _lazy_learning is None:
        _lazy_learning = LazyMLXBackgroundLearning()
    return _lazy_learning

def queue_chat_for_learning(user_id: str, chat_id: str, messages: List[Dict]):
    """Queue a chat for lazy background learning"""
    get_lazy_learning().queue_chat_for_learning(user_id, chat_id, messages)

def on_ui_opened():
    """Call when UI opens"""
    get_lazy_learning().on_ui_opened()

def on_ui_closed():
    """Call when UI closes"""
    get_lazy_learning().on_ui_closed()

def get_learning_status() -> Dict[str, Any]:
    """Get learning status"""
    return get_lazy_learning().get_status()