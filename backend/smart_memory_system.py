"""
Smart Memory System for SuriAI
===============================

A clean, intelligent long-term memory system that:
1. Learns what to store from previous chats in the background
2. Only processes when UI is closed (ContentView and Dynamic Island not active)
3. Pre-fetches and prepares everything when UI is closed
4. Makes everything instant when user opens chat panels

Key Features:
- Background intelligent learning
- Zero latency during active chat
- Smart content extraction and storage
- Automatic memory optimization
- Simple, clean API
"""

import asyncio
import sqlite3
import json
import time
import queue
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, asdict
from pathlib import Path
import threading


@dataclass
class MemoryEntry:
    """Enhanced memory entry with comprehensive information"""
    id: str
    user_id: str
    content: str
    memory_type: str  # "fact", "preference", "pattern", "skill", "goal", "event", "emotional", "temporal", "context", "meta", "social", "procedural"
    importance: float  # 0.0 to 1.0
    created_at: str
    last_accessed: str
    access_count: int
    keywords: List[str]
    context: str  # Original conversation context
    confidence: float = 0.8  # Confidence in memory accuracy
    category: str = ""  # Sub-category within memory type
    temporal_pattern: str = ""  # Time-based pattern if applicable
    related_memories: List[str] = None  # IDs of related memories
    metadata: Dict[str, Any] = None  # Additional structured data

    def __post_init__(self):
        if self.related_memories is None:
            self.related_memories = []
        if self.metadata is None:
            self.metadata = {}


@dataclass
class UserProfile:
    """User's learned profile"""
    user_id: str
    communication_style: str
    interests: List[str]
    expertise_areas: List[str]
    personality_traits: List[str]
    preferences: Dict[str, str]
    updated_at: str


