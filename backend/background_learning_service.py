"""
Background Learning Service
===========================

Monitors chat sessions and triggers background learning when UI is inactive.
Integrates with the chat manager to queue conversations for processing.
"""

import asyncio
import time
from typing import Dict, List, Any, Optional
from smart_memory_system import get_smart_memory
from chat_manager import chat_manager
from langchain_core.messages import HumanMessage, AIMessage


class BackgroundLearningService:
    """
    Service that manages background learning from chat sessions
    """
    
    def __init__(self):
        self.smart_memory = get_smart_memory()
        self.ui_status_tracker = UIStatusTracker()
        self.processed_sessions = set()  # Track which sessions we've already processed
        self.monitoring_started = False
        
        # Start monitoring when in async context
        self._schedule_monitoring()
    
    def _schedule_monitoring(self):
        """Schedule monitoring task if in async context"""
        try:
            if not self.monitoring_started:
                # Check if we're in an async context before creating task
                try:
                    asyncio.get_running_loop()
                    asyncio.create_task(self._start_monitoring())
                    self.monitoring_started = True
                except RuntimeError:
                    # No event loop running - skip scheduling
                    print("📚 Background learning monitoring will start when event loop is available")
                    pass
        except RuntimeError:
            # No event loop - monitoring will start when FastAPI app starts
            pass
    
    async def _start_monitoring(self):
        """Disabled automatic monitoring - using event-driven approach instead"""
        print("📚 Background learning monitoring disabled - using event-driven triggers")
        # No continuous monitoring - everything is triggered by events:
        # - New messages trigger learning via notify_new_message()
        # - UI status changes trigger learning via smart_memory events
    
    async def _queue_recent_chats(self):
        """Queue recent unprocessed chat sessions for learning"""
        try:
            # Get all chat sessions for the default user
            user_sessions = chat_manager.get_user_sessions("pradhumn")
            
            for session in user_sessions:
                session_id = session.get("id")
                user_id = session.get("user_id", "pradhumn")
                
                # Skip if already processed
                if session_id in self.processed_sessions:
                    continue
                
                # Get messages for this session
                messages = chat_manager.get_chat_history(session_id)
                
                # Convert messages to the format expected by smart memory
                formatted_messages = []
                for msg in messages:
                    if hasattr(msg, 'content'):
                        if isinstance(msg, HumanMessage):
                            formatted_messages.append({
                                "role": "user",
                                "content": msg.content
                            })
                        elif isinstance(msg, AIMessage):
                            formatted_messages.append({
                                "role": "assistant", 
                                "content": msg.content
                            })
                
                # Only process if we have enough messages for learning
                if len(formatted_messages) >= 2:  # At least one exchange
                    # Queue for background learning
                    self.smart_memory.queue_chat_for_learning(
                        user_id=user_id,
                        chat_id=session_id,
                        messages=formatted_messages
                    )
                    
                    # Mark as queued
                    self.processed_sessions.add(session_id)
                    print(f"📚 Queued session {session_id} for background learning")
        
        except Exception as e:
            print(f"❌ Error queuing chats for learning: {e}")
    
    async def _queue_specific_session(self, session_id: str, user_id: str):
        """Queue a specific session for learning"""
        try:
            # Get messages for this session
            messages = chat_manager.get_chat_history(session_id)
            
            # Convert messages to the format expected by smart memory
            formatted_messages = []
            for msg in messages:
                if hasattr(msg, 'content'):
                    if isinstance(msg, HumanMessage):
                        formatted_messages.append({
                            "role": "user",
                            "content": msg.content
                        })
                    elif isinstance(msg, AIMessage):
                        formatted_messages.append({
                            "role": "assistant", 
                            "content": msg.content
                        })
            
            # Only process if we have enough messages for learning
            if len(formatted_messages) >= 2:  # At least one exchange
                # Queue for background learning
                self.smart_memory.queue_chat_for_learning(
                    user_id=user_id,
                    chat_id=session_id,
                    messages=formatted_messages
                )
                
                # Mark as queued
                self.processed_sessions.add(session_id)
                print(f"📚 Queued specific session {session_id} for background learning")
                
        except Exception as e:
            print(f"❌ Error queuing specific session for learning: {e}")
    
    def notify_new_message(self, session_id: str, user_id: str, message: Dict):
        """Called when a new message is added to a session"""
        # Remove from processed set so it gets re-queued for learning
        self.processed_sessions.discard(session_id)
        print(f"🔄 Session {session_id} marked for re-learning due to new message")
        
        # Trigger learning immediately if UI is inactive
        if not self.ui_status_tracker.is_ui_active():
            print(f"📚 Triggering immediate learning for session {session_id}")
            # Queue this specific session for learning
            asyncio.create_task(self._queue_specific_session(session_id, user_id))


class UIStatusTracker:
    """
    Tracks whether the UI is currently active based on recent API calls
    """
    
    def __init__(self):
        self.last_ui_activity = time.time()
        self.ui_timeout = 300  # 5 minutes of inactivity = UI is closed
    
    def mark_ui_activity(self):
        """Call this when UI-related API calls are made"""
        self.last_ui_activity = time.time()
    
    def is_ui_active(self) -> bool:
        """Check if UI is currently active"""
        time_since_activity = time.time() - self.last_ui_activity
        return time_since_activity < self.ui_timeout
    
    def force_ui_status(self, is_active: bool):
        """Manually set UI status (for explicit open/close events)"""
        if is_active:
            self.last_ui_activity = time.time()
        else:
            self.last_ui_activity = 0  # Force inactive


# Global instances
background_learning_service = None
ui_status_tracker = None

def initialize_background_learning():
    """Initialize background learning service"""
    global background_learning_service, ui_status_tracker
    background_learning_service = BackgroundLearningService()
    ui_status_tracker = background_learning_service.ui_status_tracker
    print("📚 Background Learning Service initialized")
    return background_learning_service

def get_background_learning_service() -> BackgroundLearningService:
    """Get the global background learning service"""
    global background_learning_service
    if background_learning_service is None:
        background_learning_service = initialize_background_learning()
    return background_learning_service

def get_ui_status_tracker() -> UIStatusTracker:
    """Get the global UI status tracker"""
    global ui_status_tracker
    if ui_status_tracker is None:
        initialize_background_learning()
    return ui_status_tracker