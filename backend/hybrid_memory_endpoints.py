"""
Hybrid Memory API Endpoints
===========================

Enhanced memory endpoints supporting:
- Multiple memory types
- Urgency modes (instant, normal, comprehensive)  
- Vector semantic search
- Performance analytics
"""

from fastapi import HTTPException
from pydantic import BaseModel
from typing import Dict, List, Any, Optional
from hybrid_memory_system import get_hybrid_memory, MEMORY_TYPES, URGENCY_MODES, RetrievalResult
import time


class HybridMemorySearchRequest(BaseModel):
    user_id: str
    query: str
    urgency: str = "normal"  # instant, normal, comprehensive
    memory_types: Optional[List[str]] = None
    limit: int = 10


class MemoryStoreRequest(BaseModel):
    user_id: str
    content: str
    memory_type: str = "fact"
    importance: float = 0.5
    category: str = ""
    confidence: float = 0.8
    keywords: List[str] = []
    context: str = ""
    temporal_pattern: str = ""
    metadata: Dict[str, Any] = {}


class MemoryAnalyticsRequest(BaseModel):
    user_id: str
    days: int = 30
    memory_types: Optional[List[str]] = None


def add_hybrid_memory_endpoints(app):
    """Add hybrid memory endpoints to FastAPI app"""
    
    hybrid_memory = get_hybrid_memory()
    
    @app.post("/memory/hybrid_search")
    async def hybrid_memory_search(request: HybridMemorySearchRequest):
        """Advanced memory search with urgency modes and semantic understanding"""
        try:
            start_time = time.time()
            
            # Validate urgency mode
            if request.urgency not in URGENCY_MODES:
                raise HTTPException(
                    status_code=400, 
                    detail=f"Invalid urgency mode. Must be one of: {list(URGENCY_MODES.keys())}"
                )
            
            # Validate memory types
            if request.memory_types:
                invalid_types = [t for t in request.memory_types if t not in MEMORY_TYPES]
                if invalid_types:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Invalid memory types: {invalid_types}. Valid types: {list(MEMORY_TYPES.keys())}"
                    )
            
            # Perform search
            result = await hybrid_memory.retrieve_memories(
                query=request.query,
                user_id=request.user_id,
                urgency=request.urgency,
                memory_types=request.memory_types,
                limit=request.limit
            )
            
            # Convert memories to serializable format
            memories_data = []
            for i, memory in enumerate(result.memories):
                memory_data = {
                    "id": memory.id,
                    "content": memory.content,
                    "memory_type": memory.memory_type,
                    "importance": memory.importance,
                    "confidence": memory.confidence,
                    "category": memory.category,
                    "created_at": memory.created_at,
                    "last_accessed": memory.last_accessed,
                    "access_count": memory.access_count,
                    "keywords": memory.keywords,
                    "context": memory.context,
                    "temporal_pattern": memory.temporal_pattern,
                    "related_memories": memory.related_memories,
                    "metadata": memory.metadata,
                    "relevance_score": result.relevance_scores[i] if i < len(result.relevance_scores) else 0.0
                }
                memories_data.append(memory_data)
            
            return {
                "success": True,
                "memories": memories_data,
                "search_metadata": {
                    "strategy": result.search_strategy,
                    "latency_ms": result.latency_ms,
                    "total_searched": result.total_searched,
                    "urgency_mode": result.urgency_mode,
                    "query": result.search_query
                },
                "count": len(memories_data)
            }
            
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Hybrid memory search failed: {e}")
    
    @app.post("/memory/store_enhanced")
    async def store_enhanced_memory(request: MemoryStoreRequest):
        """Store memory with enhanced metadata and automatic vectorization"""
        try:
            from hybrid_memory_system import MemoryEntry
            import uuid
            from datetime import datetime
            
            # Create enhanced memory entry
            memory = MemoryEntry(
                id=str(uuid.uuid4()),
                user_id=request.user_id,
                content=request.content,
                memory_type=request.memory_type,
                importance=request.importance,
                created_at=datetime.now().isoformat(),
                last_accessed=datetime.now().isoformat(),
                access_count=0,
                keywords=request.keywords,
                context=request.context,
                confidence=request.confidence,
                category=request.category,
                temporal_pattern=request.temporal_pattern,
                related_memories=[],
                metadata=request.metadata
            )
            
            # Store memory
            success = await hybrid_memory.store_memory(memory)
            
            if success:
                return {
                    "success": True,
                    "message": "Enhanced memory stored successfully",
                    "memory_id": memory.id,
                    "memory_type": memory.memory_type,
                    "vectorized": hybrid_memory.embedding_model is not None
                }
            else:
                raise HTTPException(status_code=500, detail="Failed to store memory")
                
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Enhanced memory storage failed: {e}")
    
    @app.get("/memory/types")
    async def get_memory_types():
        """Get all available memory types with descriptions"""
        return {
            "success": True,
            "memory_types": MEMORY_TYPES
        }
    
    @app.get("/memory/urgency_modes")
    async def get_urgency_modes():
        """Get all available urgency modes with descriptions"""
        return {
            "success": True,
            "urgency_modes": URGENCY_MODES
        }
    
    @app.get("/memory/performance_stats")
    async def get_performance_stats():
        """Get performance statistics for different urgency modes"""
        try:
            stats = hybrid_memory.get_performance_stats()
            return {
                "success": True,
                "performance_stats": stats,
                "cache_size": len(hybrid_memory.query_cache),
                "vector_db_available": hybrid_memory.embedding_model is not None
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to get performance stats: {e}")
    
    @app.post("/memory/analytics")
    async def get_memory_analytics(request: MemoryAnalyticsRequest):
        """Get detailed memory analytics for a user"""
        try:
            # Get all memories for analysis
            all_memories_result = await hybrid_memory.retrieve_memories(
                query="",  # Empty query to get all
                user_id=request.user_id,
                urgency="comprehensive",
                memory_types=request.memory_types,
                limit=1000  # Large limit for analytics
            )
            
            memories = all_memories_result.memories
            
            # Analyze memory distribution
            type_distribution = {}
            importance_distribution = {"high": 0, "medium": 0, "low": 0}
            confidence_distribution = {"high": 0, "medium": 0, "low": 0}
            temporal_patterns = {}
            categories = {}
            
            for memory in memories:
                # Type distribution
                type_distribution[memory.memory_type] = type_distribution.get(memory.memory_type, 0) + 1
                
                # Importance distribution
                if memory.importance >= 0.7:
                    importance_distribution["high"] += 1
                elif memory.importance >= 0.4:
                    importance_distribution["medium"] += 1
                else:
                    importance_distribution["low"] += 1
                
                # Confidence distribution
                if memory.confidence >= 0.8:
                    confidence_distribution["high"] += 1
                elif memory.confidence >= 0.5:
                    confidence_distribution["medium"] += 1
                else:
                    confidence_distribution["low"] += 1
                
                # Temporal patterns
                if memory.temporal_pattern:
                    temporal_patterns[memory.temporal_pattern] = temporal_patterns.get(memory.temporal_pattern, 0) + 1
                
                # Categories
                if memory.category:
                    categories[memory.category] = categories.get(memory.category, 0) + 1
            
            # Calculate insights
            total_memories = len(memories)
            avg_importance = sum(m.importance for m in memories) / total_memories if total_memories > 0 else 0
            avg_confidence = sum(m.confidence for m in memories) / total_memories if total_memories > 0 else 0
            
            # Memory health score (0-100)
            health_score = min(100, (
                (total_memories / 100) * 20 +  # Memory quantity (20 points)
                avg_importance * 30 +          # Average importance (30 points)
                avg_confidence * 25 +          # Average confidence (25 points)
                (len(type_distribution) / len(MEMORY_TYPES)) * 25  # Type diversity (25 points)
            ))
            
            return {
                "success": True,
                "analytics": {
                    "total_memories": total_memories,
                    "avg_importance": round(avg_importance, 3),
                    "avg_confidence": round(avg_confidence, 3),
                    "health_score": round(health_score, 1),
                    "type_distribution": type_distribution,
                    "importance_distribution": importance_distribution,
                    "confidence_distribution": confidence_distribution,
                    "temporal_patterns": temporal_patterns,
                    "categories": categories,
                    "insights": [
                        f"You have {total_memories} memories across {len(type_distribution)} different types",
                        f"Average memory importance: {avg_importance:.1%}",
                        f"Memory confidence level: {avg_confidence:.1%}",
                        f"Most common memory type: {max(type_distribution.items(), key=lambda x: x[1])[0] if type_distribution else 'None'}",
                        f"Memory health score: {health_score:.1f}/100"
                    ]
                }
            }
            
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Memory analytics failed: {e}")
    
    @app.get("/memory/suggest_types/{user_id}")
    async def suggest_memory_types(user_id: str, content: str):
        """Suggest appropriate memory type for given content using AI analysis with rule-based fallback"""
        try:
            content_lower = content.lower()
            suggestions = []
            
            # Try LLM-based analysis first
            try:
                llm_suggestions = await _analyze_content_with_llm(content, user_id)
                if llm_suggestions:
                    suggestions.extend(llm_suggestions)
                    print(f"✅ Generated {len(llm_suggestions)} LLM-based suggestions")
            except Exception as e:
                print(f"⚠️ LLM analysis failed, using rule-based fallback: {e}")
            
            # Rule-based fallback suggestions (enhanced)
            rule_suggestions = _get_rule_based_suggestions(content_lower)
            
            # Merge LLM and rule-based suggestions, prioritizing LLM
            if not suggestions:  # Only use rule-based if LLM failed
                suggestions = rule_suggestions
            else:
                # Add unique rule-based suggestions that LLM might have missed
                existing_types = {s["type"] for s in suggestions}
                for rule_suggestion in rule_suggestions:
                    if rule_suggestion["type"] not in existing_types:
                        suggestions.append(rule_suggestion)
            
            # Default suggestion if none found
            if not suggestions:
                suggestions.append({"type": "fact", "confidence": 0.5, "reason": "Default classification"})
            
            # Sort by confidence and limit to top 3
            suggestions.sort(key=lambda x: x["confidence"], reverse=True)
            
            return {
                "success": True,
                "suggestions": suggestions[:3],  # Top 3 suggestions
                "content_analyzed": content[:100] + "..." if len(content) > 100 else content
            }
            
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Memory type suggestion failed: {e}")
    
    @app.get("/memory/system_status")
    async def get_memory_system_status():
        """Get comprehensive memory system status"""
        try:
            performance_stats = hybrid_memory.get_performance_stats()
            
            return {
                "success": True,
                "system_status": {
                    "sql_memory_available": True,
                    "vector_db_available": hybrid_memory.embedding_model is not None,
                    "embedding_model": "all-MiniLM-L6-v2" if hybrid_memory.embedding_model else None,
                    "cache_size": len(hybrid_memory.query_cache),
                    "cache_ttl": hybrid_memory.cache_ttl,
                    "performance_stats": performance_stats,
                    "supported_urgency_modes": list(URGENCY_MODES.keys()),
                    "supported_memory_types": list(MEMORY_TYPES.keys()),
                    "features": {
                        "semantic_search": hybrid_memory.embedding_model is not None,
                        "multi_type_support": True,
                        "urgency_modes": True,
                        "performance_analytics": True,
                        "smart_caching": True,
                        "background_vectorization": True
                    }
                }
            }
            
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"System status check failed: {e}")


