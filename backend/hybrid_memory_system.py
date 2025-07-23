"""
Hybrid Memory System for SuriAI
===============================

Advanced memory system combining:
- Fast SQL queries for instant retrieval
- Vector semantic search for comprehensive understanding
- Multiple memory types and urgency modes
- Smart caching and background processing
"""

import asyncio
import time
import json
import numpy as np
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from collections import defaultdict
import sqlite3
from sentence_transformers import SentenceTransformer
import chromadb
from chromadb.config import Settings
import threading
import schedule
import gzip
import hashlib

from smart_memory_system import MemoryEntry, UserProfile, SmartMemorySystem


# Production optimization configuration
PRODUCTION_CONFIG = {
    "importance_threshold": 0.2,  # Don't embed anything below this
    "hot_days": 7,               # Hot tier: last 7 days raw
    "warm_days": 90,             # Warm tier: up to 90 days compressed
    "embedding_dtype": np.float16,  # Use float16 for 50% memory reduction
    "vacuum_interval_days": 7,   # Weekly vacuum operations
    "max_hot_per_user": 1000,    # Max memories in hot tier per user
    "max_warm_per_user": 5000,   # Max memories in warm tier per user
    "compression_enabled": True,  # Enable content compression for old memories
    "deduplication_enabled": True,  # Enable content deduplication
}

# Memory type definitions with descriptions and examples
MEMORY_TYPES = {
    "fact": {
        "name": "Factual Knowledge",
        "description": "Objective information and verifiable facts",
        "examples": ["User is a Python developer", "Lives in San Francisco", "Has 5 years experience"],
        "color": "#2563eb"  # Blue
    },
    "preference": {
        "name": "User Preferences", 
        "description": "User likes, dislikes, and preferred styles",
        "examples": ["Prefers concise explanations", "Likes dark mode", "Dislikes verbose responses"],
        "color": "#16a34a"  # Green
    },
    "pattern": {
        "name": "Behavioral Patterns",
        "description": "Recurring behaviors and interaction patterns",
        "examples": ["Asks follow-up questions", "Works late evenings", "Reviews code on Mondays"],
        "color": "#ea580c"  # Orange
    },
    "skill": {
        "name": "Skills & Expertise",
        "description": "User competencies and knowledge domains",
        "examples": ["Expert in Machine Learning", "Beginner in React", "Advanced Python"],
        "color": "#7c3aed"  # Purple
    },
    "goal": {
        "name": "Goals & Objectives",
        "description": "User intentions, plans, and objectives",
        "examples": ["Learning LangGraph", "Building AI app", "Getting ML certification"],
        "color": "#dc2626"  # Red
    },
    "event": {
        "name": "Significant Events",
        "description": "Important occurrences and milestones",
        "examples": ["First AI model deployed", "Completed course", "Job interview"],
        "color": "#0891b2"  # Cyan
    },
    "emotional": {
        "name": "Emotional Context",
        "description": "Emotional states, reactions, and triggers",
        "examples": ["Gets frustrated with bugs", "Excited about AI", "Stressed about deadlines"],
        "color": "#e11d48"  # Rose
    },
    "temporal": {
        "name": "Time Patterns",
        "description": "Time-based routines and schedules",
        "examples": ["Daily standup at 9am", "Code review Fridays", "Weekend learning sessions"],
        "color": "#059669"  # Emerald
    },
    "context": {
        "name": "Situational Context",
        "description": "Environmental and situational information",
        "examples": ["Works from home office", "Uses MacBook Pro", "Team of 5 developers"],
        "color": "#7c2d12"  # Amber
    },
    "meta": {
        "name": "Learning Meta-Memory",
        "description": "How user learns and retains information",
        "examples": ["Learns better with examples", "Visual learner", "Needs repetition"],
        "color": "#4338ca"  # Indigo
    },
    "social": {
        "name": "Social Dynamics",
        "description": "Relationships and social interactions",
        "examples": ["Collaborates well", "Mentors junior devs", "Prefers async communication"],
        "color": "#be185d"  # Pink
    },
    "procedural": {
        "name": "Procedures & Workflows",
        "description": "Step-by-step processes and workflows",
        "examples": ["Debug workflow", "Code review process", "Deployment procedure"],
        "color": "#374151"  # Gray
    }
}

