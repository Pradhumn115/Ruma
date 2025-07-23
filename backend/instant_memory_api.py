"""
Instant Memory API
==================

Provides lightning-fast access to pre-fetched memory data.
No latency during active chat sessions.
"""

from typing import Dict, List, Any, Optional
from smart_memory_system import get_smart_memory, MemoryEntry, UserProfile
from background_learning_service import get_ui_status_tracker


class InstantMemoryAPI:
    """
    High-speed memory API that serves pre-fetched data
    """
    
    def __init__(self):
        self.smart_memory = get_smart_memory()
        self.ui_tracker = get_ui_status_tracker()
    
    # === INSTANT ACCESS METHODS ===
    
    def get_user_context(self, user_id: str) -> Dict[str, Any]:
        """
        Get complete user context instantly - this is the main method
        the chat system should call for personalization
        """
        # Mark UI activity
        self.ui_tracker.mark_ui_activity()
        
        # Get pre-fetched data
        memories = self.smart_memory.get_user_memories(user_id, limit=20)
        profile = self.smart_memory.get_user_profile(user_id)
        
        # Build context
        context = {
            "user_id": user_id,
            "profile": {
                "communication_style": profile.communication_style if profile else "casual",
                "interests": profile.interests if profile else [],
                "expertise_areas": profile.expertise_areas if profile else [],
                "personality_traits": profile.personality_traits if profile else [],
                "preferences": profile.preferences if profile else {}
            },
            "recent_memories": [
                {
                    "content": memory.content,
                    "type": memory.memory_type,
                    "importance": memory.importance,
                    "keywords": memory.keywords
                }
                for memory in memories[:10]  # Top 10 most relevant
            ],
            "facts": [
                memory.content for memory in memories 
                if memory.memory_type == "fact"
            ][:5],
            "preferences": [
                memory.content for memory in memories 
                if memory.memory_type == "preference"
            ][:5],
            "patterns": [
                memory.content for memory in memories 
                if memory.memory_type == "pattern"
            ][:3]
        }
        
        print(f"⚡ Instant context for {user_id}: {len(memories)} memories, profile ready")
        return context
    
    def search_user_knowledge(self, user_id: str, query: str) -> List[Dict[str, Any]]:
        """Search user's knowledge base instantly"""
        self.ui_tracker.mark_ui_activity()
        
        relevant_memories = self.smart_memory.search_memories(user_id, query, limit=10)
        
        return [
            {
                "content": memory.content,
                "type": memory.memory_type,
                "importance": memory.importance,
                "relevance": self._calculate_relevance(memory, query)
            }
            for memory in relevant_memories
        ]
    
    def get_user_summary(self, user_id: str) -> Dict[str, Any]:
        """Get a quick summary of what we know about the user"""
        self.ui_tracker.mark_ui_activity()
        
        profile = self.smart_memory.get_user_profile(user_id)
        stats = self.smart_memory.get_memory_stats(user_id)
        
        return {
            "user_id": user_id,
            "communication_style": profile.communication_style if profile else "unknown",
            "total_memories": stats["total_memories"],
            "memory_breakdown": stats["by_type"],
            "data_ready": stats["ready_memories_count"] > 0,
            "profile_updated": profile.updated_at if profile else None,
            "key_interests": profile.interests[:3] if profile else [],
            "personality_overview": profile.personality_traits[:3] if profile else []
        }
    
    def get_personalization_prompt(self, user_id: str, base_message: str, chat_id: str = None) -> str:
        """
        Generate a personalized prompt with both long-term and short-term memory
        """
        self.ui_tracker.mark_ui_activity()
        
        context = self.get_user_context(user_id)
        print("User Context:", context)
        
        # Build personalization prompt
        personalization = []
        
        # Communication style
        style = context["profile"]["communication_style"]
        if style == "formal":
            personalization.append("Respond in a professional, formal tone.")
        elif style == "casual":
            personalization.append("Respond in a friendly, casual tone.")
        
        # Key facts about user (long-term memory)
        if context["facts"]:
            facts_str = "; ".join(context["facts"][:3])
            personalization.append(f"Remember these facts about the user: {facts_str}")
        
        # User preferences (long-term memory)
        if context["preferences"]:
            prefs_str = "; ".join(context["preferences"][:3])
            personalization.append(f"Keep in mind the user's preferences: {prefs_str}")
        
        # Interests and expertise
        if context["profile"]["interests"]:
            interests = ", ".join(context["profile"]["interests"][:3])
            personalization.append(f"The user is interested in: {interests}")
        
        if context["profile"]["expertise_areas"]:
            expertise = ", ".join(context["profile"]["expertise_areas"][:3])
            personalization.append(f"The user has expertise in: {expertise}")
        
        # Add short-term memory context if chat_id provided
        if chat_id:
            stm_summary = self.smart_memory.get_short_term_memory_summary(user_id, chat_id)
            if stm_summary:
                personalization.append(f"Context from this conversation: {stm_summary}")
        
        # Build final prompt with proper formatting
        if personalization:
            memory_context = '\n'.join(personalization)
            return f"""[MEMORY CONTEXT]
                    {memory_context}

                    [CONVERSATION]
                    User: {base_message}

                    [INSTRUCTIONS]
                    - Respond naturally as yourself while incorporating the memory context
                    - Reference relevant context from this conversation when appropriate
                    - Avoid repeating identical phrases or responses
                    - Give ONE complete, well-formed response"""
        else:
            return f"User: {base_message}"
    
    def get_chat_aware_context(self, user_id: str, chat_id: str) -> Dict[str, Any]:
        """Get context that includes both long-term memories and short-term chat context"""
        self.ui_tracker.mark_ui_activity()
        
        # Get regular context (long-term memory)
        context = self.get_user_context(user_id)
        
        # Add short-term memory from LangGraph
        stm_context = self.smart_memory.get_chat_context_from_langgraph(user_id, chat_id, limit=10)
        stm_summary = self.smart_memory.get_short_term_memory_summary(user_id, chat_id)
        
        # Add short-term memory to context
        context["short_term_memory"] = {
            "chat_id": chat_id,
            "recent_context": stm_context,
            "summary": stm_summary,
            "has_context": bool(stm_context)
        }
        
        print(f"⚡ Chat-aware context for {user_id} (chat: {chat_id}): LTM + STM ready")
        return context
    
    def _calculate_relevance(self, memory: MemoryEntry, query: str) -> float:
        """Calculate relevance score between memory and query"""
        query_lower = query.lower()
        content_lower = memory.content.lower()
        
        # Simple relevance calculation
        relevance = 0.0
        
        # Exact match bonus
        if query_lower in content_lower:
            relevance += 0.8
        
        # Keyword matching
        query_words = set(query_lower.split())
        content_words = set(content_lower.split())
        keyword_words = set(word.lower() for word in memory.keywords)
        
        # Word overlap scoring
        common_words = query_words.intersection(content_words)
        keyword_overlap = query_words.intersection(keyword_words)
        
        if common_words:
            relevance += 0.3 * (len(common_words) / len(query_words))
        
        if keyword_overlap:
            relevance += 0.4 * (len(keyword_overlap) / len(query_words))
        
        # Importance boost
        relevance += memory.importance * 0.2
        
        return min(1.0, relevance)