# Helper functions for memory type suggestions
async def _analyze_content_with_llm(content: str, user_id: str) -> List[Dict[str, Any]]:
    """Use LLM to analyze content and suggest memory types"""
    try:
        # Import here to avoid circular imports
        from unified_app import current_llm
        
        if not current_llm:
            return []
        
        prompt = f"""Analyze this content and suggest the most appropriate memory type(s):

Content: "{content}"

Available memory types:
- fact: Objective, verifiable information
- preference: Personal likes, dislikes, choices
- pattern: Behavioral patterns, habits, tendencies
- skill: Abilities, expertise levels, competencies
- goal: Objectives, aspirations, planned actions
- event: Specific occurrences, experiences, activities
- emotional: Feelings, emotional states, reactions
- temporal: Time-based patterns, schedules, routines
- context: Environmental factors, circumstances
- meta: Information about information, learning about learning
- social: Relationships, social preferences, communication style
- procedural: How-to knowledge, processes, methods

Return exactly 1-3 suggestions in this JSON format:
[{{"type": "memory_type", "confidence": 0.8, "reason": "Brief explanation"}}]

Respond ONLY with valid JSON array, no other text."""

        # Get LLM response
        response_chunks = []
        for chunk in current_llm.stream(prompt):
            from unified_app import extract_chunk_content
            chunk_content = extract_chunk_content(chunk, "memory_analysis")
            response_chunks.append(chunk_content)
        
        response = "".join(response_chunks).strip()
        
        # Parse JSON response
        import re
        # Extract JSON array from response
        json_match = re.search(r'\[.*\]', response, re.DOTALL)
        if json_match:
            suggestions = json.loads(json_match.group(0))
            
            # Validate suggestions
            valid_suggestions = []
            from hybrid_memory_system import MEMORY_TYPES
            valid_types = set(MEMORY_TYPES.keys())
            
            for suggestion in suggestions:
                if (isinstance(suggestion, dict) and 
                    "type" in suggestion and 
                    "confidence" in suggestion and 
                    "reason" in suggestion and
                    suggestion["type"] in valid_types):
                    
                    valid_suggestions.append({
                        "type": suggestion["type"],
                        "confidence": min(0.95, max(0.5, float(suggestion["confidence"]))),  # Clamp confidence
                        "reason": f"LLM: {suggestion['reason']}"
                    })
            
            return valid_suggestions[:3]  # Max 3 suggestions
        
        return []
        
    except Exception as e:
        print(f"⚠️ LLM memory analysis failed: {e}")
        return []