class SmartMemorySystem:
    """
    Intelligent memory system that learns in the background
    """
    
    def __init__(self, db_path: str = "smart_memory.db"):
        self.db_path = db_path
        self.is_ui_active = True  # Default to active (UI is running if we're processing chats)
        self.background_processor = None
        # Chats are stored in database table 'pending_chats' and processed via background worker
        self.ready_memories = {}  # Pre-fetched memories per user
        self.ready_profiles = {}  # Pre-fetched profiles per user
        self.needs_prefetch = True  # Flag to trigger prefetch only when needed
        self.stop_background_processing = False  # Flag to stop background processing when UI active
        
        # Vector storage is now handled by memory coordinator
        # Legacy attributes kept for compatibility
        self.vector_processing_active = False
        
        # Initialize database
        self._init_database()
        
        # Start background processor for memory learning
        self._start_background_processor()
    
    def _get_db_connection(self, timeout=30.0):
        """Get database connection with proper configuration"""
        conn = sqlite3.connect(self.db_path, timeout=timeout)
        conn.execute("PRAGMA journal_mode=WAL")  # Enable WAL mode for better concurrency
        conn.execute("PRAGMA synchronous=NORMAL")  # Balance between safety and speed
        conn.execute("PRAGMA cache_size=10000")  # Increase cache size
        conn.execute("PRAGMA temp_store=MEMORY")  # Store temp tables in memory
        return conn
    
    def _execute_with_retry(self, query, params=None, fetch=False, max_retries=3):
        """Execute database query with retry logic"""
        import time
        
        for attempt in range(max_retries):
            try:
                with self._get_db_connection() as conn:
                    cursor = conn.cursor()
                    if params:
                        cursor.execute(query, params)
                    else:
                        cursor.execute(query)
                    
                    if fetch:
                        result = cursor.fetchall()
                        return result
                    else:
                        conn.commit()
                        return cursor.rowcount
                        
            except sqlite3.OperationalError as e:
                if "database is locked" in str(e) and attempt < max_retries - 1:
                    wait_time = (attempt + 1) * 0.1  # Exponential backoff
                    print(f"⚠️ Database locked, retrying in {wait_time}s (attempt {attempt + 1}/{max_retries})")
                    time.sleep(wait_time)
                    continue
                else:
                    print(f"❌ Database error after {attempt + 1} attempts: {e}")
                    raise
            except Exception as e:
                print(f"❌ Unexpected database error: {e}")
                raise
    
    def _init_database(self):
        """Initialize clean database schema"""
        try:
            with self._get_db_connection() as conn:
                # Memory entries table
                conn.execute("""
                CREATE TABLE IF NOT EXISTS memories (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    content TEXT NOT NULL,
                    memory_type TEXT NOT NULL,
                    importance REAL NOT NULL,
                    created_at TEXT NOT NULL,
                    last_accessed TEXT NOT NULL,
                    access_count INTEGER DEFAULT 0,
                    keywords TEXT NOT NULL,
                    context TEXT NOT NULL
                )
            """)
            
            # User profiles table
            conn.execute("""
                CREATE TABLE IF NOT EXISTS user_profiles (
                    user_id TEXT PRIMARY KEY,
                    communication_style TEXT,
                    interests TEXT,
                    expertise_areas TEXT,
                    personality_traits TEXT,
                    preferences TEXT,
                    updated_at TEXT NOT NULL
                )
            """)
            
            # Chat sessions for background processing
            conn.execute("""
                CREATE TABLE IF NOT EXISTS pending_chats (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    chat_id TEXT NOT NULL,
                    messages TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    processed BOOLEAN DEFAULT FALSE
                )
            """)
            
            # Create indexes for performance
            conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_user ON memories(user_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(memory_type)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_memories_importance ON memories(importance)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_pending_processed ON pending_chats(processed)")
            
            conn.commit()
        except Exception as e:
            print(f"❌ Database initialization failed: {e}")
    
    def _start_background_processor(self):
        """Start the event-driven background processing thread"""
        import queue
        self.processing_queue = queue.Queue()
        
        def background_worker():
            while True:
                try:
                    # Wait for a processing event (blocking until event occurs)
                    event = self.processing_queue.get(timeout=None)
                    
                    # Only process when UI is inactive
                    if not self.is_ui_active:
                        print(f"🧠 Processing event: {event}")
                        
                        if event == "process_chats":
                            print("🔄 Starting background learning process...")
                            self._process_pending_chats()
                        elif event == "prefetch_data":
                            self._prefetch_user_data()
                            self.needs_prefetch = False
                        elif event == "cleanup":
                            self._cleanup_old_memories()
                    else:
                        print(f"🎯 Skipping background processing - UI is active")
                    
                    # Mark task as done
                    self.processing_queue.task_done()
                    
                except Exception as e:
                    print(f"🧠 Background processor error: {e}")
        
        self.background_processor = threading.Thread(target=background_worker, daemon=True)
        self.background_processor.start()
        print("🧠 Smart memory background processor started (event-driven)")
    
    # === PUBLIC API ===
    
    def set_ui_status(self, is_active: bool):
        """Call this when UI opens/closes"""
        old_status = self.is_ui_active
        self.is_ui_active = is_active
        
        print(f"🔍 SmartMemorySystem UI status changed: {old_status} -> {is_active}")
        
        if is_active:
            print("🎯 UI opened - memory system in fast mode")
            # Stop any ongoing background processing to avoid MLX conflicts
            self.stop_background_processing = True
        else:
            print("🧠 UI closed - background learning enabled")
            # Allow background processing when UI becomes inactive
            self.stop_background_processing = False
            # Trigger processing when UI becomes inactive
            if old_status != is_active:  # Only if status actually changed
                print("🚀 Triggering data prefetch for background mode")
                self.processing_queue.put("prefetch_data")
                print("🔄 Triggering processing of pending chats")
                self.processing_queue.put("process_chats")
    
    def queue_chat_for_learning(self, user_id: str, chat_id: str, messages: List[Dict]):
        """Queue a chat session for background learning"""
        chat_data = {
            "id": f"{user_id}_{chat_id}_{int(time.time())}",
            "user_id": user_id,
            "chat_id": chat_id,
            "messages": json.dumps(messages),
            "created_at": datetime.now().isoformat(),
            "processed": False
        }
        
        try:
            self._execute_with_retry("""
                INSERT OR REPLACE INTO pending_chats 
                (id, user_id, chat_id, messages, created_at, processed)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                chat_data["id"], chat_data["user_id"], chat_data["chat_id"],
                chat_data["messages"], chat_data["created_at"], chat_data["processed"]
            ))
            
            # Trigger chat processing when new chat is queued (only if UI is inactive)
            print(f"🔍 UI Status Check: self.is_ui_active = {self.is_ui_active}")
            if not self.is_ui_active:
                print("📝 New chat queued - triggering processing")
                self.processing_queue.put("process_chats")
            else:
                print("📝 Chat queued but UI is active - will process when UI becomes inactive")
                
        except Exception as e:
            print(f"❌ Failed to queue chat for learning: {e}")
        
        print(f"📝 Queued chat {chat_id} for background learning")
    
    def process_pending_chats_now(self):
        """Force process pending chats immediately (for testing)"""
        try:
            self._process_pending_chats()
            print("✅ Forced processing of pending chats completed")
        except Exception as e:
            print(f"❌ Error processing pending chats: {e}")
    
    def get_user_memories(self, user_id: str, limit: int = 20) -> List[MemoryEntry]:
        """Get pre-fetched memories for instant access"""
        if user_id in self.ready_memories:
            memories = self.ready_memories[user_id][:limit]
            print(f"⚡ Instant access to {len(memories)} memories for {user_id}")
            return memories
        
        # Fallback to direct database access (should be rare)
        return self._fetch_memories_from_db(user_id, limit)
    
    def get_chat_context_from_langgraph(self, user_id: str, chat_id: str, limit: int = 10) -> str:
        """Get recent chat context from LangGraph's memory checkpoint system"""
        try:
            # Import here to avoid circular imports
            from chat_manager import chat_manager
            
            # Get chat history from LangGraph checkpoint
            chat_history = chat_manager.get_chat_history(chat_id, limit=limit)
            
            if not chat_history:
                print(f"📝 No chat history found for {chat_id}")
                return ""
            
            # Build context from LangGraph messages
            context_parts = []
            for msg in chat_history[-limit:]:  # Get recent messages
                if hasattr(msg, 'content'):
                    if "Human" in str(type(msg)):
                        context_parts.append(f"User: {msg.content}")
                    elif "AI" in str(type(msg)):
                        context_parts.append(f"Assistant: {msg.content}")
            
            context = "\n".join(context_parts)
            print(f"🧠 Built LangGraph chat context for {chat_id}: {len(context_parts)} messages")
            return context
            
        except Exception as e:
            print(f"❌ Error getting LangGraph chat context: {e}")
            return ""
    
    def get_short_term_memory_summary(self, user_id: str, chat_id: str) -> str:
        """Get a summary of the short-term memory for this chat session using LLM analysis"""
        try:
            # Get recent context from LangGraph
            chat_context = self.get_chat_context_from_langgraph(user_id, chat_id, limit=20)
            
            if not chat_context:
                return ""
            
            # Use LLM to summarize the chat context
            prompt = f"""Analyze this conversation and provide a concise summary of the key points, topics discussed, and any important context that should be remembered for this chat session.

                        Chat History:
                        {chat_context}

                        Provide a brief summary (2-3 sentences) that captures:
                        1. Main topics discussed
                        2. Key information shared
                        3. Current context/state of the conversation

                        Summary:"""

            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                summary = response.strip()
                print(f"🧠 Generated STM summary for chat {chat_id}: {len(summary)} chars")
                return summary
            else:
                # Fallback: return recent context
                return chat_context[-500:] if len(chat_context) > 500 else chat_context
                
        except Exception as e:
            print(f"❌ Error generating STM summary: {e}")
            return ""
    
    def get_user_profile(self, user_id: str) -> Optional[UserProfile]:
        """Get pre-fetched user profile for instant access"""
        if user_id in self.ready_profiles:
            print(f"⚡ Instant access to profile for {user_id}")
            return self.ready_profiles[user_id]
        
        # Fallback to direct database access
        return self._fetch_profile_from_db(user_id)
    
    def search_memories(self, user_id: str, query: str, limit: int = 10) -> List[MemoryEntry]:
        """Search memories by keyword/content"""
        memories = self.get_user_memories(user_id, limit=100)  # Get more for searching
        
        # Simple keyword matching (can be enhanced with semantic search)
        query_lower = query.lower()
        relevant_memories = []
        
        for memory in memories:
            if (query_lower in memory.content.lower() or 
                any(keyword.lower() in query_lower for keyword in memory.keywords)):
                relevant_memories.append(memory)
        
        # Sort by importance and access count
        relevant_memories.sort(key=lambda m: (m.importance, m.access_count), reverse=True)
        return relevant_memories[:limit]
    
    def get_memory_stats(self, user_id: str) -> Dict[str, Any]:
        """Get comprehensive memory statistics for user"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Total memories
            cursor.execute("SELECT COUNT(*) FROM memories WHERE user_id = ?", (user_id,))
            total_memories = cursor.fetchone()[0]
            
            # Get all memory content for token and size calculation
            cursor.execute("""
                SELECT content, memory_type, created_at 
                FROM memories WHERE user_id = ?
            """, (user_id,))
            all_memories = cursor.fetchall()
            
            # Calculate tokens and size
            total_tokens = 0
            total_chars = 0
            type_breakdown = {}
            latest_timestamp = None
            
            for content, memory_type, created_at in all_memories:
                # Estimate tokens (roughly 4 characters per token)
                content_tokens = max(1, len(content) // 4)
                total_tokens += content_tokens
                total_chars += len(content)
                
                # Track latest timestamp
                if latest_timestamp is None or created_at > latest_timestamp:
                    latest_timestamp = created_at
                
                # Build type breakdown
                if memory_type not in type_breakdown:
                    type_breakdown[memory_type] = {"count": 0, "tokens": 0}
                type_breakdown[memory_type]["count"] += 1
                type_breakdown[memory_type]["tokens"] += content_tokens
            
            # Calculate size in bytes (rough estimate: 1 char ≈ 1 byte)
            total_size_bytes = total_chars
            
            # Average importance
            cursor.execute("""
                SELECT AVG(importance) 
                FROM memories WHERE user_id = ?
            """, (user_id,))
            avg_importance = cursor.fetchone()[0] or 0.0
            
            # Get latest memory timestamp for last updated
            cursor.execute("""
                SELECT MAX(created_at) 
                FROM memories WHERE user_id = ?
            """, (user_id,))
            last_updated = cursor.fetchone()[0]
            
            # Log memory types found for debugging (can be removed in production)
            if type_breakdown:
                print(f"📊 Found {len(type_breakdown)} memory types for user {user_id}: {list(type_breakdown.keys())}")
            # Note: Removed warning for empty memory types as this is expected for new users
            
            # Get enhanced statistics including vector database info
            enhanced_stats = self._get_enhanced_memory_stats(total_memories, total_tokens, total_size_bytes, type_breakdown)
            
            return {
                "user_id": user_id,
                "total_memories": total_memories,
                "total_tokens": total_tokens,
                "total_size_bytes": total_size_bytes,
                "avg_importance": round(avg_importance, 2),
                "memory_types_count": len(type_breakdown),
                "type_breakdown": type_breakdown,
                "timestamp": last_updated or datetime.now().isoformat(),
                "ready_memories_count": len(self.ready_memories.get(user_id, [])),
                "profile_ready": user_id in self.ready_profiles,
                # Enhanced combined database statistics
                "combined_size_mb": enhanced_stats["combined_size_mb"],
                "combined_size_bytes": enhanced_stats["combined_size_bytes"],
                "sql_database": enhanced_stats["sql_database"],
                "vector_database": enhanced_stats["vector_database"]
            }
    
    def _get_enhanced_memory_stats(self, sql_memories: int, sql_tokens: int, sql_size_bytes: int, type_breakdown: dict) -> Dict[str, Any]:
        """Get enhanced statistics including vector database information"""
        try:
            # Import here to avoid circular imports
            from memory_optimizer import get_memory_optimizer
            
            # Get vector database stats from memory optimizer
            optimizer = get_memory_optimizer()
            vector_stats = optimizer._get_vector_db_stats()
            
            # Calculate combined statistics
            combined_size_bytes = sql_size_bytes + vector_stats["vector_size_bytes"]
            combined_size_mb = combined_size_bytes / (1024 * 1024)
            
            return {
                "combined_size_mb": round(combined_size_mb, 2),
                "combined_size_bytes": combined_size_bytes,
                "sql_database": {
                    "size_mb": round(sql_size_bytes / (1024 * 1024), 2),
                    "size_bytes": sql_size_bytes,
                    "memory_count": sql_memories
                },
                "vector_database": vector_stats
            }
            
        except Exception as e:
            print(f"⚠️ Could not get enhanced memory stats: {e}")
            # Fallback to SQL-only stats
            return {
                "combined_size_mb": round(sql_size_bytes / (1024 * 1024), 2),
                "combined_size_bytes": sql_size_bytes,
                "sql_database": {
                    "size_mb": round(sql_size_bytes / (1024 * 1024), 2),
                    "size_bytes": sql_size_bytes,
                    "memory_count": sql_memories
                },
                "vector_database": {
                    "vector_size_mb": 0,
                    "vector_size_bytes": 0,
                    "embedding_count": 0,
                    "collection_count": 0,
                    "chroma_db_size_mb": 0,
                    "available": False
                }
            }
    
    def store_memory(self, user_id: str, content: str = None, memory_type: str = "working", 
                    importance: float = 0.5, keywords: List[str] = None, context: str = "") -> str:
        """Store a new memory manually (public interface)"""
        import uuid
        from datetime import datetime
        
        # Defensive check for required parameters
        if not user_id:
            raise ValueError("user_id is required")
        if not content:
            raise ValueError("content is required")
            
        if keywords is None:
            keywords = []
        
        # Create memory entry
        memory = MemoryEntry(
            id=str(uuid.uuid4()),
            user_id=user_id,
            content=content,
            memory_type=memory_type,
            importance=importance,
            created_at=datetime.now().isoformat(),
            last_accessed=datetime.now().isoformat(),
            access_count=0,
            keywords=keywords,
            context=context
        )
        
        # Store it
        self._store_memory(memory)
        
        # Clear cached data for this user so it gets refreshed
        if user_id in self.ready_memories:
            del self.ready_memories[user_id]
        
        return memory.id
    
    # === BACKGROUND PROCESSING ===
    
    def _process_pending_chats(self):
        """Process pending chats to extract and store memories"""
        currently_processing = None
        try:
            # Check if UI is active before starting any processing
            if self.stop_background_processing:
                print("⏹️ Skipping background processing - UI is active")
                return
            
            # Get pending chats with retry mechanism (process all pending chats)
            pending_chats = self._execute_with_retry("""
                SELECT id, user_id, chat_id, messages 
                FROM pending_chats 
                WHERE processed = 0 
                ORDER BY created_at ASC
            """, fetch=True)
            
            if not pending_chats:
                print("No Pending Chats to Process")
                return
            
            print(f"🔄 Processing {len(pending_chats)} pending chats")
            
            for chat_row in pending_chats:
                # Check if we should stop processing (UI became active)
                if self.stop_background_processing:
                    print("⏹️ Stopping background processing immediately - UI became active")
                    break
                    
                chat_id, user_id, orig_chat_id, messages_json = chat_row
                currently_processing = chat_id  # Track what we're processing
                
                try:
                    print(f"🧠 Processing chat {orig_chat_id} for user {user_id}")
                    messages = json.loads(messages_json)
                    
                    # Mark as being processed to avoid duplicate processing
                    self._execute_with_retry("""
                        UPDATE pending_chats 
                        SET processed = -1 
                        WHERE id = ?
                    """, (chat_id,))
                    
                    # Check again before expensive MLX operation
                    if self.stop_background_processing:
                        print("⏹️ UI opened during processing - re-queuing chat for later")
                        # Reset to unprocessed so it can be retried later
                        self._execute_with_retry("""
                            UPDATE pending_chats 
                            SET processed = 0 
                            WHERE id = ?
                        """, (chat_id,))
                        currently_processing = None
                        break
                    
                    # Extract and store memories from this chat
                    print(f"🧠 Starting memory extraction from chat {orig_chat_id}")
                    memories = self._extract_memories_from_chat(user_id, messages)
                    
                    # Check if UI opened during memory extraction
                    if self.stop_background_processing:
                        print("⏹️ UI opened during memory extraction - re-queuing chat for later")
                        # Reset to unprocessed so it can be retried later
                        self._execute_with_retry("""
                            UPDATE pending_chats 
                            SET processed = 0 
                            WHERE id = ?
                        """, (chat_id,))
                        currently_processing = None
                        break
                    
                    # Store extracted memories
                    for memory in memories:
                        self._store_memory(memory)
                    
                    # Update user profile based on chat
                    self._update_user_profile(user_id, messages)
                    
                    print(f"✅ Extracted and stored {len(memories)} memories from chat {orig_chat_id}")
                    
                    # Mark as completed
                    self._execute_with_retry("""
                        UPDATE pending_chats 
                        SET processed = 1 
                        WHERE id = ?
                    """, (chat_id,))
                    
                    currently_processing = None
                    print(f"✅ Completed processing chat {orig_chat_id}")
                    
                except Exception as e:
                    print(f"❌ Error processing chat {orig_chat_id}: {e}")
                    # Reset to unprocessed so it can be retried later
                    self._execute_with_retry("""
                        UPDATE pending_chats 
                        SET processed = 0 
                        WHERE id = ?
                    """, (chat_id,))
                    currently_processing = None
                    
        except Exception as e:
            print(f"❌ Error in _process_pending_chats: {e}")
            # If we were processing something and failed, reset it
            if currently_processing:
                try:
                    self._execute_with_retry("""
                        UPDATE pending_chats 
                        SET processed = 0 
                        WHERE id = ?
                    """, (currently_processing,))
                    print(f"♻️ Reset failed chat {currently_processing} for retry")
                except:
                    pass
    
    def process_single_batch(self) -> int:
        """Process a single batch of pending chats. Returns number of chats processed."""
        try:
            from simple_background_control import should_stop_processing
            
            # Get one pending chat
            pending_chats = self._execute_with_retry("""
                SELECT id, user_id, chat_id, messages 
                FROM pending_chats 
                WHERE processed = 0 
                ORDER BY created_at ASC
                LIMIT 1
            """, fetch=True)
            
            if not pending_chats:
                return 0
            
            if should_stop_processing():
                print("⏹️ Stopping - UI is active")
                return 0
            
            chat_row = pending_chats[0]
            chat_id, user_id, orig_chat_id, messages_json = chat_row
            
            try:
                print(f"🧠 Processing chat {orig_chat_id}")
                messages = json.loads(messages_json)
                
                # Check again before expensive operation
                if should_stop_processing():
                    print("⏹️ Stopping before memory extraction")
                    return 0
                
                # Extract and store memories
                memories = self._extract_memories_from_chat(user_id, messages)
                
                # Check one more time before storing
                if should_stop_processing():
                    print("⏹️ Stopping before storing memories")
                    return 0
                
                # Store extracted memories
                for memory in memories:
                    self._store_memory(memory)
                
                # Update user profile
                self._update_user_profile(user_id, messages)
                
                print(f"✅ Extracted {len(memories)} memories from chat {orig_chat_id}")
                
                # Mark as processed
                self._execute_with_retry("""
                    UPDATE pending_chats 
                    SET processed = 1 
                    WHERE id = ?
                """, (chat_id,))
                
                return 1
                
            except Exception as e:
                print(f"❌ Error processing chat {orig_chat_id}: {e}")
                # Mark as processed to avoid infinite retry
                self._execute_with_retry("""
                    UPDATE pending_chats 
                    SET processed = 1 
                    WHERE id = ?
                """, (chat_id,))
                return 0
                
        except Exception as e:
            print(f"❌ Error in process_single_batch: {e}")
            return 0
    
    def _extract_memories_from_chat(self, user_id: str, messages: List[Dict]) -> List[MemoryEntry]:
        """Extract meaningful memories from chat messages using AI analysis"""
        memories = []
        conversation_text = ""
        
        # Build conversation context
        for msg in messages:
            if msg.get("role") in ["user", "human"]:
                conversation_text += f"User: {msg.get('content', '')}\n"
            elif msg.get("role") in ["assistant", "ai"]:
                conversation_text += f"AI: {msg.get('content', '')}\n"
        
        if not conversation_text.strip():
            return memories
        
        # Extract different types of memories (with stop checks before each LLM call)
        # Critical: Check UI status before each extraction to prevent GPU conflicts
        extraction_functions = [
            ("facts", self._extract_facts),
            ("preferences", self._extract_preferences),
            ("patterns", self._extract_patterns),
            ("skills", self._extract_skills),
            ("goals", self._extract_goals),
            ("events", self._extract_events),
            ("emotional_context", self._extract_emotional_context),
            ("temporal_patterns", self._extract_temporal_patterns),
            ("context_info", self._extract_context_info),
            ("meta_learning", self._extract_meta_learning),
            ("social_dynamics", self._extract_social_dynamics),
            ("procedures", self._extract_procedures)
        ]
        
        for extraction_name, extraction_func in extraction_functions:
            # Check UI status before each extraction
            if self.stop_background_processing:
                print(f"⏹️ Stopping memory extraction at {extraction_name} - UI became active")
                break
            
            try:
                extracted = extraction_func(user_id, conversation_text)
                if extracted:
                    memories.extend(extracted)
                    print(f"✅ Extracted {len(extracted)} {extraction_name}")
                
                # Check again after each extraction
                if self.stop_background_processing:
                    print(f"⏹️ Stopping after {extraction_name} extraction - UI became active")
                    break
                    
            except Exception as e:
                print(f"❌ Error in {extraction_name} extraction: {e}")
                # Continue with other extractions even if one fails
                continue
        
        return memories
    
    def _extract_facts(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract factual information about the user using LLM analysis"""
        memories = []
        
        try:
            # Use LLM to intelligently extract facts
            prompt = f"""Analyze this conversation and extract important factual information about the user.
                        Focus on concrete, verifiable facts about their life, work, identity, location, etc.

                        Conversation:
                        {conversation}

                        Extract facts and return them as a JSON list with this format:
                        [
                        {{
                            "fact": "specific fact about the user",
                            "category": "personal_info|professional|location|identity|education|skills|family|possessions",
                            "importance": 0.1-1.0,
                            "keywords": ["keyword1", "keyword2"]
                        }}
                        ]

                        IMPORTANT: Return only the JSON array, no other text. Do not repeat content. If no facts found, return []. Stop after the closing bracket ]."""

            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                facts_data = self._parse_json_response(response)
                
                for fact_item in facts_data:
                    if isinstance(fact_item, dict) and 'fact' in fact_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_fact_{int(time.time())}_{hash(fact_item['fact']) % 10000}",
                            user_id=user_id,
                            content=fact_item['fact'],
                            memory_type="fact",
                            importance=float(fact_item.get('importance', 0.8)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=fact_item.get('keywords', [fact_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
                        
        except Exception as e:
            print(f"❌ LLM fact extraction failed: {e}")
            # Fallback to simple pattern matching
            memories.extend(self._extract_facts_fallback(user_id, conversation))
        
        return memories
    
    def _extract_preferences(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract user preferences and opinions using LLM analysis"""
        memories = []
        
        try:
            # Use LLM to intelligently extract preferences
            prompt = f"""Analyze this conversation and extract the user's preferences, opinions, likes, dislikes, and wants.
                            Focus on things the user expresses positive or negative sentiment about.

                            Conversation:
                            {conversation}

                            Extract preferences and return them as a JSON list with this format:
                            [
                            {{
                                "preference": "what the user likes/dislikes/prefers",
                                "sentiment": "positive|negative|neutral",
                                "category": "technology|food|entertainment|work|lifestyle|hobbies|communication|other",
                                "importance": 0.1-1.0,
                                "keywords": ["keyword1", "keyword2"]
                            }}
                            ]

                            IMPORTANT: Return only the JSON array, no other text. Do not repeat content. If no preferences found, return []. Stop after the closing bracket ]."""

            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                prefs_data = self._parse_json_response(response)
                
                for pref_item in prefs_data:
                    if isinstance(pref_item, dict) and 'preference' in pref_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_pref_{int(time.time())}_{hash(pref_item['preference']) % 10000}",
                            user_id=user_id,
                            content=pref_item['preference'],
                            memory_type="preference",
                            importance=float(pref_item.get('importance', 0.7)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=pref_item.get('keywords', [pref_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
                        
        except Exception as e:
            print(f"❌ LLM preference extraction failed: {e}")
            # Fallback to simple pattern matching
            memories.extend(self._extract_preferences_fallback(user_id, conversation))
        
        return memories
    
    def _extract_patterns(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract behavioral patterns and communication style using LLM analysis"""
        memories = []
        
        try:
            # Use LLM to intelligently extract behavioral patterns
            prompt = f"""Analyze this conversation and identify behavioral patterns, communication style, and personality traits of the user.
                        Look for recurring behaviors, communication preferences, learning style, problem-solving approach, etc.

                        Conversation:
                        {conversation}

                        Extract patterns and return them as a JSON list with this format:
                        [
                        {{
                            "pattern": "description of the behavioral pattern or communication style",
                            "category": "communication_style|personality_trait|learning_style|interaction_pattern|problem_solving|other",
                            "importance": 0.1-1.0,
                            "keywords": ["keyword1", "keyword2"]
                        }}
                        ]

                        Return only the JSON, no other text. If no patterns found, return []."""

            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                patterns_data = self._parse_json_response(response)
                
                for pattern_item in patterns_data:
                    if isinstance(pattern_item, dict) and 'pattern' in pattern_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_pattern_{int(time.time())}_{hash(pattern_item['pattern']) % 10000}",
                            user_id=user_id,
                            content=pattern_item['pattern'],
                            memory_type="pattern",
                            importance=float(pattern_item.get('importance', 0.6)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=pattern_item.get('keywords', [pattern_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
                        
        except Exception as e:
            print(f"❌ LLM pattern extraction failed: {e}")
            # Fallback to simple analysis
            memories.extend(self._extract_patterns_fallback(user_id, conversation))
        
        return memories
    
    def _extract_skills(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract skills and expertise mentioned"""
        memories = []
        try:
            prompt = f"""Extract skills, expertise, and capabilities from this conversation.
            
            Conversation:
            {conversation}
            
            Extract skills as JSON array:
            [
                {{
                    "skill": "specific skill or expertise mentioned",
                    "proficiency": "beginner|intermediate|advanced|expert|unknown",
                    "category": "technical|creative|interpersonal|analytical|physical|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no skills found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                skills_data = self._parse_json_response(response)
                for skill_item in skills_data:
                    if isinstance(skill_item, dict) and 'skill' in skill_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_skill_{int(time.time())}_{hash(skill_item['skill']) % 10000}",
                            user_id=user_id,
                            content=skill_item['skill'],
                            memory_type="skill",
                            importance=float(skill_item.get('importance', 0.7)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=skill_item.get('keywords', [skill_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Skill extraction failed: {e}")
        return memories
    
    def _extract_goals(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract goals and objectives mentioned"""
        memories = []
        try:
            prompt = f"""Extract goals, objectives, and aspirations from this conversation.
            
            Conversation:
            {conversation}
            
            Extract goals as JSON array:
            [
                {{
                    "goal": "specific goal or objective mentioned",
                    "timeframe": "short_term|medium_term|long_term|ongoing|unknown",
                    "category": "personal|professional|learning|health|financial|creative|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no goals found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                goals_data = self._parse_json_response(response)
                for goal_item in goals_data:
                    if isinstance(goal_item, dict) and 'goal' in goal_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_goal_{int(time.time())}_{hash(goal_item['goal']) % 10000}",
                            user_id=user_id,
                            content=goal_item['goal'],
                            memory_type="goal",
                            importance=float(goal_item.get('importance', 0.8)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=goal_item.get('keywords', [goal_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Goal extraction failed: {e}")
        return memories
    
    def _extract_events(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract significant events mentioned"""
        memories = []
        try:
            prompt = f"""Extract significant events, experiences, and milestones from this conversation.
            
            Conversation:
            {conversation}
            
            Extract events as JSON array:
            [
                {{
                    "event": "description of significant event or experience",
                    "timeframe": "past|present|future|ongoing|unknown",
                    "category": "personal|work|social|educational|travel|milestone|achievement|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no events found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                events_data = self._parse_json_response(response)
                for event_item in events_data:
                    if isinstance(event_item, dict) and 'event' in event_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_event_{int(time.time())}_{hash(event_item['event']) % 10000}",
                            user_id=user_id,
                            content=event_item['event'],
                            memory_type="event",
                            importance=float(event_item.get('importance', 0.6)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=event_item.get('keywords', [event_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Event extraction failed: {e}")
        return memories
    
    def _extract_emotional_context(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract emotional states and reactions"""
        memories = []
        try:
            prompt = f"""Extract emotional states, reactions, and feelings from this conversation.
            
            Conversation:
            {conversation}
            
            Extract emotions as JSON array:
            [
                {{
                    "emotion": "description of emotional state or reaction",
                    "intensity": "low|medium|high|very_high",
                    "category": "joy|sadness|anger|fear|surprise|disgust|trust|anticipation|excitement|frustration|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no emotions found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                emotions_data = self._parse_json_response(response)
                for emotion_item in emotions_data:
                    if isinstance(emotion_item, dict) and 'emotion' in emotion_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_emotional_{int(time.time())}_{hash(emotion_item['emotion']) % 10000}",
                            user_id=user_id,
                            content=emotion_item['emotion'],
                            memory_type="emotional",
                            importance=float(emotion_item.get('importance', 0.5)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=emotion_item.get('keywords', [emotion_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Emotional extraction failed: {e}")
        return memories
    
    def _extract_temporal_patterns(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract time-based patterns and routines"""
        memories = []
        try:
            prompt = f"""Extract time-based patterns, routines, and schedules from this conversation.
            
            Conversation:
            {conversation}
            
            Extract temporal patterns as JSON array:
            [
                {{
                    "pattern": "description of time-based pattern or routine",
                    "frequency": "daily|weekly|monthly|yearly|irregular|one_time",
                    "category": "work_schedule|personal_routine|meeting_pattern|habit|deadline|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no temporal patterns found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                temporal_data = self._parse_json_response(response)
                for temporal_item in temporal_data:
                    if isinstance(temporal_item, dict) and 'pattern' in temporal_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_temporal_{int(time.time())}_{hash(temporal_item['pattern']) % 10000}",
                            user_id=user_id,
                            content=temporal_item['pattern'],
                            memory_type="temporal",
                            importance=float(temporal_item.get('importance', 0.6)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=temporal_item.get('keywords', [temporal_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Temporal extraction failed: {e}")
        return memories
    
    def _extract_context_info(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract contextual and environmental information"""
        memories = []
        try:
            prompt = f"""Extract contextual information, environment details, and situational context from this conversation.
            
            Conversation:
            {conversation}
            
            Extract context as JSON array:
            [
                {{
                    "context": "contextual or environmental information",
                    "scope": "immediate|session|personal|environmental|technical|organizational",
                    "category": "location|setup|environment|tools|team|process|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no context found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                context_data = self._parse_json_response(response)
                for context_item in context_data:
                    if isinstance(context_item, dict) and 'context' in context_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_context_{int(time.time())}_{hash(context_item['context']) % 10000}",
                            user_id=user_id,
                            content=context_item['context'],
                            memory_type="context",
                            importance=float(context_item.get('importance', 0.4)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=context_item.get('keywords', [context_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Context extraction failed: {e}")
        return memories
    
    def _extract_meta_learning(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract meta-information about how user learns and thinks"""
        memories = []
        try:
            prompt = f"""Extract meta-learning information about how this user learns, thinks, and processes information.
            
            Conversation:
            {conversation}
            
            Extract meta-learning as JSON array:
            [
                {{
                    "meta_info": "insight about how user learns or thinks",
                    "category": "learning_style|thinking_pattern|processing_preference|comprehension_method|other",
                    "application": "future_interactions|explanation_style|teaching_approach|communication|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no meta-learning found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                meta_data = self._parse_json_response(response)
                for meta_item in meta_data:
                    if isinstance(meta_item, dict) and 'meta_info' in meta_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_meta_{int(time.time())}_{hash(meta_item['meta_info']) % 10000}",
                            user_id=user_id,
                            content=meta_item['meta_info'],
                            memory_type="meta",
                            importance=float(meta_item.get('importance', 0.7)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=meta_item.get('keywords', [meta_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Meta-learning extraction failed: {e}")
        return memories
    
    def _extract_social_dynamics(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract social interactions and relationship information"""
        memories = []
        try:
            prompt = f"""Extract social dynamics, relationships, and interpersonal information from this conversation.
            
            Conversation:
            {conversation}
            
            Extract social dynamics as JSON array:
            [
                {{
                    "social_info": "information about relationships or social interactions",
                    "relationship_type": "colleague|friend|family|mentor|client|team_member|other",
                    "category": "collaboration_style|communication_preference|social_behavior|relationship|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no social dynamics found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                social_data = self._parse_json_response(response)
                for social_item in social_data:
                    if isinstance(social_item, dict) and 'social_info' in social_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_social_{int(time.time())}_{hash(social_item['social_info']) % 10000}",
                            user_id=user_id,
                            content=social_item['social_info'],
                            memory_type="social",
                            importance=float(social_item.get('importance', 0.6)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=social_item.get('keywords', [social_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Social dynamics extraction failed: {e}")
        return memories
    
    def _extract_procedures(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Extract procedures, workflows, and step-by-step processes"""
        memories = []
        try:
            prompt = f"""Extract procedures, workflows, and step-by-step processes from this conversation.
            
            Conversation:
            {conversation}
            
            Extract procedures as JSON array:
            [
                {{
                    "procedure": "description of procedure or workflow",
                    "complexity": "simple|moderate|complex|very_complex",
                    "category": "work_process|debug_workflow|decision_making|problem_solving|other",
                    "importance": 0.1-1.0,
                    "keywords": ["keyword1", "keyword2"]
                }}
            ]
            
            Return only JSON array. If no procedures found, return []."""
            
            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                procedure_data = self._parse_json_response(response)
                for procedure_item in procedure_data:
                    if isinstance(procedure_item, dict) and 'procedure' in procedure_item:
                        memory = MemoryEntry(
                            id=f"{user_id}_procedural_{int(time.time())}_{hash(procedure_item['procedure']) % 10000}",
                            user_id=user_id,
                            content=procedure_item['procedure'],
                            memory_type="procedural",
                            importance=float(procedure_item.get('importance', 0.7)),
                            created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(),
                            access_count=0,
                            keywords=procedure_item.get('keywords', [procedure_item.get('category', 'general')]),
                            context=conversation[:500]
                        )
                        memories.append(memory)
        except Exception as e:
            print(f"❌ Procedural extraction failed: {e}")
        return memories

    def _is_small_model(self) -> bool:
        """Detect if current model is small (1B parameters) and needs special handling"""
        try:
            from model_manager import ModelManager
            model_manager = ModelManager()
            current_model = model_manager.get_current_model()
            
            if current_model and isinstance(current_model, str):
                # Check for common 1B model patterns
                small_model_patterns = [
                    "1b", "1B", "1.1b", "1.1B", "1.3b", "1.3B",
                    "llama-3.2-1b", "qwen-1.5-1.8b", "phi-3-mini"
                ]
                
                for pattern in small_model_patterns:
                    if pattern in current_model.lower():
                        return True
                        
            return False
        except Exception:
            return False  # Assume larger model if we can't detect

    def _query_llm(self, prompt: str) -> str:
        """Query the LLM for memory extraction analysis with simple stop mechanism"""
        try:
            from simple_background_control import should_stop_processing
            
            # Early check - don't even start if UI is active
            if should_stop_processing():
                print("⏹️ Skipping LLM query - UI already active")
                return ""
            
            from llm_provider import get_llm_provider
            llm_provider = get_llm_provider()
            llm = llm_provider.get_llm()
            
            if not llm:
                import sys
                if 'unified_app' in sys.modules:
                    unified_app = sys.modules['unified_app']
                    model_ready = getattr(unified_app, 'model_ready', False)
                    if not model_ready:
                        return ""
                
                print("⚠️ Using fallback extraction - LLM not available")
                return ""
            
            # Check again before starting streaming
            if self.stop_background_processing:
                print("⏹️ Skipping LLM query - UI became active during setup")
                return ""
            
            # Detect small models and use more aggressive settings
            is_small = self._is_small_model()
            max_chunks = 100 if is_small else 300
            max_length = 2000 if is_small else 5000
            repetition_threshold = 1 if is_small else 2
            
            if is_small:
                print("🔍 Small model detected - using aggressive repetition detection")
            
            # Streaming with repetition detection
            response = ""
            chunk_count = 0
            last_50_chars = ""
            repetition_count = 0
            
            try:
                for chunk in llm.stream(prompt):
                    # Check in every chunk for immediate response to UI opening
                    if self.stop_background_processing:
                        print("⏹️ Stopping LLM query immediately - UI became active")
                        break
                    
                    if hasattr(chunk, 'content'):
                        content = chunk.content
                    else:
                        content = str(chunk)
                    
                    response += content
                    chunk_count += 1
                    
                    # Stop immediately if we see closing bracket (for JSON responses)
                    if ']' in content and len(response) > 50:
                        bracket_pos = response.rfind(']')
                        if bracket_pos > 0:
                            # Check if there's mostly junk after the bracket
                            after_bracket = response[bracket_pos + 1:].strip()
                            if len(after_bracket) > 100:  # Too much content after closing bracket
                                print("⚠️ Detected content after JSON closing bracket, truncating")
                                response = response[:bracket_pos + 1]
                                break
                    
                    # Check UI status every 10 chunks during streaming
                    if chunk_count % 10 == 0 and self.stop_background_processing:
                        print("⏹️ Stopping LLM query - UI became active (periodic check)")
                        break
                
                    # Check for repetitive output (for small models that get stuck)
                    if len(response) > 100:
                        current_50 = response[-50:]
                        if current_50 == last_50_chars:
                            repetition_count += 1
                            if repetition_count > repetition_threshold:  # Dynamic threshold based on model size
                                print(f"⚠️ Detected repetitive output (threshold: {repetition_threshold}), stopping stream")
                                break
                            # Also check UI status during repetition to break out quickly
                            if self.stop_background_processing:
                                print("⏹️ Stopping repetitive LLM query - UI became active")
                                break
                        else:
                            repetition_count = 0
                            last_50_chars = current_50
                    
                    # Additional check for small repetitive patterns (character level)
                    if len(response) > 200:
                        last_20 = response[-20:]
                        if last_20 in response[:-20]:  # This pattern appeared before
                            occurrences = response.count(last_20)
                            if occurrences > 3:  # Same 20-char pattern repeated 3+ times
                                print("⚠️ Detected small repetitive pattern, stopping stream")
                                break
                    
                    # Stop if response gets too long (runaway generation)
                    if len(response) > max_length:
                        print(f"⚠️ Response too long ({len(response)} > {max_length}), stopping stream")
                        break
                    
                    # Stop if too many chunks (likely repetitive)
                    if chunk_count > max_chunks:
                        print(f"⚠️ Too many chunks ({chunk_count} > {max_chunks}), stopping stream")
                        break
                    
                    # Additional UI check when we detect potential problems
                    if (chunk_count > 50 or len(response) > 2000) and self.stop_background_processing:
                        print("⏹️ Stopping problematic LLM query - UI became active")
                        break
                        
            except Exception as stream_e:
                print(f"❌ LLM streaming failed: {stream_e}")
                # Try to return whatever we got so far
                if response:
                    return response.strip()
                return ""
            
            return response.strip()
            
        except Exception as e:
            print(f"❌ LLM query failed: {e}")
            return ""
    
    def _fix_common_json_issues(self, json_str: str) -> str:
        """Fix common JSON formatting issues from smaller models"""
        try:
            import re
            
            # Handle incomplete arrays or objects at the end
            # Find the last complete object or array element
            lines = json_str.split('\n')
            fixed_lines = []
            in_incomplete_line = False
            
            for line in lines:
                line = line.strip()
                
                # Skip empty lines
                if not line:
                    continue
                
                # Check if this line looks incomplete (common patterns)
                if (line.endswith('"') and not line.endswith('",') and not line.endswith('}') and not line.endswith(']')) or \
                   (line.startswith('"') and line.count('"') == 1) or \
                   (line.endswith('[') and not line.endswith('],')) or \
                   (line.endswith(',') and len(line) < 10):  # Very short incomplete lines
                    print(f"🔧 Detected incomplete line: {line}")
                    in_incomplete_line = True
                    continue
                
                # If we were in an incomplete section, try to close it properly
                if in_incomplete_line:
                    # Add closing for the previous incomplete section
                    if fixed_lines and not fixed_lines[-1].endswith(','):
                        # Remove trailing comma from previous line if present
                        if fixed_lines[-1].endswith(','):
                            fixed_lines[-1] = fixed_lines[-1][:-1]
                    in_incomplete_line = False
                
                fixed_lines.append(line)
            
            # Reconstruct the JSON string
            json_str = '\n'.join(fixed_lines)
            
            # Remove trailing commas before closing brackets
            json_str = re.sub(r',\s*}', '}', json_str)
            json_str = re.sub(r',\s*]', ']', json_str)
            
            # Fix missing quotes around keys (but be careful not to double-quote)
            json_str = re.sub(r'(\w+):', r'"\1":', json_str)
            json_str = re.sub(r'""(\w+)":', r'"\1":', json_str)  # Fix double quotes
            
            # Fix single quotes to double quotes
            json_str = json_str.replace("'", '"')
            
            # Ensure the JSON array/object is properly closed
            open_brackets = json_str.count('[') - json_str.count(']')
            open_braces = json_str.count('{') - json_str.count('}')
            
            # Add missing closing brackets
            for _ in range(open_braces):
                json_str += '}'
            for _ in range(open_brackets):
                json_str += ']'
            
            # Remove any trailing incomplete objects or arrays at the very end
            # Find the last properly closed element
            last_complete_end = max(
                json_str.rfind('}'),
                json_str.rfind(']'),
                json_str.rfind('"'),
                -1
            )
            
            if last_complete_end > 0:
                # Look for any incomplete fragments after the last complete element
                remaining = json_str[last_complete_end + 1:].strip()
                if remaining and not remaining.startswith(',') and not remaining.startswith(']') and not remaining.startswith('}'):
                    # There's incomplete content, truncate it
                    json_str = json_str[:last_complete_end + 1]
                    print(f"🔧 Removed incomplete trailing content: {remaining}")
            
            # Final cleanup - ensure proper array structure
            if json_str.strip().startswith('[') and not json_str.strip().endswith(']'):
                json_str = json_str.strip() + ']'
            
            return json_str
            
        except Exception as e:
            print(f"❌ JSON fixing failed: {e}")
            return json_str
    
    def _fix_individual_object(self, obj_str: str) -> str:
        """Fix issues in a single JSON object"""
        try:
            import re
            
            # Remove trailing commas
            obj_str = re.sub(r',\s*}', '}', obj_str)
            
            # Fix unquoted keys
            obj_str = re.sub(r'(\w+):', r'"\1":', obj_str)
            obj_str = re.sub(r'""(\w+)":', r'"\1":', obj_str)  # Fix double quotes
            
            # Fix single quotes
            obj_str = obj_str.replace("'", '"')
            
            # Ensure proper closing
            if obj_str.count('{') > obj_str.count('}'):
                obj_str += '}'
            
            return obj_str
            
        except Exception as e:
            print(f"❌ Individual object fixing failed: {e}")
            return obj_str
    
    def _parse_json_response(self, response: str) -> list:
        """Parse JSON response from LLM, with complex recovery for small models"""
        try:
            if not response or not response.strip():
                return []
            
            # Basic cleanup
            response = response.strip()
            response = response.replace('<|eot_id|>', '').replace('<|end_of_text|>', '').replace('</s>', '').replace('<|im_end|>', '')
            
            # Remove markdown if present
            if response.startswith("```json"):
                response = response[7:]
            if response.startswith("```"):
                response = response[3:]
            if response.endswith("```"):
                response = response[:-3]
            if response.startswith("json"):
                response = response[4:]
            
            # Try direct JSON parsing first
            try:
                parsed = json.loads(response)
                if isinstance(parsed, list):
                    return parsed
                elif isinstance(parsed, dict):
                    return [parsed]
                else:
                    return []
            except:
                pass
            
            # Look for JSON array
            start_idx = response.find('[')
            end_idx = response.rfind(']')
            
            if start_idx != -1 and end_idx != -1:
                json_str = response[start_idx:end_idx+1]
                
                # Try to fix common JSON issues
                json_str = self._fix_common_json_issues(json_str)
                
                try:
                    parsed = json.loads(json_str)
                    if isinstance(parsed, list):
                        return parsed
                    else:
                        return [parsed] if parsed else []
                except json.JSONDecodeError as e:
                    print(f"❌ JSON parsing failed even after cleanup: {e}")
                    print(f"🔧 Problematic JSON: {json_str[:200]}...")
                    return self._extract_fallback_data(response)
            
            # No valid JSON array found
            return self._extract_fallback_data(response)
            
        except Exception as e:
            print(f"❌ JSON parsing error: {e}")
            return self._extract_fallback_data(response)
    
    def _parse_json_response_dict(self, response: str) -> dict:
        """Parse JSON object response from LLM"""
        try:
            # Clean up the response
            response = response.strip()
            
            # Remove model-specific tokens
            response = response.replace('<|eot_id|>', '')
            response = response.replace('<|end_of_text|>', '')
            response = response.replace('</s>', '')
            response = response.replace('<|im_end|>', '')
            
            # Remove markdown code blocks if present
            if response.startswith("```json"):
                response = response[7:]
            if response.startswith("```"):
                response = response[3:]
            if response.endswith("```"):
                response = response[:-3]
            
            # Find JSON object in the response
            start_idx = response.find('{')
            end_idx = response.rfind('}')
            
            if start_idx != -1 and end_idx != -1:
                json_str = response[start_idx:end_idx+1]
                return json.loads(json_str)
            else:
                print(f"🔧 No valid JSON object found in response, returning empty dict")
                return {}
                
        except json.JSONDecodeError as e:
            print(f"❌ JSON object parsing failed: {e}")
            print(f"🔧 Raw response (first 500 chars): {response[:500]}")
            return {}
        except Exception as e:
            print(f"❌ Response object parsing failed: {e}")
            print(f"🔧 Raw response (first 500 chars): {response[:500]}")
            return {}
    
    def _extract_fallback_data(self, response: str) -> list:
        """Complex fallback extraction when JSON parsing fails"""
        try:
            objects = []
            
            # Look for individual JSON objects in the response
            lines = response.split('\n')
            for line in lines:
                line = line.strip()
                if line.startswith('{') and line.endswith('}'):
                    try:
                        obj = json.loads(line)
                        objects.append(obj)
                    except:
                        continue
            
            if objects:
                print(f"🔧 Recovered {len(objects)} objects from lines")
                return objects
            
            # Try to find partial JSON objects using regex
            import re
            json_pattern = r'\{[^{}]*"[^"]*"\s*:[^{}]*\}'
            matches = re.findall(json_pattern, response)
            
            for match in matches:
                try:
                    fixed_match = self._fix_individual_object(match)
                    obj = json.loads(fixed_match)
                    objects.append(obj)
                except:
                    continue
            
            if objects:
                print(f"🔧 Recovered {len(objects)} objects using regex")
                return objects
            
            # Look for key-value patterns in repetitive text
            objects = self._extract_from_repetitive_text(response)
            if objects:
                print(f"🔧 Recovered {len(objects)} objects from repetitive text")
                return objects
                
            print("🔧 No recoverable data found, returning empty list")
            return []
            
        except Exception as e:
            print(f"❌ Fallback extraction failed: {e}")
            return []
    
    def _extract_from_repetitive_text(self, response: str) -> list:
        """Extract meaningful data from repetitive text output (common in small models)"""
        try:
            # Look for patterns that might indicate repeated structured data
            import re
            
            # Check if response contains repetitive patterns
            if len(response) < 100:
                return []
            
            # Look for repeated phrases or patterns that might contain data
            # This is a simple heuristic for extracting from repetitive output
            lines = response.split('\n')
            unique_lines = []
            seen_lines = set()
            
            for line in lines:
                line = line.strip()
                if line and line not in seen_lines and len(line) > 10:
                    unique_lines.append(line)
                    seen_lines.add(line)
                    
                    # Limit to prevent processing too much repetitive text
                    if len(unique_lines) > 20:
                        break
            
            # Try to extract structured information from unique lines
            objects = []
            for line in unique_lines:
                # Look for key patterns that might indicate facts, preferences, etc.
                if any(word in line.lower() for word in ['fact', 'preference', 'pattern', 'skill', 'goal']):
                    # Create a simple object from the line
                    obj = {
                        "content": line,
                        "type": "extracted_from_repetitive",
                        "importance": 0.5
                    }
                    objects.append(obj)
            
            return objects[:5]  # Limit to 5 objects max
            
        except Exception as e:
            print(f"❌ Repetitive text extraction failed: {e}")
            return []
    
    def _pattern_based_extraction(self, response: str) -> list:
        """Simple pattern extraction fallback"""
        return []
    
    def _extract_facts_fallback(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Fallback fact extraction using simple patterns"""
        memories = []
        fact_patterns = [
            ("I am", "personal_info"), ("I work", "professional"), ("I live", "location"),
            ("I have", "possessions"), ("My name is", "identity"), ("I study", "education")
        ]
        
        lines = conversation.split('\n')
        for line in lines:
            if line.startswith("User:"):
                content = line[5:].strip()
                for pattern, category in fact_patterns:
                    if pattern.lower() in content.lower():
                        memory = MemoryEntry(
                            id=f"{user_id}_fact_{int(time.time())}_{hash(content) % 10000}",
                            user_id=user_id, content=content, memory_type="fact",
                            importance=0.8, created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(), access_count=0,
                            keywords=[category], context=conversation[:500]
                        )
                        memories.append(memory)
                        break
        return memories
    
    def _extract_preferences_fallback(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Fallback preference extraction using simple patterns"""
        memories = []
        preference_patterns = [
            ("I like", "likes"), ("I don't like", "dislikes"), ("I prefer", "preferences"),
            ("I love", "loves"), ("I enjoy", "enjoys"), ("I want", "wants")
        ]
        
        lines = conversation.split('\n')
        for line in lines:
            if line.startswith("User:"):
                content = line[5:].strip()
                for pattern, category in preference_patterns:
                    if pattern.lower() in content.lower():
                        memory = MemoryEntry(
                            id=f"{user_id}_pref_{int(time.time())}_{hash(content) % 10000}",
                            user_id=user_id, content=content, memory_type="preference",
                            importance=0.7, created_at=datetime.now().isoformat(),
                            last_accessed=datetime.now().isoformat(), access_count=0,
                            keywords=[category], context=conversation[:500]
                        )
                        memories.append(memory)
                        break
        return memories
    
    def _extract_patterns_fallback(self, user_id: str, conversation: str) -> List[MemoryEntry]:
        """Fallback pattern extraction using simple analysis"""
        memories = []
        questions = [line for line in conversation.split('\n') 
                    if line.startswith("User:") and "?" in line]
        
        if len(questions) > 2:
            memory = MemoryEntry(
                id=f"{user_id}_pattern_{int(time.time())}_curious",
                user_id=user_id,
                content=f"User tends to ask many questions ({len(questions)} in this conversation)",
                memory_type="pattern", importance=0.6,
                created_at=datetime.now().isoformat(),
                last_accessed=datetime.now().isoformat(), access_count=0,
                keywords=["curious", "questions"], context=conversation[:500]
            )
            memories.append(memory)
        return memories
    
    def _update_user_profile(self, user_id: str, messages: List[Dict]):
        """Update user profile based on LLM conversation analysis"""
        try:
            # Build conversation for analysis
            conversation_text = ""
            for msg in messages:
                if msg.get("role") in ["user", "human"]:
                    conversation_text += f"User: {msg.get('content', '')}\n"
                elif msg.get("role") in ["assistant", "ai"]:
                    conversation_text += f"AI: {msg.get('content', '')}\n"
            
            # Use LLM to analyze user profile
            prompt = f"""Analyze this conversation and create a comprehensive user profile.
                        Focus on communication style, interests, expertise areas, personality traits, and preferences.

                        Conversation:
                        {conversation_text}

                        Extract profile information and return as JSON:
                        {{
                        "communication_style": "formal|casual|technical|conversational|professional",
                        "interests": ["interest1", "interest2"],
                        "expertise_areas": ["area1", "area2"],
                        "personality_traits": ["trait1", "trait2"],
                        "preferences": {{
                            "response_style": "detailed|brief|balanced",
                            "tone": "friendly|professional|casual"
                        }}
                        }}

                        Return only the JSON, no other text."""

            from simple_llm_query import simple_query_llm
            response = simple_query_llm(prompt)
            if response:
                profile_data = self._parse_json_response_dict(response)
                if profile_data:
                    # Get existing profile or create new one
                    profile = self._fetch_profile_from_db(user_id)
                    if not profile:
                        profile = UserProfile(
                            user_id=user_id,
                            communication_style="casual",
                            interests=[],
                            expertise_areas=[],
                            personality_traits=[],
                            preferences={},
                            updated_at=datetime.now().isoformat()
                        )
                    
                    # Update with LLM analysis
                    profile.communication_style = profile_data.get("communication_style", profile.communication_style)
                    
                    # Merge interests (avoid duplicates)
                    new_interests = profile_data.get("interests", [])
                    profile.interests = list(set(profile.interests + new_interests))
                    
                    # Merge expertise areas
                    new_expertise = profile_data.get("expertise_areas", [])
                    profile.expertise_areas = list(set(profile.expertise_areas + new_expertise))
                    
                    # Merge personality traits
                    new_traits = profile_data.get("personality_traits", [])
                    profile.personality_traits = list(set(profile.personality_traits + new_traits))
                    
                    # Update preferences
                    new_prefs = profile_data.get("preferences", {})
                    profile.preferences.update(new_prefs)
                    
                    profile.updated_at = datetime.now().isoformat()
                    
                    # Store updated profile
                    self._store_profile(profile)
                    print(f"✅ Updated profile for {user_id} using LLM analysis")
                    return
                    
        except Exception as e:
            print(f"❌ LLM profile update failed: {e}")
        
        # Fallback to simple analysis
        self._update_user_profile_fallback(user_id, messages)
    
    def _update_user_profile_fallback(self, user_id: str, messages: List[Dict]):
        """Fallback profile update using simple pattern analysis"""
        # Get existing profile or create new one
        profile = self._fetch_profile_from_db(user_id)
        if not profile:
            profile = UserProfile(
                user_id=user_id,
                communication_style="casual",
                interests=[],
                expertise_areas=[],
                personality_traits=[],
                preferences={},
                updated_at=datetime.now().isoformat()
            )
        
        # Simple analysis of communication style
        user_messages = [msg for msg in messages if msg.get("role") in ["user", "human"]]
        
        if user_messages:
            formal_indicators = ["please", "thank you", "could you", "would you"]
            casual_indicators = ["hey", "yeah", "cool", "awesome", "lol"]
            
            formal_count = casual_count = 0
            for msg in user_messages:
                content = msg.get("content", "").lower()
                formal_count += sum(1 for indicator in formal_indicators if indicator in content)
                casual_count += sum(1 for indicator in casual_indicators if indicator in content)
            
            if formal_count > casual_count:
                profile.communication_style = "formal"
            elif casual_count > formal_count:
                profile.communication_style = "casual"
            else:
                profile.communication_style = "balanced"
        
        profile.updated_at = datetime.now().isoformat()
        self._store_profile(profile)
    
    def _prefetch_user_data(self):
        """Pre-fetch memories and profiles for all users when UI is closed"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT DISTINCT user_id FROM memories")
                user_ids = [row[0] for row in cursor.fetchall()]
                
                for user_id in user_ids:
                    # Pre-fetch memories
                    self.ready_memories[user_id] = self._fetch_memories_from_db(user_id, limit=50)
                    
                    # Pre-fetch profile
                    profile = self._fetch_profile_from_db(user_id)
                    if profile:
                        self.ready_profiles[user_id] = profile
                
                if user_ids:
                    print(f"🚀 Pre-fetched data for {len(user_ids)} users")
                    
        except Exception as e:
            print(f"❌ Error pre-fetching data: {e}")
    
    def _cleanup_old_memories(self):
        """Clean up old, low-importance memories"""
        try:
            cutoff_date = (datetime.now() - timedelta(days=90)).isoformat()
            
            # Delete old, low-importance memories that haven't been accessed
            deleted_count = self._execute_with_retry("""
                DELETE FROM memories 
                WHERE importance < 0.3 
                AND access_count = 0 
                AND created_at < ?
            """, (cutoff_date,))
            
            if deleted_count > 0:
                print(f"🧹 Cleaned up {deleted_count} old memories")
                
            # Clean up old processed chats
            old_chat_cutoff = (datetime.now() - timedelta(days=7)).isoformat()
            chat_deleted_count = self._execute_with_retry("""
                DELETE FROM pending_chats 
                WHERE processed = 1 
                AND created_at < ?
            """, (old_chat_cutoff,))
            
            if chat_deleted_count > 0:
                print(f"🧹 Cleaned up {chat_deleted_count} old processed chats")
                
        except Exception as e:
            print(f"❌ Error during cleanup: {e}")
    
    # === DATABASE HELPERS ===
    
    def _store_memory(self, memory: MemoryEntry):
        """Store a memory entry in both SQL and vector databases"""
        try:
            # Store memory directly in SQL database
            self._execute_with_retry("""
                INSERT OR REPLACE INTO memories 
                (id, user_id, content, memory_type, importance, created_at, 
                 last_accessed, access_count, keywords, context)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                memory.id, memory.user_id, memory.content, memory.memory_type,
                memory.importance, memory.created_at, memory.last_accessed,
                memory.access_count, json.dumps(memory.keywords), memory.context
            ))
            print(f"💾 Memory {memory.id} stored in SQL database")
            
            # Also store in vector database via hybrid memory system
            try:
                # Import here to avoid circular imports
                from hybrid_memory_system import get_hybrid_memory
                hybrid_memory = get_hybrid_memory()
                
                if hybrid_memory:
                    # Store in vector database (this will also update SQL via hybrid system)
                    import asyncio
                    loop = None
                    try:
                        loop = asyncio.get_running_loop()
                    except RuntimeError:
                        pass
                    
                    if loop:
                        # We're in an async context, schedule the vector storage
                        asyncio.create_task(hybrid_memory.store_vector(memory))
                        print(f"🔍 Scheduled vector storage for memory {memory.id}")
                    else:
                        # Run in new event loop for vector storage
                        asyncio.run(hybrid_memory.store_vector(memory))
                        print(f"🔍 Memory {memory.id} vectorized and stored")
                else:
                    print(f"⚠️ Hybrid memory not available, skipping vector storage")
                    
            except Exception as vector_error:
                print(f"⚠️ Vector storage failed (SQL storage succeeded): {vector_error}")
            
            # Trigger prefetch when new memory is stored (only if UI is inactive)
            if not self.is_ui_active:
                print("🧠 New memory stored - triggering prefetch")
                self.processing_queue.put("prefetch_data")
            
            # Trigger automatic memory optimization if needed
            try:
                from memory_optimizer import get_memory_optimizer
                optimizer = get_memory_optimizer()
                
                # Check if optimization is needed (runs optimization only if thresholds are met)
                results = optimizer.auto_optimize_if_needed(user_id=memory.user_id)
                if results:
                    print(f"🗜️ Auto-optimization completed: saved {results.get('savings_mb', 0)}MB")
                    
            except Exception as opt_error:
                print(f"⚠️ Auto-optimization failed (memory storage successful): {opt_error}")
                
        except Exception as e:
            print(f"❌ Critical: Failed to store memory in SQL database: {e}")
    
    def _start_vector_processor(self):
        """Vector processing is now handled by the memory coordinator"""
        # Note: This method is kept for compatibility but vector processing
        # is now handled by the MemoryStorageCoordinator to prevent infinite loops
        print("📝 Vector processing delegated to memory coordinator")
    
    def _store_profile(self, profile: UserProfile):
        """Store user profile in database"""
        try:
            self._execute_with_retry("""
                INSERT OR REPLACE INTO user_profiles 
                (user_id, communication_style, interests, expertise_areas, 
                 personality_traits, preferences, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                profile.user_id, profile.communication_style,
                json.dumps(profile.interests), json.dumps(profile.expertise_areas),
                json.dumps(profile.personality_traits), json.dumps(profile.preferences),
                profile.updated_at
            ))
        except Exception as e:
            print(f"❌ Failed to store profile: {e}")
    
    def _fetch_memories_from_db(self, user_id: str, limit: int = 20) -> List[MemoryEntry]:
        """Fetch memories from database"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, user_id, content, memory_type, importance, created_at,
                       last_accessed, access_count, keywords, context
                FROM memories 
                WHERE user_id = ? 
                ORDER BY importance DESC, access_count DESC, created_at DESC
                LIMIT ?
            """, (user_id, limit))
            
            memories = []
            for row in cursor.fetchall():
                memory = MemoryEntry(
                    id=row[0], user_id=row[1], content=row[2], memory_type=row[3],
                    importance=row[4], created_at=row[5], last_accessed=row[6],
                    access_count=row[7], keywords=json.loads(row[8]), context=row[9]
                )
                memories.append(memory)
            
            return memories
    
    def _fetch_profile_from_db(self, user_id: str) -> Optional[UserProfile]:
        """Fetch user profile from database"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT user_id, communication_style, interests, expertise_areas,
                       personality_traits, preferences, updated_at
                FROM user_profiles 
                WHERE user_id = ?
            """, (user_id,))
            
            row = cursor.fetchone()
            if row:
                return UserProfile(
                    user_id=row[0], communication_style=row[1],
                    interests=json.loads(row[2]), expertise_areas=json.loads(row[3]),
                    personality_traits=json.loads(row[4]), preferences=json.loads(row[5]),
                    updated_at=row[6]
                )
            
            return None


# Global instance
smart_memory = None

def initialize_smart_memory():
    """Initialize the global smart memory system"""
    global smart_memory
    smart_memory = SmartMemorySystem()
    print("🧠 Smart Memory System initialized")
    return smart_memory

def get_smart_memory() -> SmartMemorySystem:
    """Get the global smart memory instance"""
    global smart_memory
    if smart_memory is None:
        smart_memory = initialize_smart_memory()
    return smart_memory