"""
Deferred Background Learning System
==================================

Safe background learning that only processes when the app is truly idle
for extended periods, avoiding GPU conflicts entirely.
"""

import threading
import time
import json
from typing import List, Dict, Any
from datetime import datetime


class DeferredBackgroundLearning:
    """Safe background learning that processes only during extended idle periods"""
    
    def __init__(self):
        self.pending_chats = []
        self.idle_timer = None
        self.processing_lock = threading.Lock()
        self.last_ui_activity = time.time()
        self.idle_threshold = 60.0  # 60 seconds of complete inactivity
        self.is_processing = False
        
    def queue_chat_for_learning(self, user_id: str, chat_id: str, messages: List[Dict]):
        """Queue a chat for deferred learning"""
        with self.processing_lock:
            chat_data = {
                "user_id": user_id,
                "chat_id": chat_id,
                "messages": messages,
                "queued_at": datetime.now().isoformat()
            }
            self.pending_chats.append(chat_data)
            print(f"📚 Queued chat {chat_id} for deferred learning ({len(self.pending_chats)} pending)")
    
    def on_ui_activity(self):
        """Call this on ANY UI activity (opens, closes, interactions)"""
        with self.processing_lock:
            self.last_ui_activity = time.time()
            
            # Cancel any pending processing
            if self.idle_timer:
                self.idle_timer.cancel()
                self.idle_timer = None
                print("⏹️ Cancelled deferred learning due to UI activity")
            
            # If currently processing, we can't stop it mid-stream
            # but we won't start new processing
            if self.is_processing:
                print("⚠️ Background learning in progress - will finish current batch")
    
    def on_app_idle(self):
        """Call this when app becomes idle (no UI activity)"""
        with self.processing_lock:
            # Cancel any existing timer
            if self.idle_timer:
                self.idle_timer.cancel()
            
            # Start new timer for deferred processing
            self.idle_timer = threading.Timer(self.idle_threshold, self.process_when_safe)
            self.idle_timer.start()
            print(f"⏰ Started idle timer - will process in {self.idle_threshold}s if no activity")
    
    def process_when_safe(self):
        """Process all pending chats when it's safe (no GPU conflicts)"""
        with self.processing_lock:
            if self.is_processing:
                print("⚠️ Already processing - skipping")
                return
                
            if not self.pending_chats:
                print("📚 No pending chats to process")
                return
            
            # Double-check we're still idle
            time_since_activity = time.time() - self.last_ui_activity
            if time_since_activity < self.idle_threshold:
                print(f"⚠️ UI activity detected recently ({time_since_activity:.1f}s ago) - postponing")
                # Reschedule for later
                self.on_app_idle()
                return
            
            self.is_processing = True
            
        # Process outside the lock to avoid blocking UI activity detection
        self._process_all_pending_chats()
        
        with self.processing_lock:
            self.is_processing = False
            print("✅ Deferred learning completed")
    
    def _process_all_pending_chats(self):
        """Process all pending chats in one batch"""
        try:
            from smart_memory_system import get_smart_memory
            smart_memory = get_smart_memory()
            
            chats_to_process = self.pending_chats.copy()
            processed_count = 0
            
            print(f"🧠 Starting deferred processing of {len(chats_to_process)} chats")
            
            for chat_data in chats_to_process:
                try:
                    # Quick check if UI became active
                    time_since_activity = time.time() - self.last_ui_activity
                    if time_since_activity < 30.0:  # If UI activity in last 30s, stop
                        print("⏹️ UI activity detected during processing - stopping")
                        break
                    
                    # Process this chat
                    user_id = chat_data["user_id"]
                    chat_id = chat_data["chat_id"]
                    messages = chat_data["messages"]
                    
                    print(f"🧠 Processing deferred chat {chat_id}")
                    
                    # Extract memories using the existing system
                    memories = smart_memory._extract_memories_from_chat(user_id, messages)
                    
                    # Store memories
                    for memory in memories:
                        smart_memory._store_memory(memory)
                    
                    # Update user profile
                    smart_memory._update_user_profile(user_id, messages)
                    
                    print(f"✅ Processed chat {chat_id} - extracted {len(memories)} memories")
                    processed_count += 1
                    
                    # Remove from pending list
                    with self.processing_lock:
                        if chat_data in self.pending_chats:
                            self.pending_chats.remove(chat_data)
                    
                    # Brief pause between chats
                    time.sleep(1.0)
                    
                except Exception as e:
                    print(f"❌ Error processing chat {chat_data.get('chat_id', 'unknown')}: {e}")
                    # Remove failed chat from pending list
                    with self.processing_lock:
                        if chat_data in self.pending_chats:
                            self.pending_chats.remove(chat_data)
            
            print(f"✅ Deferred learning completed: {processed_count}/{len(chats_to_process)} chats processed")
            
        except Exception as e:
            print(f"❌ Deferred learning failed: {e}")
    
    def get_pending_count(self) -> int:
        """Get number of pending chats"""
        with self.processing_lock:
            return len(self.pending_chats)
    
    def clear_pending(self):
        """Clear all pending chats (for debugging)"""
        with self.processing_lock:
            cleared = len(self.pending_chats)
            self.pending_chats.clear()
            print(f"🗑️ Cleared {cleared} pending chats")
    
    def force_process_now(self):
        """Force process now (for debugging) - use with caution!"""
        print("🚨 Force processing all pending chats NOW")
        self.process_when_safe()


# Global instance
_deferred_learning = None

def get_deferred_learning() -> DeferredBackgroundLearning:
    """Get the global deferred learning instance"""
    global _deferred_learning
    if _deferred_learning is None:
        _deferred_learning = DeferredBackgroundLearning()
    return _deferred_learning


def queue_chat_for_learning(user_id: str, chat_id: str, messages: List[Dict]):
    """Queue a chat for deferred learning"""
    get_deferred_learning().queue_chat_for_learning(user_id, chat_id, messages)


def on_ui_activity():
    """Call this on any UI activity"""
    get_deferred_learning().on_ui_activity()


def on_app_idle():
    """Call this when app becomes idle"""
    get_deferred_learning().on_app_idle()