def _get_rule_based_suggestions(content_lower: str) -> List[Dict[str, Any]]:
    """Enhanced rule-based memory type suggestions as fallback"""
    suggestions = []
    
    # Fact indicators
    if any(word in content_lower for word in ["is", "are", "has", "have", "works at", "lives in", "studied", "graduated"]):
        suggestions.append({"type": "fact", "confidence": 0.8, "reason": "Contains factual statements"})
    
    # Preference indicators
    if any(word in content_lower for word in ["likes", "prefers", "loves", "hates", "enjoys", "dislikes", "favorite"]):
        suggestions.append({"type": "preference", "confidence": 0.9, "reason": "Contains preference statements"})
    
    # Goal indicators
    if any(word in content_lower for word in ["want to", "planning to", "goal", "objective", "aim to", "intend to"]):
        suggestions.append({"type": "goal", "confidence": 0.8, "reason": "Contains goal-oriented language"})
    
    # Skill indicators
    if any(word in content_lower for word in ["expert in", "skilled at", "proficient", "beginner", "advanced", "experienced"]):
        suggestions.append({"type": "skill", "confidence": 0.85, "reason": "Contains skill level indicators"})
    
    # Pattern indicators
    if any(word in content_lower for word in ["usually", "often", "always", "typically", "tends to", "habit"]):
        suggestions.append({"type": "pattern", "confidence": 0.7, "reason": "Contains behavioral patterns"})
    
    # Emotional indicators
    if any(word in content_lower for word in ["feels", "frustrated", "excited", "worried", "happy", "stressed", "emotion"]):
        suggestions.append({"type": "emotional", "confidence": 0.8, "reason": "Contains emotional content"})
    
    # Temporal indicators
    if any(word in content_lower for word in ["daily", "weekly", "monthly", "every", "schedule", "routine", "morning", "evening"]):
        suggestions.append({"type": "temporal", "confidence": 0.75, "reason": "Contains time-based patterns"})
    
    # Event indicators
    if any(word in content_lower for word in ["happened", "occurred", "event", "meeting", "conference", "trip", "vacation"]):
        suggestions.append({"type": "event", "confidence": 0.75, "reason": "Contains event descriptions"})
    
    # Procedural indicators
    if any(word in content_lower for word in ["how to", "steps", "process", "method", "procedure", "instructions"]):
        suggestions.append({"type": "procedural", "confidence": 0.8, "reason": "Contains procedural knowledge"})
    
    # Social indicators
    if any(word in content_lower for word in ["team", "colleague", "friend", "relationship", "communication", "social"]):
        suggestions.append({"type": "social", "confidence": 0.75, "reason": "Contains social context"})
    
    # Context indicators
    if any(word in content_lower for word in ["environment", "location", "context", "situation", "circumstances"]):
        suggestions.append({"type": "context", "confidence": 0.7, "reason": "Contains contextual information"})
    
    # Meta indicators
    if any(word in content_lower for word in ["learning", "remember", "memory", "knowledge", "understanding", "meta"]):
        suggestions.append({"type": "meta", "confidence": 0.7, "reason": "Contains meta-cognitive content"})
    
    return suggestions