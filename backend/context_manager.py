"""
Dynamic Context Management for LLM Chat Sessions
Optimizes context length based on system memory and implements conversation summarization.
"""

import psutil
import os
import sys
from typing import Dict, List, Optional, Tuple
import tiktoken
import json
from dataclasses import dataclass
from langchain_core.messages import BaseMessage, HumanMessage, AIMessage, SystemMessage

@dataclass
class ContextConfig:
    """Configuration for context management."""
    max_tokens: int
    reserved_tokens: int  # Tokens to reserve for response
    summarization_threshold: float  # When to trigger summarization (0.8 = 80% of max)
    min_recent_messages: int  # Minimum messages to keep unsummarized
    
class DynamicContextManager:
    """
    Manages conversation context dynamically based on system resources.
    """
    
    def __init__(self, model_name: str = "gpt-3.5-turbo"):
        self.model_name = model_name
        try:
            self.tokenizer = tiktoken.encoding_for_model("gpt-3.5-turbo")  # Fallback encoding
        except:
            self.tokenizer = tiktoken.get_encoding("cl100k_base")  # Default encoding
        
        self.context_config = self._calculate_optimal_context()
        
    def _calculate_optimal_context(self) -> ContextConfig:
        """Calculate optimal context length based on system memory."""
        try:
            # Get system memory info
            memory = psutil.virtual_memory()
            total_memory_gb = memory.total / (1024**3)
            available_memory_gb = memory.available / (1024**3)
            
            print(f"💾 System Memory: {total_memory_gb:.1f}GB total, {available_memory_gb:.1f}GB available")
            
            # Calculate context based on available memory
            if available_memory_gb >= 20:
                # High-end system - use maximum context (your system has 24.6GB available)
                max_tokens = 200000  # Maximum context for your high-memory system
                print("🚀 High-memory system detected - using MAXIMUM context length (200k tokens)")
            elif available_memory_gb >= 16:
                # Mid-range system - good context  
                max_tokens = 128000
                print("⚡ Mid-range system detected - using large context length")
            elif available_memory_gb >= 8:
                # Standard system - moderate context
                max_tokens = 64000
                print("📱 Standard system detected - using moderate context length")
            elif available_memory_gb >= 4:
                # Low memory system - conservative context
                max_tokens = 16000
                print("💧 Low-memory system detected - using conservative context length")
            else:
                # Very low memory - minimal context
                max_tokens = 8000
                print("⚠️ Very low memory detected - using minimal context length")
            
            return ContextConfig(
                max_tokens=max_tokens,
                reserved_tokens=16000,  # Reserve more tokens for longer responses
                summarization_threshold=0.85,  # Higher threshold to use more context before summarizing
                min_recent_messages=20  # Keep more recent messages
            )
            
        except Exception as e:
            print(f"⚠️ Error calculating memory-based context: {e}")
            # Fallback to conservative settings
            return ContextConfig(
                max_tokens=16000,
                reserved_tokens=4000,
                summarization_threshold=0.75,
                min_recent_messages=10
            )
    
    def count_tokens(self, text: str) -> int:
        """Count tokens in text using the tokenizer."""
        try:
            return len(self.tokenizer.encode(text))
        except Exception as e:
            print(f"⚠️ Token counting error: {e}")
            # Fallback to rough estimation (4 chars per token)
            return len(text) // 4
    
    def count_message_tokens(self, messages: List[BaseMessage]) -> int:
        """Count total tokens in a list of messages."""
        total_tokens = 0
        for message in messages:
            if hasattr(message, 'content'):
                total_tokens += self.count_tokens(message.content)
                # Add overhead for message formatting
                total_tokens += 10
        return total_tokens
    
    def should_summarize(self, messages: List[BaseMessage]) -> bool:
        """Determine if conversation should be summarized."""
        if len(messages) <= self.context_config.min_recent_messages:
            return False
            
        current_tokens = self.count_message_tokens(messages)
        threshold_tokens = int(
            (self.context_config.max_tokens - self.context_config.reserved_tokens) 
            * self.context_config.summarization_threshold
        )
        
        return current_tokens > threshold_tokens
    
    def optimize_conversation_context(
        self, 
        messages: List[BaseMessage], 
        system_message: Optional[str] = None
    ) -> Tuple[List[BaseMessage], Dict[str, any]]:
        """
        Optimize conversation context by summarization if needed.
        Returns optimized messages and metadata about the operation.
        """
        metadata = {
            "original_count": len(messages),
            "original_tokens": self.count_message_tokens(messages),
            "summarized": False,
            "summary_created": False
        }
        
        if not self.should_summarize(messages):
            # Add system message if provided
            final_messages = []
            if system_message:
                final_messages.append(SystemMessage(content=system_message))
            final_messages.extend(messages)
            
            metadata.update({
                "final_count": len(final_messages),
                "final_tokens": self.count_message_tokens(final_messages)
            })
            return final_messages, metadata
        
        # Need to summarize - keep recent messages and summarize older ones
        recent_messages = messages[-self.context_config.min_recent_messages:]
        older_messages = messages[:-self.context_config.min_recent_messages]
        
        # Create summary of older messages
        summary_text = self._create_conversation_summary(older_messages)
        summary_message = SystemMessage(content=f"Previous conversation summary: {summary_text}")
        
        # Build final context
        final_messages = []
        if system_message:
            final_messages.append(SystemMessage(content=system_message))
        
        final_messages.append(summary_message)
        final_messages.extend(recent_messages)
        
        metadata.update({
            "summarized": True,
            "summary_created": True,
            "messages_summarized": len(older_messages),
            "messages_kept": len(recent_messages),
            "final_count": len(final_messages),
            "final_tokens": self.count_message_tokens(final_messages),
            "summary_tokens": self.count_tokens(summary_text)
        })
        
        print(f"📝 Context optimized: {metadata['original_count']} → {metadata['final_count']} messages, "
              f"{metadata['original_tokens']} → {metadata['final_tokens']} tokens")
        
        return final_messages, metadata
    
    def _create_conversation_summary(self, messages: List[BaseMessage]) -> str:
        """
        Create a summary of conversation messages.
        This is a simple implementation - can be enhanced with actual LLM summarization.
        """
        if not messages:
            return "No previous conversation."
        
        # Extract key information
        user_messages = []
        ai_messages = []
        
        for msg in messages:
            if isinstance(msg, HumanMessage):
                user_messages.append(msg.content)
            elif isinstance(msg, AIMessage):
                ai_messages.append(msg.content)
        
        # Create structured summary
        summary_parts = []
        
        if user_messages:
            # Get topics/keywords from user messages
            user_topics = self._extract_topics(user_messages)
            summary_parts.append(f"User discussed: {', '.join(user_topics[:5])}")
        
        if ai_messages:
            # Summary of AI responses
            summary_parts.append(f"Assistant provided information and assistance on {len(ai_messages)} topics")
        
        summary_parts.append(f"({len(messages)} messages exchanged)")
        
        return ". ".join(summary_parts) + "."
    
    def _extract_topics(self, messages: List[str]) -> List[str]:
        """Extract key topics from messages (simple keyword extraction)."""
        import re
        from collections import Counter
        
        # Combine all messages
        text = " ".join(messages).lower()
        
        # Remove common words and extract meaningful terms
        stop_words = {
            'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 
            'of', 'with', 'by', 'from', 'up', 'about', 'into', 'through', 'during',
            'before', 'after', 'above', 'below', 'between', 'among', 'i', 'you',
            'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them',
            'is', 'am', 'are', 'was', 'were', 'be', 'been', 'being', 'have',
            'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should',
            'what', 'how', 'when', 'where', 'why', 'can', 'please', 'tell', 'help'
        }
        
        # Extract words (2+ characters, alphabetic)
        words = re.findall(r'\b[a-z]{2,}\b', text)
        meaningful_words = [w for w in words if w not in stop_words and len(w) > 2]
        
        # Get most common words as topics
        word_counts = Counter(meaningful_words)
        return [word for word, count in word_counts.most_common(10)]
    
    def get_context_info(self) -> Dict[str, any]:
        """Get information about current context configuration."""
        memory = psutil.virtual_memory()
        
        return {
            "context_config": {
                "max_tokens": self.context_config.max_tokens,
                "reserved_tokens": self.context_config.reserved_tokens,
                "available_tokens": self.context_config.max_tokens - self.context_config.reserved_tokens,
                "summarization_threshold": self.context_config.summarization_threshold,
                "min_recent_messages": self.context_config.min_recent_messages
            },
            "system_memory": {
                "total_gb": round(memory.total / (1024**3), 1),
                "available_gb": round(memory.available / (1024**3), 1),
                "used_percent": memory.percent
            },
            "model_info": {
                "model_name": self.model_name,
                "tokenizer": self.tokenizer.name if hasattr(self.tokenizer, 'name') else "unknown"
            }
        }

# Global instance
context_manager = DynamicContextManager()

def get_system_optimized_context(
    messages: List[BaseMessage], 
    system_message: Optional[str] = None
) -> Tuple[List[BaseMessage], Dict[str, any]]:
    """
    Get system-optimized conversation context.
    Convenience function for the global context manager.
    """
    return context_manager.optimize_conversation_context(messages, system_message)

def get_context_info() -> Dict[str, any]:
    """Get context manager information."""
    return context_manager.get_context_info()

def should_summarize_conversation(messages: List[BaseMessage]) -> bool:
    """Check if conversation should be summarized."""
    return context_manager.should_summarize(messages)