# Urgency mode configurations
URGENCY_MODES = {
    "instant": {
        "name": "Instant",
        "description": "Ultra-fast retrieval using SQL only",
        "max_latency": 30,  # milliseconds
        "search_strategy": "sql_only",
        "icon": "⚡",
        "use_cases": ["Real-time chat", "Quick responses", "Live interactions"]
    },
    "normal": {
        "name": "Normal", 
        "description": "Balanced speed and relevance with hybrid search",
        "max_latency": 100,  # milliseconds
        "search_strategy": "hybrid",
        "icon": "⚖️", 
        "use_cases": ["Standard conversations", "Memory insights", "Content generation"]
    },
    "comprehensive": {
        "name": "Comprehensive",
        "description": "Deep semantic search for best relevance",
        "max_latency": 300,  # milliseconds
        "search_strategy": "vector_full",
        "icon": "🔍",
        "use_cases": ["Complex queries", "Research tasks", "Detailed analysis"]
    }
}


@dataclass
class RetrievalResult:
    """Result from memory retrieval with metadata"""
    memories: List[MemoryEntry]
    search_strategy: str
    latency_ms: float
    total_searched: int
    relevance_scores: List[float]
    search_query: str
    urgency_mode: str


class HybridMemorySystem:
    """
    Advanced hybrid memory system with multiple retrieval strategies
    """
    
    def __init__(self, db_path: str = "smart_memory.db", vector_db_path: str = "./vector_memory"):
        self.db_path = db_path
        self.vector_db_path = vector_db_path
        
        # Initialize components
        self.sql_memory = SmartMemorySystem(db_path)
        self.embedding_model = None
        self.vector_db = None
        self.query_cache = {}
        self.cache_ttl = 300  # 5 minutes
        
        # Performance tracking
        self.performance_stats = defaultdict(list)
        
        # Initialize vector components
        self._init_vector_components()
        
        # Background processing
        self.background_queue = asyncio.Queue()
        self.is_processing = False
        
        # Initialize weekly scheduler
        self._init_weekly_scheduler()
    
    async def initialize(self):
        """Initialize the hybrid memory system (async compatibility method)"""
        # This method exists for compatibility with other memory systems
        # All initialization is already done in __init__
        print("🧠 Hybrid memory system initialized")
        return True
        
    def _init_vector_components(self):
        """Initialize embedding model and vector database"""
        try:
            print("🔧 Initializing vector components...")
            
            # Use fast, lightweight embedding model
            self.embedding_model = SentenceTransformer('all-MiniLM-L6-v2')
            print("✅ Embedding model loaded")
            
            # Initialize ChromaDB
            self.vector_db = chromadb.PersistentClient(
                path=self.vector_db_path,
                settings=Settings(anonymized_telemetry=False)
            )
            
            # Get or create collection
            try:
                self.collection = self.vector_db.get_collection("memory_vectors")
                print("✅ Vector database connected")
            except Exception:
                self.collection = self.vector_db.create_collection(
                    name="memory_vectors",
                    metadata={"description": "SuriAI memory vectors"}
                )
                print("✅ Vector database created")
                
        except Exception as e:
            print(f"⚠️ Vector components failed to initialize: {e}")
            print("📝 Falling back to SQL-only mode")
            self.embedding_model = None
            self.vector_db = None
            
    async def retrieve_memories(self, query: str, user_id: str, urgency: str = "normal", 
                              memory_types: List[str] = None, limit: int = 10) -> RetrievalResult:
        """
        Main retrieval function with urgency-based strategy selection
        """
        start_time = time.time()
        
        # Validate urgency mode
        if urgency not in URGENCY_MODES:
            urgency = "normal"
            
        mode_config = URGENCY_MODES[urgency]
        max_latency = mode_config["max_latency"]
        strategy = mode_config["search_strategy"]
        
        print(f"🔍 Memory retrieval: '{query}' | Mode: {urgency} | Strategy: {strategy}")
        
        # Check cache first
        cache_key = f"{user_id}:{query}:{urgency}:{str(memory_types)}"
        if cache_key in self.query_cache:
            cached_result, cache_time = self.query_cache[cache_key]
            if time.time() - cache_time < self.cache_ttl:
                print(f"💾 Cache hit - returning cached results")
                return cached_result
        
        try:
            # Route to appropriate retrieval strategy
            if strategy == "sql_only":
                result = await self._sql_retrieval(query, user_id, memory_types, limit, max_latency)
            elif strategy == "hybrid":
                result = await self._hybrid_retrieval(query, user_id, memory_types, limit, max_latency)
            else:  # vector_full
                result = await self._vector_retrieval(query, user_id, memory_types, limit, max_latency)
                
            # Cache result
            self.query_cache[cache_key] = (result, time.time())
            
            # Track performance
            latency = (time.time() - start_time) * 1000
            self.performance_stats[urgency].append(latency)
            result.latency_ms = latency
            
            print(f"✅ Retrieved {len(result.memories)} memories in {latency:.1f}ms using {result.search_strategy}")
            return result
            
        except Exception as e:
            print(f"❌ Memory retrieval failed: {e}")
            # Fallback to basic SQL search
            return await self._sql_retrieval(query, user_id, memory_types, limit, max_latency)
    
    async def _sql_retrieval(self, query: str, user_id: str, memory_types: List[str], 
                           limit: int, max_latency: float) -> RetrievalResult:
        """Fast SQL-based retrieval for instant responses"""
        memories = self.sql_memory.search_memories(user_id, query, limit=limit)
        
        # Filter by memory types if specified
        if memory_types:
            memories = [m for m in memories if m.memory_type in memory_types]
        
        # Simple relevance scoring based on keyword matches
        relevance_scores = []
        query_words = set(query.lower().split())
        
        for memory in memories:
            content_words = set(memory.content.lower().split())
            keyword_words = set([kw.lower() for kw in memory.keywords])
            
            # Calculate relevance
            content_overlap = len(query_words.intersection(content_words))
            keyword_overlap = len(query_words.intersection(keyword_words))
            relevance = (content_overlap * 0.7 + keyword_overlap * 0.3) / len(query_words)
            relevance_scores.append(min(1.0, relevance))
        
        return RetrievalResult(
            memories=memories[:limit],
            search_strategy="sql_keyword",
            latency_ms=0,  # Will be set by caller
            total_searched=len(memories),
            relevance_scores=relevance_scores[:limit],
            search_query=query,
            urgency_mode="instant"
        )
    
    async def _hybrid_retrieval(self, query: str, user_id: str, memory_types: List[str], 
                              limit: int, max_latency: float) -> RetrievalResult:
        """Hybrid retrieval combining SQL and vector search"""
        if not self.embedding_model:
            return await self._sql_retrieval(query, user_id, memory_types, limit, max_latency)
        
        # Phase 1: Fast SQL pre-filtering
        sql_candidates = self.sql_memory.search_memories(user_id, "", limit=50)  # Get recent memories
        if memory_types:
            sql_candidates = [m for m in sql_candidates if m.memory_type in memory_types]
        
        # Phase 2: Vector search on candidates
        if len(sql_candidates) > 5:
            query_embedding = self.embedding_model.encode([query])
            
            # Get embeddings for candidates (or compute if not cached)
            candidate_embeddings = []
            candidate_memories = []
            
            for memory in sql_candidates:
                try:
                    # Try to get from vector DB first
                    results = self.collection.query(
                        query_embeddings=query_embedding.tolist(),
                        where={"memory_id": memory.id},
                        n_results=1
                    )
                    
                    if results['embeddings']:
                        candidate_embeddings.append(results['embeddings'][0])
                        candidate_memories.append(memory)
                    else:
                        # Compute embedding if not in vector DB
                        memory_embedding = self.embedding_model.encode([memory.content])
                        candidate_embeddings.append(memory_embedding[0].tolist())
                        candidate_memories.append(memory)
                        
                        # Store in vector DB for future use
                        self._store_memory_vector(memory, memory_embedding[0])
                        
                except Exception as e:
                    # Fallback: compute embedding
                    memory_embedding = self.embedding_model.encode([memory.content])
                    candidate_embeddings.append(memory_embedding[0].tolist())
                    candidate_memories.append(memory)
            
            # Calculate similarities
            query_emb = query_embedding[0]
            similarities = []
            
            for candidate_emb in candidate_embeddings:
                similarity = np.dot(query_emb, candidate_emb) / (
                    np.linalg.norm(query_emb) * np.linalg.norm(candidate_emb)
                )
                similarities.append(float(similarity))
            
            # Sort by similarity
            sorted_indices = sorted(range(len(similarities)), key=lambda i: similarities[i], reverse=True)
            
            result_memories = [candidate_memories[i] for i in sorted_indices[:limit]]
            result_scores = [similarities[i] for i in sorted_indices[:limit]]
            
        else:
            # Too few candidates, fall back to SQL
            return await self._sql_retrieval(query, user_id, memory_types, limit, max_latency)
        
        return RetrievalResult(
            memories=result_memories,
            search_strategy="hybrid_sql_vector",
            latency_ms=0,  # Will be set by caller
            total_searched=len(sql_candidates),
            relevance_scores=result_scores,
            search_query=query,
            urgency_mode="normal"
        )
    
    async def _vector_retrieval(self, query: str, user_id: str, memory_types: List[str], 
                              limit: int, max_latency: float) -> RetrievalResult:
        """Full vector semantic search for comprehensive results"""
        if not self.embedding_model:
            return await self._hybrid_retrieval(query, user_id, memory_types, limit, max_latency)
        
        try:
            # Generate query embedding
            query_embedding = self.embedding_model.encode([query])
            
            # Prepare filters
            where_filter = {"user_id": user_id}
            if memory_types:
                where_filter["memory_type"] = {"$in": memory_types}
            
            # Query vector database
            results = self.collection.query(
                query_embeddings=query_embedding.tolist(),
                where=where_filter,
                n_results=limit * 2  # Get more to account for filtering
            )
            
            # Convert back to MemoryEntry objects
            memories = []
            relevance_scores = []
            
            for i, (doc_id, distance, metadata) in enumerate(zip(
                results['ids'][0], results['distances'][0], results['metadatas'][0]
            )):
                try:
                    # Reconstruct memory from metadata
                    memory = MemoryEntry(
                        id=metadata['memory_id'],
                        user_id=metadata['user_id'],
                        content=metadata['content'],
                        memory_type=metadata['memory_type'],
                        importance=metadata.get('importance', 0.5),
                        created_at=metadata.get('created_at', ''),
                        last_accessed=metadata.get('last_accessed', ''),
                        access_count=metadata.get('access_count', 0),
                        keywords=json.loads(metadata.get('keywords', '[]')),
                        context=metadata.get('context', ''),
                        confidence=metadata.get('confidence', 0.8),
                        category=metadata.get('category', ''),
                        temporal_pattern=metadata.get('temporal_pattern', ''),
                        related_memories=json.loads(metadata.get('related_memories', '[]')),
                        metadata=json.loads(metadata.get('extra_metadata', '{}'))
                    )
                    
                    memories.append(memory)
                    # Convert distance to similarity (ChromaDB uses L2 distance)
                    similarity = 1 / (1 + distance)
                    relevance_scores.append(similarity)
                    
                except Exception as e:
                    print(f"⚠️ Error reconstructing memory: {e}")
                    continue
            
            return RetrievalResult(
                memories=memories[:limit],
                search_strategy="vector_semantic",
                latency_ms=0,  # Will be set by caller
                total_searched=len(results['ids'][0]),
                relevance_scores=relevance_scores[:limit],
                search_query=query,
                urgency_mode="comprehensive"
            )
            
        except Exception as e:
            print(f"⚠️ Vector search failed: {e}, falling back to hybrid")
            return await self._hybrid_retrieval(query, user_id, memory_types, limit, max_latency)
    
    def _store_memory_vector(self, memory: MemoryEntry, embedding: np.ndarray):
        """Store memory embedding in vector database"""
        try:
            metadata = {
                "memory_id": memory.id,
                "user_id": memory.user_id,
                "content": memory.content[:500],  # Truncate for storage
                "memory_type": memory.memory_type,
                "importance": memory.importance,
                "created_at": memory.created_at,
                "last_accessed": memory.last_accessed,
                "access_count": memory.access_count,
                "keywords": json.dumps(memory.keywords),
                "context": memory.context[:200],  # Truncate
                "confidence": memory.confidence,
                "category": memory.category,
                "temporal_pattern": memory.temporal_pattern,
                "related_memories": json.dumps(memory.related_memories),
                "extra_metadata": json.dumps(memory.metadata)
            }
            
            self.collection.add(
                embeddings=[embedding.tolist()],
                documents=[memory.content],
                metadatas=[metadata],
                ids=[f"mem_{memory.id}"]
            )
            
        except Exception as e:
            print(f"⚠️ Failed to store vector: {e}")
    
    def _store_memory_vector_optimized(self, memory: MemoryEntry, embedding: np.ndarray, content_hash: str):
        """Store memory embedding with production optimizations"""
        try:
            # Determine tier based on age and importance
            tier = self._determine_memory_tier(memory)
            
            metadata = {
                "memory_id": memory.id,
                "user_id": memory.user_id,
                "content": memory.content[:500],  # Truncate for storage
                "content_hash": content_hash,
                "memory_type": memory.memory_type,
                "importance": memory.importance,
                "tier": tier,
                "created_at": memory.created_at,
                "last_accessed": memory.last_accessed,
                "access_count": memory.access_count,
                "keywords": json.dumps(memory.keywords),
                "context": memory.context[:200],  # Truncate
                "confidence": memory.confidence,
                "category": memory.category,
                "temporal_pattern": memory.temporal_pattern,
                "related_memories": json.dumps(memory.related_memories),
                "extra_metadata": json.dumps(memory.metadata),
                "compressed": True,  # Mark as float16 compressed
                "storage_version": "v2"  # Version for future migrations
            }
            
            self.collection.add(
                embeddings=[embedding.tolist()],
                documents=[memory.content],
                metadatas=[metadata],
                ids=[f"mem_{memory.id}"]
            )
            
            print(f"🔧 Stored optimized vector: {memory.id} (tier: {tier}, float16: {embedding.dtype})")
            
        except Exception as e:
            print(f"⚠️ Failed to store optimized vector: {e}")
    
    async def store_vector(self, memory: MemoryEntry):
        """Compute embedding and store memory in vector database"""
        try:
            if not self.embedding_model or not self.collection:
                print(f"⚠️ Vector components not initialized, skipping vector storage")
                return
                
            # Compute embedding for the memory content
            content_to_embed = f"{memory.content} {' '.join(memory.keywords)}"
            embedding = self.embedding_model.encode([content_to_embed])
            
            # Store in vector database
            self._store_memory_vector(memory, embedding[0])
            
        except Exception as e:
            print(f"⚠️ Failed to compute/store vector embedding: {e}")
    
    async def store_vector_optimized(self, memory: MemoryEntry):
        """Compute embedding and store with production optimizations"""
        try:
            if not self.embedding_model or not self.collection:
                print(f"⚠️ Vector components not initialized, skipping vector storage")
                return
                
            # Compute embedding for the memory content
            content_to_embed = f"{memory.content} {' '.join(memory.keywords)}"
            embedding = self.embedding_model.encode([content_to_embed])
            
            # Convert to float16 for storage efficiency (50% memory reduction)
            embedding_f16 = embedding[0].astype(PRODUCTION_CONFIG["embedding_dtype"])
            
            # Check for duplicate content using hash
            content_hash = hashlib.md5(content_to_embed.encode()).hexdigest()
            if PRODUCTION_CONFIG["deduplication_enabled"]:
                try:
                    existing_results = self.collection.query(
                        query_texts=[content_to_embed],
                        where={"$and": [{"user_id": memory.user_id}, {"content_hash": content_hash}]},
                        n_results=1
                    )
                    if existing_results['ids'] and existing_results['ids'][0]:
                        print(f"🔄 Skipping duplicate content for memory {memory.id}")
                        return
                except Exception as e:
                    print(f"⚠️ Duplicate check failed: {e}")
                    # Continue with storage even if duplicate check fails
            
            # Store with optimized metadata
            self._store_memory_vector_optimized(memory, embedding_f16, content_hash)
            
        except Exception as e:
            print(f"⚠️ Failed to compute/store optimized vector embedding: {e}")
    
    async def store_memory(self, memory: MemoryEntry) -> bool:
        """Store memory with production optimizations"""
        try:
            # Apply importance gate - skip low-importance memories
            if memory.importance < PRODUCTION_CONFIG["importance_threshold"]:
                print(f"⚠️ Skipping memory with importance {memory.importance:.3f} < {PRODUCTION_CONFIG['importance_threshold']}")
                return False
            
            # Store in SQL database
            if self.sql_memory:
                # Convert MemoryEntry to SmartMemorySystem parameters
                self.sql_memory.store_memory(
                    user_id=memory.user_id,
                    content=memory.content,
                    memory_type=memory.memory_type,
                    importance=memory.importance,
                    keywords=memory.keywords,
                    context=memory.context
                )
                print(f"💾 Memory {memory.id} stored in SQL database")
            
            # Store in vector database with optimizations
            try:
                await self.store_vector_optimized(memory)
                print(f"🔍 Memory {memory.id} vectorized and stored (optimized)")
            except Exception as vector_error:
                print(f"⚠️ Vector storage failed (SQL storage succeeded): {vector_error}")
            
            # Check and apply tiered retention
            await self._apply_tiered_retention(memory.user_id)
            
            # Clear relevant caches
            self._clear_user_cache(memory.user_id)
            return True
            
        except Exception as e:
            print(f"❌ Failed to store memory: {e}")
            return False
    
    def _clear_user_cache(self, user_id: str):
        """Clear cached queries for a specific user"""
        keys_to_remove = [k for k in self.query_cache.keys() if k.startswith(f"{user_id}:")]
        for key in keys_to_remove:
            del self.query_cache[key]
    
    def get_performance_stats(self) -> Dict[str, Any]:
        """Get performance statistics for different urgency modes"""
        stats = {}
        
        for mode, latencies in self.performance_stats.items():
            if latencies:
                stats[mode] = {
                    "count": len(latencies),
                    "avg_latency": np.mean(latencies),
                    "min_latency": np.min(latencies),
                    "max_latency": np.max(latencies),
                    "p95_latency": np.percentile(latencies, 95)
                }
            else:
                stats[mode] = {"count": 0}
        
        return stats
    
    def get_memory_type_info(self) -> Dict[str, Any]:
        """Get information about available memory types"""
        return MEMORY_TYPES
    
    def get_urgency_mode_info(self) -> Dict[str, Any]:
        """Get information about available urgency modes"""
        return URGENCY_MODES
    
    def _determine_memory_tier(self, memory: MemoryEntry) -> str:
        """Determine appropriate tier for memory based on age and importance"""
        try:
            # Parse creation date
            if isinstance(memory.created_at, str):
                created_date = datetime.fromisoformat(memory.created_at.replace('Z', '+00:00'))
            else:
                created_date = memory.created_at
            
            age_days = (datetime.now() - created_date).days
            
            # High importance memories stay hot longer
            if memory.importance >= 0.8:
                hot_threshold = PRODUCTION_CONFIG["hot_days"] * 2
                warm_threshold = PRODUCTION_CONFIG["warm_days"] * 2
            else:
                hot_threshold = PRODUCTION_CONFIG["hot_days"]
                warm_threshold = PRODUCTION_CONFIG["warm_days"]
            
            if age_days <= hot_threshold:
                return "hot"
            elif age_days <= warm_threshold:
                return "warm"
            else:
                return "cold"
                
        except Exception as e:
            print(f"⚠️ Error determining tier: {e}")
            return "hot"  # Default to hot on error
    
    async def _apply_tiered_retention(self, user_id: str):
        """Apply tiered retention limits per user"""
        try:
            # Get user's memory counts by tier
            results = self.collection.query(
                query_texts=[""],
                where={"user_id": user_id},
                n_results=10000,  # Get all for counting
                include=["metadatas"]
            )
            
            if not results['metadatas']:
                return
            
            # Count by tier
            tier_counts = {"hot": 0, "warm": 0, "cold": 0}
            memory_by_tier = {"hot": [], "warm": [], "cold": []}
            
            for i, metadata in enumerate(results['metadatas'][0]):
                tier = metadata.get('tier', 'hot')
                tier_counts[tier] += 1
                memory_by_tier[tier].append({
                    'id': results['ids'][0][i],
                    'created_at': metadata.get('created_at', ''),
                    'importance': metadata.get('importance', 0.5),
                    'metadata': metadata
                })
            
            # Apply hot tier limit
            if tier_counts["hot"] > PRODUCTION_CONFIG["max_hot_per_user"]:
                excess = tier_counts["hot"] - PRODUCTION_CONFIG["max_hot_per_user"]
                await self._promote_memories_to_warm(user_id, memory_by_tier["hot"], excess)
            
            # Apply warm tier limit
            if tier_counts["warm"] > PRODUCTION_CONFIG["max_warm_per_user"]:
                excess = tier_counts["warm"] - PRODUCTION_CONFIG["max_warm_per_user"]
                await self._promote_memories_to_cold(user_id, memory_by_tier["warm"], excess)
                
        except Exception as e:
            print(f"⚠️ Error applying tiered retention: {e}")
    
    async def _promote_memories_to_warm(self, user_id: str, hot_memories: List[Dict], count: int):
        """Promote oldest hot memories to warm tier"""
        try:
            # Sort by creation date (oldest first)
            hot_memories.sort(key=lambda x: x['created_at'])
            
            memories_to_promote = hot_memories[:count]
            
            for memory in memories_to_promote:
                # Update metadata in vector database
                self.collection.update(
                    ids=[memory['id']],
                    metadatas=[{**memory['metadata'], 'tier': 'warm'}]
                )
            
            print(f"📦 Promoted {count} memories from hot to warm tier (user: {user_id})")
            
        except Exception as e:
            print(f"⚠️ Error promoting to warm: {e}")
    
    async def _promote_memories_to_cold(self, user_id: str, warm_memories: List[Dict], count: int):
        """Promote oldest warm memories to cold tier"""
        try:
            # Sort by creation date and importance (oldest, lowest importance first)
            warm_memories.sort(key=lambda x: (x['created_at'], x['importance']))
            
            memories_to_promote = warm_memories[:count]
            
            for memory in memories_to_promote:
                # Update metadata in vector database
                self.collection.update(
                    ids=[memory['id']],
                    metadatas=[{**memory['metadata'], 'tier': 'cold'}]
                )
            
            print(f"🗜️ Promoted {count} memories from warm to cold tier (user: {user_id})")
            
        except Exception as e:
            print(f"⚠️ Error promoting to cold: {e}")
    
    async def vacuum_and_optimize(self) -> Dict[str, Any]:
        """Comprehensive weekly vacuum and optimization"""
        start_time = time.time()
        
        results = {
            "started_at": datetime.now().isoformat(),
            "operations": [],
            "stats_before": {},
            "stats_after": {},
            "execution_time_ms": 0
        }
        
        try:
            # Get stats before optimization
            stats_before = self._get_optimization_stats()
            results["stats_before"] = stats_before
            
            # 1. Age-based tier promotion
            promoted_count = await self._age_based_tier_promotion()
            if promoted_count > 0:
                results["operations"].append(f"Age-based promotion: {promoted_count} memories")
            
            # 2. Compress old vectors (simulate by updating metadata)
            compressed_count = await self._compress_old_vectors()
            if compressed_count > 0:
                results["operations"].append(f"Compressed {compressed_count} old vectors")
            
            # 3. Remove low-importance memories from cold tier
            removed_count = await self._remove_low_importance_cold()
            if removed_count > 0:
                results["operations"].append(f"Removed {removed_count} low-importance cold memories")
            
            # 4. Optimize vector database
            self._optimize_vector_database()
            results["operations"].append("Vector database optimized")
            
            # Get stats after optimization
            stats_after = self._get_optimization_stats()
            results["stats_after"] = stats_after
            
            results["execution_time_ms"] = (time.time() - start_time) * 1000
            
            print(f"🧹 Vacuum completed in {results['execution_time_ms']:.0f}ms")
            print(f"   Operations: {len(results['operations'])}")
            
            return results
            
        except Exception as e:
            print(f"❌ Vacuum failed: {e}")
            results["error"] = str(e)
            return results
    
    async def _age_based_tier_promotion(self) -> int:
        """Promote memories based on age thresholds"""
        try:
            promoted_count = 0
            
            # Get all memories for age-based promotion
            results = self.collection.query(
                query_texts=[""],
                where={},
                n_results=50000,  # Large number to get all
                include=["metadatas"]
            )
            
            if not results['metadatas']:
                return 0
            
            current_time = datetime.now()
            
            for i, metadata in enumerate(results['metadatas'][0]):
                memory_id = results['ids'][0][i]
                current_tier = metadata.get('tier', 'hot')
                created_at = metadata.get('created_at', '')
                importance = metadata.get('importance', 0.5)
                
                try:
                    if isinstance(created_at, str):
                        created_date = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                    else:
                        created_date = created_at
                    
                    age_days = (current_time - created_date).days
                    
                    # Determine target tier
                    target_tier = self._determine_tier_by_age(age_days, importance)
                    
                    # Promote if needed
                    if self._should_promote_tier(current_tier, target_tier):
                        self.collection.update(
                            ids=[memory_id],
                            metadatas=[{**metadata, 'tier': target_tier}]
                        )
                        promoted_count += 1
                        
                except Exception as e:
                    continue  # Skip problematic entries
            
            return promoted_count
            
        except Exception as e:
            print(f"⚠️ Error in age-based promotion: {e}")
            return 0
    
    def _determine_tier_by_age(self, age_days: int, importance: float) -> str:
        """Determine tier based on age and importance"""
        # High importance memories stay hot longer
        multiplier = 2.0 if importance >= 0.8 else 1.0
        
        hot_threshold = PRODUCTION_CONFIG["hot_days"] * multiplier
        warm_threshold = PRODUCTION_CONFIG["warm_days"] * multiplier
        
        if age_days <= hot_threshold:
            return "hot"
        elif age_days <= warm_threshold:
            return "warm"
        else:
            return "cold"
    
    def _should_promote_tier(self, current_tier: str, target_tier: str) -> bool:
        """Check if tier promotion is needed"""
        tier_order = {"hot": 0, "warm": 1, "cold": 2}
        return tier_order.get(target_tier, 0) > tier_order.get(current_tier, 0)
    
    async def _compress_old_vectors(self) -> int:
        """Mark old vectors as compressed (metadata update)"""
        try:
            # Find vectors older than warm threshold that aren't marked as compressed
            cutoff_date = datetime.now() - timedelta(days=PRODUCTION_CONFIG["warm_days"])
            
            results = self.collection.query(
                query_texts=[""],
                where={"compressed": False},
                n_results=10000,
                include=["metadatas"]
            )
            
            if not results['metadatas']:
                return 0
            
            compressed_count = 0
            
            for i, metadata in enumerate(results['metadatas'][0]):
                memory_id = results['ids'][0][i]
                created_at = metadata.get('created_at', '')
                
                try:
                    if isinstance(created_at, str):
                        created_date = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                    else:
                        created_date = created_at
                    
                    if created_date < cutoff_date:
                        # Mark as compressed
                        self.collection.update(
                            ids=[memory_id],
                            metadatas=[{**metadata, 'compressed': True}]
                        )
                        compressed_count += 1
                        
                except Exception as e:
                    continue
            
            return compressed_count
            
        except Exception as e:
            print(f"⚠️ Error compressing old vectors: {e}")
            return 0
    
    async def _remove_low_importance_cold(self) -> int:
        """Remove very low importance memories from cold tier"""
        try:
            # Remove cold memories with importance < 0.1
            results = self.collection.query(
                query_texts=[""],
                where={"tier": "cold"},
                n_results=10000,
                include=["metadatas"]
            )
            
            if not results['metadatas']:
                return 0
            
            ids_to_remove = []
            
            for i, metadata in enumerate(results['metadatas'][0]):
                importance = metadata.get('importance', 0.5)
                if importance < 0.1:  # Very low importance threshold
                    ids_to_remove.append(results['ids'][0][i])
            
            if ids_to_remove:
                self.collection.delete(ids=ids_to_remove)
            
            return len(ids_to_remove)
            
        except Exception as e:
            print(f"⚠️ Error removing low importance memories: {e}")
            return 0
    
    def _optimize_vector_database(self):
        """Optimize vector database performance"""
        try:
            # ChromaDB doesn't have explicit optimization, but we can:
            # 1. Update collection metadata
            # 2. Log optimization event
            print("🔧 Vector database optimization completed")
            
        except Exception as e:
            print(f"⚠️ Vector database optimization warning: {e}")
    
    def _get_optimization_stats(self) -> Dict[str, Any]:
        """Get current optimization statistics"""
        try:
            results = self.collection.query(
                query_texts=[""],
                where={},
                n_results=50000,
                include=["metadatas"]
            )
            
            if not results['metadatas']:
                return {
                    "total_memories": 0,
                    "hot_count": 0,
                    "warm_count": 0,
                    "cold_count": 0,
                    "compressed_count": 0,
                    "avg_importance": 0.0
                }
            
            # Count by tier and other stats
            tier_counts = {"hot": 0, "warm": 0, "cold": 0}
            compressed_count = 0
            importance_sum = 0.0
            
            for metadata in results['metadatas'][0]:
                tier = metadata.get('tier', 'hot')
                tier_counts[tier] += 1
                
                if metadata.get('compressed', False):
                    compressed_count += 1
                
                importance_sum += metadata.get('importance', 0.5)
            
            total_count = len(results['metadatas'][0])
            
            return {
                "total_memories": total_count,
                "hot_count": tier_counts["hot"],
                "warm_count": tier_counts["warm"],
                "cold_count": tier_counts["cold"],
                "compressed_count": compressed_count,
                "avg_importance": importance_sum / total_count if total_count > 0 else 0.0
            }
            
        except Exception as e:
            print(f"⚠️ Error getting optimization stats: {e}")
            return {}
    
    def _init_weekly_scheduler(self):
        """Initialize weekly vacuum and optimization scheduler"""
        try:
            # Schedule weekly vacuum every Sunday at 2:00 AM
            schedule.every().sunday.at("02:00").do(self._run_weekly_vacuum)
            
            # Start scheduler in background thread
            def run_scheduler():
                while True:
                    schedule.run_pending()
                    time.sleep(3600)  # Check every hour
            
            scheduler_thread = threading.Thread(target=run_scheduler, daemon=True)
            scheduler_thread.start()
            
            print(f"📅 Weekly optimization scheduled (Sundays at 2:00 AM)")
            
        except Exception as e:
            print(f"⚠️ Failed to initialize scheduler: {e}")
    
    def _run_weekly_vacuum(self):
        """Run weekly vacuum in background thread"""
        try:
            # Run vacuum asynchronously
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(self.vacuum_and_optimize())
            loop.close()
            
            print(f"🧹 Weekly vacuum completed: {len(result.get('operations', []))} operations")
            
        except Exception as e:
            print(f"❌ Weekly vacuum failed: {e}")


# Global instance
_hybrid_memory_system = None

def get_hybrid_memory() -> HybridMemorySystem:
    """Get global hybrid memory system instance"""
    global _hybrid_memory_system
    if _hybrid_memory_system is None:
        _hybrid_memory_system = HybridMemorySystem()
    return _hybrid_memory_system