"""
Chat Manager with LangGraph for advanced conversation handling.
Features: Chat history, memory management, web search, deep reasoning.
"""

import asyncio
import json
import sqlite3
import datetime
import uuid

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
from typing import Dict, List, Any, Optional, TypedDict, Annotated
from pathlib import Path

from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
from langchain_core.messages import BaseMessage, HumanMessage, AIMessage, SystemMessage
from langchain_core.tools import tool
from context_manager import context_manager, get_system_optimized_context

# State definition for the chat graph
class ChatState(TypedDict):
    messages: Annotated[List[BaseMessage], "The messages in the conversation"]
    user_id: str
    chat_id: str
    context: Dict[str, Any]
    memory_context: Dict[str, Any]
    tools_used: List[str]
    reasoning_depth: int

class ChatManager:
    """Advanced chat manager with memory, history, and tool usage."""
    
    def __init__(self, db_path: str = "./chat_history.db"):
        self.db_path = db_path
        self.setup_database()
        
        # Initialize LangGraph components - simplified without checkpointer for now
        self.workflow = self._create_workflow()
        self.app = self.workflow.compile()  # Compile without checkpointer to avoid issues
        
        # Memory contexts
        self.short_term_memory = {}  # Session-based memory
        self.long_term_memory = {}   # Persistent user memory
        
        # Model integration
        self.current_llm = None  # Will be set by unified_app
        self.model_ready = False
        
    def setup_database(self):
        """Initialize SQLite database for chat history."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Chat sessions table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS chat_sessions (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                title TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                message_count INTEGER DEFAULT 0
            )
        ''')
        
        # Messages table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                chat_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                metadata TEXT,
                FOREIGN KEY (chat_id) REFERENCES chat_sessions (id)
            )
        ''')
        
        # User memory table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS user_memory (
                user_id TEXT NOT NULL,
                memory_type TEXT NOT NULL,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (user_id, memory_type, key)
            )
        ''')
        
        # User preferences table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS user_preferences (
                user_id TEXT PRIMARY KEY,
                tone_style TEXT DEFAULT 'balanced',
                response_length TEXT DEFAULT 'medium',
                technical_level TEXT DEFAULT 'intermediate',
                interests TEXT,
                communication_style TEXT DEFAULT 'friendly',
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def _create_workflow(self) -> StateGraph:
        """Create the LangGraph workflow for chat processing."""
        
        # Define tools
        @tool
        def web_search(query: str) -> str:
            """Search the web for current information."""
            # Note: You'll need to set TAVILY_API_KEY environment variable
            try:
                # Optional: only import if available
                from langchain_community.tools.tavily_search import TavilySearchResults
                search = TavilySearchResults(max_results=3)
                results = search.run(query)
                return f"Web search results for '{query}': {results}"
            except ImportError:
                return f"Web search not available (TavilySearchResults not installed)"
            except Exception as e:
                return f"Web search failed: {str(e)}"
        
        @tool
        def save_memory(user_id: str, key: str, value: str, memory_type: str = "short_term") -> str:
            """Save information to user memory."""
            try:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute('''
                    INSERT OR REPLACE INTO user_memory 
                    (user_id, memory_type, key, value, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                ''', (user_id, memory_type, key, value, datetime.datetime.now()))
                conn.commit()
                conn.close()
                return f"Saved {memory_type} memory: {key}"
            except Exception as e:
                return f"Failed to save memory: {str(e)}"
        
        @tool
        def retrieve_memory(user_id: str, memory_type: str = "short_term") -> str:
            """Retrieve user memory."""
            try:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute('''
                    SELECT key, value FROM user_memory 
                    WHERE user_id = ? AND memory_type = ?
                    ORDER BY updated_at DESC
                ''', (user_id, memory_type))
                memories = cursor.fetchall()
                conn.close()
                
                if memories:
                    memory_text = "\\n".join([f"{key}: {value}" for key, value in memories])
                    return f"Retrieved {memory_type} memories:\\n{memory_text}"
                return f"No {memory_type} memories found"
            except Exception as e:
                return f"Failed to retrieve memory: {str(e)}"
        
        tools = [web_search, save_memory, retrieve_memory]
        # Simplified tool executor for now
        class SimpleToolExecutor:
            def __init__(self, tools):
                self.tools = {tool.name: tool for tool in tools}
            
            def invoke(self, tool_invocation):
                tool_name = tool_invocation.tool if hasattr(tool_invocation, 'tool') else tool_invocation
                tool_input = tool_invocation.tool_input if hasattr(tool_invocation, 'tool_input') else {}
                
                if tool_name in self.tools:
                    return self.tools[tool_name].invoke(tool_input)
                return f"Tool {tool_name} not found"
        
        tool_executor = SimpleToolExecutor(tools)
        
        # Define workflow nodes
        async def call_model(state: ChatState):
            """Call the current model with the conversation state."""
            messages = state["messages"]
            
            # Build system context with memory and preferences
            system_context = self._build_system_context(state)
            
            # Optimize context using dynamic context manager
            optimized_messages, context_metadata = get_system_optimized_context(
                messages, 
                system_context
            )
            
            # Store context optimization metadata for later use
            state["context"]["optimization"] = context_metadata
            
            # Call the actual model with optimized context
            try:
                response_content = await self.call_actual_model(optimized_messages)
                
                # Add context info in debug mode
                if context_metadata.get('summarized'):
                    debug_info = f"\n\n[Context optimized: {context_metadata.get('messages_summarized', 0)} messages summarized]"
                    response_content += debug_info
                
            except Exception as e:
                print(f"❌ Error calling model in workflow: {e}")
                response_content = f"Error generating response: {str(e)}"
            
            response = AIMessage(content=response_content)
            
            return {
                **state,
                "messages": optimized_messages + [response]
            }
        
        def should_use_tools(state: ChatState) -> bool:
            """Determine if tools should be used based on the last message."""
            last_message = state["messages"][-1]
            if isinstance(last_message, HumanMessage):
                content = last_message.content.lower()
                # Check for web search triggers
                if any(keyword in content for keyword in ["search", "current", "latest", "news", "what's happening"]):
                    return True
                # Check for memory triggers
                if any(keyword in content for keyword in ["remember", "save", "recall", "previous"]):
                    return True
            return False
        
        def call_tools(state: ChatState):
            """Execute tools based on the conversation context."""
            last_message = state["messages"][-1]
            tools_used = []
            
            if isinstance(last_message, HumanMessage):
                content = last_message.content.lower()
                
                # Web search
                if any(keyword in content for keyword in ["search", "current", "latest"]):
                    search_query = self._extract_search_query(last_message.content)
                    if search_query:
                        class SimpleToolInvocation:
                            def __init__(self, tool, tool_input):
                                self.tool = tool
                                self.tool_input = tool_input
                        
                        result = tool_executor.invoke(SimpleToolInvocation("web_search", {"query": search_query}))
                        tools_used.append("web_search")
                        state["context"]["web_search_result"] = result
                
                # Memory operations
                if "remember" in content:
                    # Extract what to remember
                    memory_item = self._extract_memory_item(last_message.content)
                    if memory_item:
                        class SimpleToolInvocation:
                            def __init__(self, tool, tool_input):
                                self.tool = tool
                                self.tool_input = tool_input
                        
                        result = tool_executor.invoke(SimpleToolInvocation(
                            "save_memory", 
                            {
                                "user_id": state["user_id"],
                                "key": memory_item["key"],
                                "value": memory_item["value"],
                                "memory_type": "long_term"
                            }
                        ))
                        tools_used.append("save_memory")
            
            return {
                **state,
                "tools_used": state.get("tools_used", []) + tools_used
            }
        
        def route_after_tools(state: ChatState):
            """Route after tools execution."""
            return "call_model"
        
        # Build the graph
        workflow = StateGraph(ChatState)
        
        # Add nodes
        workflow.add_node("call_model", call_model)
        workflow.add_node("call_tools", call_tools)
        
        # Add edges
        workflow.set_entry_point("call_model")
        workflow.add_conditional_edges(
            "call_model",
            should_use_tools,
            {
                True: "call_tools",
                False: END
            }
        )
        workflow.add_edge("call_tools", "call_model")
        
        return workflow
    
    def _build_system_context(self, state: ChatState) -> str:
        """Build system context with user memory and preferences."""
        user_id = state["user_id"]
        
        # Get user preferences
        preferences = self.get_user_preferences(user_id)
        
        # Get recent memories
        short_term = self.get_user_memory(user_id, "short_term", limit=5)
        long_term = self.get_user_memory(user_id, "long_term", limit=10)
        
        context_parts = [
            f"User preferences: {json.dumps(preferences)}",
        ]
        
        if short_term:
            context_parts.append(f"Recent context: {short_term}")
        
        if long_term:
            context_parts.append(f"Long-term memory: {long_term}")
        
        return "\\n".join(context_parts)
    
    def _extract_search_query(self, content: str) -> Optional[str]:
        """Extract search query from user message."""
        # Simple implementation - can be enhanced
        content = content.lower()
        if "search for" in content:
            return content.split("search for", 1)[1].strip()
        elif "search" in content:
            # Extract words after "search"
            words = content.split()
            if "search" in words:
                idx = words.index("search")
                if idx + 1 < len(words):
                    return " ".join(words[idx + 1:])
        return None
    
    def _extract_memory_item(self, content: str) -> Optional[Dict[str, str]]:
        """Extract memory item from user message."""
        # Simple implementation
        if "remember that" in content.lower():
            parts = content.lower().split("remember that", 1)
            if len(parts) > 1:
                memory_content = parts[1].strip()
                return {
                    "key": f"user_note_{datetime.datetime.now().isoformat()}",
                    "value": memory_content
                }
        return None
    
    async def process_message(self, user_id: str, message: str, chat_id: Optional[str] = None) -> Dict[str, Any]:
        """Process a user message through the LangGraph workflow."""
        
        if not chat_id:
            chat_id = self.create_chat_session(user_id)
        
        # Create initial state
        state = ChatState(
            messages=[HumanMessage(content=message)],
            user_id=user_id,
            chat_id=chat_id,
            context={},
            memory_context={},
            tools_used=[],
            reasoning_depth=0
        )
        
        # Get chat history
        history = self.get_chat_history(chat_id, limit=20)
        state["messages"] = history + state["messages"]
        
        # Process through workflow
        config = {"configurable": {"thread_id": chat_id}}
        result = await self.app.ainvoke(state, config=config)
        
        # Save messages to database
        self.save_message(chat_id, "human", message)
        if result["messages"]:
            last_ai_message = result["messages"][-1]
            if isinstance(last_ai_message, AIMessage):
                self.save_message(chat_id, "ai", last_ai_message.content)
        
        return {
            "response": result["messages"][-1].content if result["messages"] else "No response generated",
            "chat_id": chat_id,
            "tools_used": result.get("tools_used", []),
            "context": result.get("context", {})
        }
    
    def create_chat_session(self, user_id: str, title: Optional[str] = None) -> str:
        """Create a new chat session."""
        chat_id = str(uuid.uuid4())
        
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO chat_sessions (id, user_id, title)
                VALUES (?, ?, ?)
            ''', (chat_id, user_id, title or f"Chat {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}"))
            conn.commit()
            conn.close()
            print(f"✅ Created chat session {chat_id} for user {user_id}")
            return chat_id
        except Exception as e:
            print(f"❌ Failed to create chat session: {e}")
            return chat_id  # Return the ID anyway so chat can continue
    
    def update_chat_session_title(self, chat_id: str, first_message: str) -> bool:
        """Update chat session title based on the first user message."""
        try:
            # Create a meaningful title from the first message
            # Truncate to 50 characters and clean up
            title = first_message.strip()
            if len(title) > 50:
                title = title[:47] + "..."
            
            # Remove newlines and extra spaces
            title = " ".join(title.split())
            
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute('''
                UPDATE chat_sessions 
                SET title = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
            ''', (title, chat_id))
            conn.commit()
            conn.close()
            
            print(f"✅ Updated chat session {chat_id} title: '{title}'")
            return True
        except Exception as e:
            print(f"❌ Failed to update chat session title: {e}")
            return False
    
    def get_chat_history(self, chat_id: str, limit: int = 50) -> List[BaseMessage]:
        """Get chat history for a session."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT role, content FROM messages 
            WHERE chat_id = ? 
            ORDER BY timestamp ASC 
            LIMIT ?
        ''', (chat_id, limit))
        
        messages = []
        for role, content in cursor.fetchall():
            if role == "human":
                messages.append(HumanMessage(content=content))
            elif role == "ai":
                messages.append(AIMessage(content=content))
        
        conn.close()
        return messages
    
    def save_message(self, chat_id: str, role: str, content: str, metadata: Optional[Dict] = None):
        """Save a message to the database."""
        message_id = str(uuid.uuid4())
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO messages (id, chat_id, role, content, metadata)
            VALUES (?, ?, ?, ?, ?)
        ''', (message_id, chat_id, role, content, json.dumps(metadata) if metadata else None))
        
        # Update session message count
        cursor.execute('''
            UPDATE chat_sessions 
            SET message_count = message_count + 1, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ''', (chat_id,))
        
        conn.commit()
        conn.close()
    
    def get_user_sessions(self, user_id: str) -> List[Dict[str, Any]]:
        """Get all chat sessions for a user."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT id, title, created_at, updated_at, message_count
            FROM chat_sessions 
            WHERE user_id = ? 
            ORDER BY updated_at DESC
        ''', (user_id,))
        
        sessions = []
        for row in cursor.fetchall():
            sessions.append({
                "id": row[0],
                "title": row[1],
                "created_at": row[2],
                "updated_at": row[3],
                "message_count": row[4]
            })
        
        conn.close()
        return sessions
    
    def get_user_memory(self, user_id: str, memory_type: str = "short_term", limit: int = 10) -> List[Dict[str, Any]]:
        """Get user memory."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT key, value, created_at, updated_at
            FROM user_memory 
            WHERE user_id = ? AND memory_type = ?
            ORDER BY updated_at DESC 
            LIMIT ?
        ''', (user_id, memory_type, limit))
        
        memories = []
        for row in cursor.fetchall():
            memories.append({
                "key": row[0],
                "value": row[1],
                "created_at": row[2],
                "updated_at": row[3]
            })
        
        conn.close()
        return memories
    
    def get_user_preferences(self, user_id: str) -> Dict[str, Any]:
        """Get user preferences."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT tone_style, response_length, technical_level, interests, communication_style
            FROM user_preferences 
            WHERE user_id = ?
        ''', (user_id,))
        
        row = cursor.fetchone()
        conn.close()
        
        if row:
            return {
                "tone_style": row[0],
                "response_length": row[1],
                "technical_level": row[2],
                "interests": row[3],
                "communication_style": row[4]
            }
        else:
            # Default preferences
            return {
                "tone_style": "balanced",
                "response_length": "medium",
                "technical_level": "intermediate",
                "interests": "",
                "communication_style": "friendly"
            }
    
    def update_user_preferences(self, user_id: str, preferences: Dict[str, Any]):
        """Update user preferences."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT OR REPLACE INTO user_preferences 
            (user_id, tone_style, response_length, technical_level, interests, communication_style, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            user_id,
            preferences.get("tone_style", "balanced"),
            preferences.get("response_length", "medium"),
            preferences.get("technical_level", "intermediate"),
            preferences.get("interests", ""),
            preferences.get("communication_style", "friendly"),
            datetime.datetime.now()
        ))
        conn.commit()
        conn.close()
    
    def summarize_old_messages(self, chat_id: str, keep_recent: int = 20):
        """Summarize old messages when context limit is reached."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get messages older than the recent ones
        cursor.execute('''
            SELECT content FROM messages 
            WHERE chat_id = ? 
            ORDER BY timestamp ASC 
            LIMIT -1 OFFSET ?
        ''', (chat_id, keep_recent))
        
        old_messages = [row[0] for row in cursor.fetchall()]
        
        if len(old_messages) > 0:
            # Create summary (this would use the current model)
            summary = f"Previous conversation summary: {len(old_messages)} messages discussing various topics."
            
            # Save summary as a special message
            self.save_message(chat_id, "system", summary, {"type": "summary", "original_count": len(old_messages)})
            
            # Delete old messages
            cursor.execute('''
                DELETE FROM messages 
                WHERE chat_id = ? AND id NOT IN (
                    SELECT id FROM messages 
                    WHERE chat_id = ? 
                    ORDER BY timestamp DESC 
                    LIMIT ?
                )
            ''', (chat_id, chat_id, keep_recent + 1))  # +1 for the summary
            
            conn.commit()
        
        conn.close()
    
    def set_model(self, llm, model_ready: bool = True):
        """Set the current model for the chat manager."""
        self.current_llm = llm
        self.model_ready = model_ready
        print(f"🔗 Chat manager connected to model: {model_ready}")
    
    async def call_actual_model(self, messages: List[BaseMessage]) -> str:
        """Call the actual loaded model with optimized messages."""
        if not self.model_ready or not self.current_llm:
            return "No model loaded. Please load a model first."
        
        try:
            # Convert messages to a conversation format that preserves full context
            conversation_parts = []
            
            for msg in messages:
                if isinstance(msg, HumanMessage):
                    conversation_parts.append(f"User: {msg.content}")
                elif isinstance(msg, AIMessage):
                    # Clean up any end tokens from previous responses
                    clean_content = msg.content.replace("<|eot_id|>", "").strip()
                    conversation_parts.append(f"Assistant: {clean_content}")
                elif isinstance(msg, SystemMessage):
                    conversation_parts.append(f"System: {msg.content}")
            
            if not conversation_parts:
                return "No messages found."
            
            # Build full conversation context with proper chat format
            # Use a more explicit conversation format that the model understands better
            if len(conversation_parts) > 1:
                # Multi-turn conversation - build full context
                conversation_context = "\n".join(conversation_parts[-10:])  # Last 10 exchanges
                full_prompt = f"This is a conversation between a user and an AI assistant. The assistant should remember information from earlier in the conversation.\n\n{conversation_context}\nAssistant:"
            else:
                # Single message - just use it directly
                full_prompt = conversation_parts[0].replace("User: ", "") + "\nAssistant:"
            
            # Generate response using the current model
            if hasattr(self.current_llm, 'stream'):
                # For streaming models, collect the full response
                full_response = ""
                for chunk in self.current_llm.stream(full_prompt):
                    # Use universal chunk content extractor
                    chunk_content = extract_chunk_content(chunk, "chat_manager")
                    full_response += chunk_content
                return full_response
            elif hasattr(self.current_llm, 'generate'):
                # For non-streaming models
                response = self.current_llm.generate(full_prompt)
                return str(response)
            else:
                # Try calling the model directly
                response = self.current_llm(full_prompt)
                return str(response)
                
        except Exception as e:
            print(f"❌ Error calling model: {e}")
            return f"Error generating response: {str(e)}"

# Global chat manager instance
chat_manager = ChatManager()