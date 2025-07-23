"""
Memory Optimization System
==========================

Implements aggressive memory optimization strategies to prevent unlimited growth.
Includes deduplication, compression, importance-based cleanup, and size monitoring.
"""

import sqlite3
import json
import time
import hashlib
import os
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime, timedelta
from dataclasses import dataclass
import chromadb
from chromadb.config import Settings

@dataclass
class MemoryOptimizationConfig:
    """Configuration for memory optimization"""
    # Size limits
    max_total_size_mb: float = 15000.0  # Maximum total memory size
    max_memories_per_user: int = 10000000  # Maximum memories per user
    
    # Cleanup thresholds
    cleanup_trigger_size_mb: float = 14000.0  # Trigger cleanup at this size
    low_importance_threshold: float = 0.3  # Delete memories below this importance
    old_memory_days: int = 30  # Delete old low-importance memories after N days
    
    # Deduplication
    similarity_threshold: float = 0.85  # Merge similar memories above this threshold
    content_hash_threshold: int = 50  # Min characters for content hashing
    
    # Compression
    enable_content_compression: bool = True
    compress_min_length: int = 100  # Compress content longer than this
    
    # Optimization frequency
    auto_optimize_interval_hours: int = 6  # Auto-optimize every N hours


class MemoryOptimizer:
    """
    Advanced memory optimization system with multiple strategies
    """
    
    def __init__(self, db_path: str = "smart_memory.db", vector_db_path: str = "./vector_memory", config: MemoryOptimizationConfig = None):
        self.db_path = db_path
        self.vector_db_path = vector_db_path
        self.config = config or MemoryOptimizationConfig()
        self.last_optimization = 0
        
        # Initialize vector database connection
        self.vector_db = None
        self.collection = None
        self._init_vector_db()
        
        self.optimization_stats = {
            "total_optimizations": 0,
            "memories_deleted": 0,
            "memories_merged": 0,
            "size_saved_mb": 0.0,
            "last_optimization": None
        }
    
    def _init_vector_db(self):
        """Initialize vector database connection"""
        try:
            if os.path.exists(self.vector_db_path):
                self.vector_db = chromadb.PersistentClient(
                    path=self.vector_db_path,
                    settings=Settings(anonymized_telemetry=False)
                )
                try:
                    self.collection = self.vector_db.get_collection("memory_vectors")
                except Exception:
                    # Collection doesn't exist yet
                    self.collection = None
                print(f"🔍 Vector database connected: {self.vector_db_path}")
            else:
                print(f"⚠️ Vector database not found: {self.vector_db_path}")
        except Exception as e:
            print(f"❌ Failed to connect to vector database: {e}")
            self.vector_db = None
            self.collection = None
    
    def get_memory_size_stats(self) -> Dict[str, Any]:
        """Get current memory usage statistics"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Get total memory count and size
            cursor.execute("""
                SELECT 
                    COUNT(*) as total_memories,
                    SUM(LENGTH(content)) as total_content_size,
                    SUM(LENGTH(keywords)) as total_keywords_size,
                    SUM(LENGTH(context)) as total_context_size
                FROM memories
            """)
            
            stats = cursor.fetchone()
            total_memories = stats[0] or 0
            total_size_bytes = (stats[1] or 0) + (stats[2] or 0) + (stats[3] or 0)
            total_size_mb = total_size_bytes / (1024 * 1024)
            
            # Get size by user
            cursor.execute("""
                SELECT 
                    user_id,
                    COUNT(*) as count,
                    SUM(LENGTH(content) + LENGTH(keywords) + LENGTH(context)) as size_bytes
                FROM memories
                GROUP BY user_id
                ORDER BY size_bytes DESC
            """)
            
            user_stats = []
            for row in cursor.fetchall():
                user_stats.append({
                    "user_id": row[0],
                    "memory_count": row[1],
                    "size_mb": row[2] / (1024 * 1024) if row[2] else 0
                })
            
            # Get size by type
            cursor.execute("""
                SELECT 
                    memory_type,
                    COUNT(*) as count,
                    SUM(LENGTH(content) + LENGTH(keywords) + LENGTH(context)) as size_bytes
                FROM memories
                GROUP BY memory_type
                ORDER BY size_bytes DESC
            """)
            
            type_stats = []
            for row in cursor.fetchall():
                type_stats.append({
                    "memory_type": row[0],
                    "memory_count": row[1],
                    "size_mb": row[2] / (1024 * 1024) if row[2] else 0
                })
            
            conn.close()
            
            # Get vector database statistics
            vector_stats = self._get_vector_db_stats()
            
            # Combine SQL and vector database sizes
            total_combined_size_mb = total_size_mb + vector_stats["vector_size_mb"]
            total_combined_size_bytes = total_size_bytes + vector_stats["vector_size_bytes"]
            
            # Check if optimization is needed (based on combined size)
            needs_optimization = (
                total_combined_size_mb > self.config.cleanup_trigger_size_mb or
                any(user["memory_count"] > self.config.max_memories_per_user for user in user_stats)
            )
            
            return {
                "total_memories": total_memories,
                "total_size_mb": round(total_size_mb, 2),  # SQL only (legacy)
                "total_size_bytes": total_size_bytes,  # SQL only (legacy)
                
                # New combined statistics
                "combined_size_mb": round(total_combined_size_mb, 2),
                "combined_size_bytes": total_combined_size_bytes,
                
                # Separate database breakdowns
                "sql_database": {
                    "size_mb": round(total_size_mb, 2),
                    "size_bytes": total_size_bytes,
                    "memory_count": total_memories
                },
                "vector_database": vector_stats,
                
                "user_breakdown": user_stats,
                "type_breakdown": type_stats,
                "needs_optimization": needs_optimization,
                "optimization_recommended": total_combined_size_mb > self.config.cleanup_trigger_size_mb,
                "config": {
                    "max_size_mb": self.config.max_total_size_mb,
                    "cleanup_trigger_mb": self.config.cleanup_trigger_size_mb,
                    "max_memories_per_user": self.config.max_memories_per_user
                },
                "optimization_stats": self.optimization_stats
            }
            
        except Exception as e:
            print(f"❌ Error getting memory size stats: {e}")
            return {"error": str(e)}
    
    def _get_vector_db_stats(self) -> Dict[str, Any]:
        """Get vector database statistics - calculates actual embedding data size"""
        try:
            # Get file system size of vector database
            vector_db_file = os.path.join(self.vector_db_path, "chroma.sqlite3")
            vector_file_size = 0
            vector_embedding_count = 0
            vector_collection_count = 0
            actual_embeddings_size_bytes = 0
            
            if os.path.exists(vector_db_file):
                vector_file_size = os.path.getsize(vector_db_file)
                
                # Get detailed vector database statistics and calculate actual embedding data size
                try:
                    vector_conn = sqlite3.connect(vector_db_file)
                    vector_cursor = vector_conn.cursor()
                    
                    # Count embeddings
                    vector_cursor.execute("SELECT COUNT(*) FROM embeddings")
                    vector_embedding_count = vector_cursor.fetchone()[0] or 0
                    
                    # Count collections
                    vector_cursor.execute("SELECT COUNT(*) FROM collections")
                    vector_collection_count = vector_cursor.fetchone()[0] or 0
                    
                    # Calculate actual size of embedding data (not the whole database)
                    # In ChromaDB, embeddings are stored in the embeddings_queue table with vector BLOB
                    try:
                        # Check if there are vectors in the queue
                        vector_cursor.execute("SELECT AVG(LENGTH(vector)) FROM embeddings_queue WHERE vector IS NOT NULL")
                        avg_result = vector_cursor.fetchone()
                        if avg_result and avg_result[0]:
                            avg_embedding_size = avg_result[0]
                            actual_embeddings_size_bytes = vector_embedding_count * avg_embedding_size
                        else:
                            # Fallback: estimate based on typical embedding size
                            # Typical embedding is ~1536 dimensions * 4 bytes (float32) = ~6KB per embedding
                            actual_embeddings_size_bytes = vector_embedding_count * 6144
                            
                        # Add metadata overhead
                        vector_cursor.execute("SELECT SUM(LENGTH(metadata)) FROM embeddings_queue WHERE metadata IS NOT NULL")
                        metadata_result = vector_cursor.fetchone()
                        if metadata_result and metadata_result[0]:
                            actual_embeddings_size_bytes += metadata_result[0]
                            
                        # Add overhead for IDs and other data
                        actual_embeddings_size_bytes += vector_embedding_count * 100  # ~100 bytes per ID/metadata
                    except Exception as inner_e:
                        print(f"⚠️ Could not calculate exact vector sizes: {inner_e}")
                        # Final fallback: estimate based on embedding count
                        actual_embeddings_size_bytes = vector_embedding_count * 6144
                    
                    vector_conn.close()
                except Exception as e:
                    print(f"⚠️ Could not get detailed vector stats: {e}")
                    # Fallback: estimate based on embedding count
                    # Typical embedding is ~1536 dimensions * 4 bytes (float32) = ~6KB per embedding
                    actual_embeddings_size_bytes = vector_embedding_count * 6144
            
            # Get total directory size for reference (ChromaDB overhead)
            total_directory_size = 0
            if os.path.exists(self.vector_db_path):
                for root, dirs, files in os.walk(self.vector_db_path):
                    total_directory_size += sum(os.path.getsize(os.path.join(root, f)) for f in files)
            
            return {
                "vector_size_mb": actual_embeddings_size_bytes / (1024 * 1024),  # Actual embedding data size
                "vector_size_bytes": actual_embeddings_size_bytes,  # Actual embedding data size
                "embedding_count": vector_embedding_count,
                "collection_count": vector_collection_count,
                "chroma_db_size_mb": total_directory_size / (1024 * 1024),  # Total directory size for reference
                "chroma_db_size_bytes": total_directory_size,
                "available": os.path.exists(self.vector_db_path)
            }
            
        except Exception as e:
            print(f"❌ Error getting vector database stats: {e}")
            return {
                "vector_size_mb": 0,
                "vector_size_bytes": 0,
                "embedding_count": 0,
                "collection_count": 0,
                "chroma_db_size_mb": 0,
                "available": False,
                "error": str(e)
            }
    
    def optimize_memories(self, user_id: str = None, force: bool = False) -> Dict[str, Any]:
        """
        Comprehensive memory optimization using multiple strategies
        """
        start_time = time.time()
        optimization_results = {
            "started_at": datetime.now().isoformat(),
            "user_id": user_id or "all_users",
            "strategies_applied": [],
            "memories_before": 0,
            "memories_after": 0,
            "size_before_mb": 0,
            "size_after_mb": 0,
            "savings_mb": 0,
            "details": {}
        }
        
        try:
            # Get initial stats (using combined SQL + vector size)
            initial_stats = self.get_memory_size_stats()
            optimization_results["memories_before"] = initial_stats["total_memories"]
            optimization_results["size_before_mb"] = initial_stats.get("combined_size_mb", initial_stats["total_size_mb"])
            optimization_results["sql_size_before_mb"] = initial_stats["total_size_mb"]
            optimization_results["vector_size_before_mb"] = initial_stats.get("vector_database", {}).get("vector_size_mb", 0)
            
            # Check if optimization is needed
            if not force and not initial_stats.get("needs_optimization", False):
                optimization_results["skipped"] = "No optimization needed"
                return optimization_results
            
            print(f"🗜️ Starting memory optimization for {user_id or 'all users'}")
            
            # Strategy 1: Remove duplicate content
            dedup_results = self._deduplicate_memories(user_id)
            if dedup_results["merged_count"] > 0:
                optimization_results["strategies_applied"].append("deduplication")
                optimization_results["details"]["deduplication"] = dedup_results
            
            # Strategy 2: Remove low-importance old memories
            cleanup_results = self._cleanup_low_importance_memories(user_id)
            if cleanup_results["deleted_count"] > 0:
                optimization_results["strategies_applied"].append("importance_cleanup")
                optimization_results["details"]["importance_cleanup"] = cleanup_results
            
            # Strategy 3: Compress large content
            compression_results = self._compress_large_content(user_id)
            if compression_results["compressed_count"] > 0:
                optimization_results["strategies_applied"].append("compression")
                optimization_results["details"]["compression"] = compression_results
            
            # Strategy 4: Merge similar memories
            merge_results = self._merge_similar_memories(user_id)
            if merge_results["merged_count"] > 0:
                optimization_results["strategies_applied"].append("similarity_merge")
                optimization_results["details"]["similarity_merge"] = merge_results
            
            # Strategy 5: Archive old memories (if still over limit)
            archive_results = self._archive_old_memories(user_id)
            if archive_results["archived_count"] > 0:
                optimization_results["strategies_applied"].append("archival")
                optimization_results["details"]["archival"] = archive_results
            
            # Strategy 6: Clean up orphaned vector embeddings
            vector_cleanup_results = self._cleanup_orphaned_vectors()
            if vector_cleanup_results["deleted_count"] > 0:
                optimization_results["strategies_applied"].append("vector_cleanup")
                optimization_results["details"]["vector_cleanup"] = vector_cleanup_results
            
            # Get final stats (using combined SQL + vector size)
            final_stats = self.get_memory_size_stats()
            optimization_results["memories_after"] = final_stats["total_memories"]
            optimization_results["size_after_mb"] = final_stats.get("combined_size_mb", final_stats["total_size_mb"])
            optimization_results["sql_size_after_mb"] = final_stats["total_size_mb"]
            optimization_results["vector_size_after_mb"] = final_stats.get("vector_database", {}).get("vector_size_mb", 0)
            optimization_results["savings_mb"] = round(
                optimization_results["size_before_mb"] - optimization_results["size_after_mb"], 2
            )
            optimization_results["sql_savings_mb"] = round(
                optimization_results["sql_size_before_mb"] - optimization_results["sql_size_after_mb"], 2
            )
            optimization_results["vector_savings_mb"] = round(
                optimization_results["vector_size_before_mb"] - optimization_results["vector_size_after_mb"], 2
            )
            
            # Update global stats
            self.optimization_stats["total_optimizations"] += 1
            self.optimization_stats["size_saved_mb"] += optimization_results["savings_mb"]
            self.optimization_stats["last_optimization"] = optimization_results["started_at"]
            
            execution_time = round((time.time() - start_time) * 1000, 2)
            optimization_results["execution_time_ms"] = execution_time
            
            print(f"✅ Memory optimization completed in {execution_time}ms")
            print(f"   Saved {optimization_results['savings_mb']}MB across {len(optimization_results['strategies_applied'])} strategies")
            
            return optimization_results
            
        except Exception as e:
            print(f"❌ Memory optimization failed: {e}")
            optimization_results["error"] = str(e)
            return optimization_results
    
    def _deduplicate_memories(self, user_id: str = None) -> Dict[str, Any]:
        """Remove exact duplicate memories"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Find duplicates by content hash
            where_clause = "WHERE user_id = ?" if user_id else ""
            params = [user_id] if user_id else []
            
            cursor.execute(f"""
                SELECT content, COUNT(*) as count, MIN(id) as keep_id, GROUP_CONCAT(id) as all_ids
                FROM memories
                {where_clause}
                GROUP BY content
                HAVING COUNT(*) > 1
            """, params)
            
            duplicates = cursor.fetchall()
            merged_count = 0
            
            for content, count, keep_id, all_ids in duplicates:
                ids_to_delete = [id for id in all_ids.split(',') if id != keep_id]
                
                if ids_to_delete:
                    # Delete duplicates
                    cursor.execute(f"""
                        DELETE FROM memories 
                        WHERE id IN ({','.join(['?' for _ in ids_to_delete])})
                    """, ids_to_delete)
                    
                    merged_count += len(ids_to_delete)
            
            conn.commit()
            conn.close()
            
            return {
                "merged_count": merged_count,
                "duplicate_groups": len(duplicates)
            }
            
        except Exception as e:
            print(f"❌ Deduplication failed: {e}")
            return {"merged_count": 0, "error": str(e)}
    
    def _cleanup_low_importance_memories(self, user_id: str = None) -> Dict[str, Any]:
        """Remove low-importance old memories"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Calculate cutoff date
            cutoff_date = (datetime.now() - timedelta(days=self.config.old_memory_days)).isoformat()
            
            where_clause = "WHERE user_id = ?" if user_id else ""
            params = [user_id] if user_id else []
            
            # Delete low-importance old memories
            query = f"""
                DELETE FROM memories 
                {where_clause}
                {"AND" if user_id else "WHERE"} importance < ? 
                AND created_at < ?
            """
            params.extend([self.config.low_importance_threshold, cutoff_date])
            
            cursor.execute(query, params)
            deleted_count = cursor.rowcount
            
            conn.commit()
            conn.close()
            
            return {
                "deleted_count": deleted_count,
                "importance_threshold": self.config.low_importance_threshold,
                "cutoff_date": cutoff_date
            }
            
        except Exception as e:
            print(f"❌ Importance cleanup failed: {e}")
            return {"deleted_count": 0, "error": str(e)}
    
    def _compress_large_content(self, user_id: str = None) -> Dict[str, Any]:
        """Compress large memory content to save space"""
        try:
            if not self.config.enable_content_compression:
                return {"compressed_count": 0, "reason": "Compression disabled"}
            
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            where_clause = "WHERE user_id = ?" if user_id else ""
            params = [user_id] if user_id else []
            
            # Find large content to compress
            cursor.execute(f"""
                SELECT id, content
                FROM memories
                {where_clause}
                {"AND" if user_id else "WHERE"} LENGTH(content) > ?
                AND content NOT LIKE '[COMPRESSED]%'
            """, params + [self.config.compress_min_length])
            
            large_memories = cursor.fetchall()
            compressed_count = 0
            
            for memory_id, content in large_memories:
                # Simple compression: summarize very long content
                if len(content) > 500:
                    # Keep first 200 chars + last 100 chars
                    compressed = f"[COMPRESSED] {content[:200]}...{content[-100:]}"
                    
                    cursor.execute("""
                        UPDATE memories 
                        SET content = ?
                        WHERE id = ?
                    """, (compressed, memory_id))
                    
                    compressed_count += 1
            
            conn.commit()
            conn.close()
            
            return {
                "compressed_count": compressed_count,
                "candidates_found": len(large_memories)
            }
            
        except Exception as e:
            print(f"❌ Content compression failed: {e}")
            return {"compressed_count": 0, "error": str(e)}
    
    def _merge_similar_memories(self, user_id: str = None) -> Dict[str, Any]:
        """Merge memories with very similar content"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            where_clause = "WHERE user_id = ?" if user_id else ""
            params = [user_id] if user_id else []
            
            # Get all memories for similarity comparison
            cursor.execute(f"""
                SELECT id, content, memory_type, importance
                FROM memories
                {where_clause}
                ORDER BY importance DESC
            """, params)
            
            memories = cursor.fetchall()
            merged_count = 0
            processed_ids = set()
            
            for i, (id1, content1, type1, importance1) in enumerate(memories):
                if id1 in processed_ids:
                    continue
                
                for j, (id2, content2, type2, importance2) in enumerate(memories[i+1:], i+1):
                    if id2 in processed_ids or type1 != type2:
                        continue
                    
                    # Simple similarity check
                    similarity = self._calculate_similarity(content1, content2)
                    
                    if similarity > self.config.similarity_threshold:
                        # Merge into the higher importance memory
                        if importance1 >= importance2:
                            keep_id, merge_id = id1, id2
                            keep_content = content1
                        else:
                            keep_id, merge_id = id2, id1
                            keep_content = content2
                        
                        # Update the kept memory with combined info
                        combined_content = f"{keep_content} [MERGED: Similar content consolidated]"
                        cursor.execute("""
                            UPDATE memories 
                            SET content = ?, importance = ?
                            WHERE id = ?
                        """, (combined_content, max(importance1, importance2), keep_id))
                        
                        # Delete the merged memory
                        cursor.execute("DELETE FROM memories WHERE id = ?", (merge_id,))
                        
                        processed_ids.add(merge_id)
                        merged_count += 1
            
            conn.commit()
            conn.close()
            
            return {
                "merged_count": merged_count,
                "similarity_threshold": self.config.similarity_threshold
            }
            
        except Exception as e:
            print(f"❌ Similarity merge failed: {e}")
            return {"merged_count": 0, "error": str(e)}
    
    def _archive_old_memories(self, user_id: str = None) -> Dict[str, Any]:
        """Archive old memories to reduce active memory size"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Count current memories
            where_clause = "WHERE user_id = ?" if user_id else ""
            params = [user_id] if user_id else []
            
            cursor.execute(f"SELECT COUNT(*) FROM memories {where_clause}", params)
            current_count = cursor.fetchone()[0]
            
            # Only archive if over limit
            if current_count <= self.config.max_memories_per_user:
                return {"archived_count": 0, "reason": "Under memory limit"}
            
            # Archive oldest low-importance memories
            excess_count = current_count - self.config.max_memories_per_user
            
            cursor.execute(f"""
                DELETE FROM memories
                {where_clause}
                {"AND" if user_id else "WHERE"} id IN (
                    SELECT id FROM memories
                    {where_clause}
                    ORDER BY importance ASC, created_at ASC
                    LIMIT ?
                )
            """, params + [excess_count])
            
            archived_count = cursor.rowcount
            
            conn.commit()
            conn.close()
            
            return {
                "archived_count": archived_count,
                "reason": f"Archived oldest {archived_count} memories to stay under {self.config.max_memories_per_user} limit"
            }
            
        except Exception as e:
            print(f"❌ Memory archival failed: {e}")
            return {"archived_count": 0, "error": str(e)}
    
    def _calculate_similarity(self, text1: str, text2: str) -> float:
        """Simple similarity calculation between two texts"""
        if not text1 or not text2:
            return 0.0
        
        # Simple word-based similarity
        words1 = set(text1.lower().split())
        words2 = set(text2.lower().split())
        
        if not words1 or not words2:
            return 0.0
        
        intersection = words1.intersection(words2)
        union = words1.union(words2)
        
        return len(intersection) / len(union) if union else 0.0
    
    def auto_optimize_if_needed(self, user_id: str = None) -> Optional[Dict[str, Any]]:
        """Automatically optimize if conditions are met"""
        current_time = time.time()
        
        # Check if enough time has passed since last optimization
        if (current_time - self.last_optimization) < (self.config.auto_optimize_interval_hours * 3600):
            return None
        
        # Check if optimization is needed
        stats = self.get_memory_size_stats()
        if not stats.get("needs_optimization", False):
            return None
        
        # Run optimization
        self.last_optimization = current_time
        return self.optimize_memories(user_id=user_id, force=False)
    
    def optimize_user_memories(self, user_id: str, force_optimization: bool = False) -> Dict[str, Any]:
        """Alias for optimize_memories to match endpoint expectations"""
        print(f"🔧 [DEBUG] MemoryOptimizer.optimize_user_memories called with user_id={user_id}, force_optimization={force_optimization}")
        result = self.optimize_memories(user_id=user_id, force=force_optimization)
        print(f"🔧 [DEBUG] MemoryOptimizer.optimize_memories returned: {result}")
        return result
    
    def _cleanup_orphaned_vectors(self) -> Dict[str, Any]:
        """Remove vector embeddings that don't have corresponding SQL memory entries"""
        try:
            if not self.collection:
                return {"deleted_count": 0, "reason": "Vector collection not available"}
            
            # Get all vector IDs
            all_vectors = self.collection.get()
            vector_ids = all_vectors['ids']
            
            if not vector_ids:
                return {"deleted_count": 0, "reason": "No vectors found"}
            
            # Extract memory IDs from vector IDs (format: "mem_{memory_id}")
            vector_memory_ids = []
            vector_id_map = {}
            for vector_id in vector_ids:
                if vector_id.startswith("mem_"):
                    memory_id = vector_id[4:]  # Remove "mem_" prefix
                    vector_memory_ids.append(memory_id)
                    vector_id_map[memory_id] = vector_id
            
            if not vector_memory_ids:
                return {"deleted_count": 0, "reason": "No valid vector memory IDs found"}
            
            # Check which memory IDs exist in SQL database
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Create placeholders for IN clause
            placeholders = ','.join('?' for _ in vector_memory_ids)
            cursor.execute(f"SELECT id FROM memories WHERE id IN ({placeholders})", vector_memory_ids)
            existing_memory_ids = set(row[0] for row in cursor.fetchall())
            conn.close()
            
            # Find orphaned vector embeddings
            orphaned_memory_ids = set(vector_memory_ids) - existing_memory_ids
            orphaned_vector_ids = [vector_id_map[mem_id] for mem_id in orphaned_memory_ids]
            
            if not orphaned_vector_ids:
                return {"deleted_count": 0, "reason": "No orphaned vectors found"}
            
            # Delete orphaned vectors
            deleted_count = 0
            for vector_id in orphaned_vector_ids:
                try:
                    self.collection.delete(ids=[vector_id])
                    deleted_count += 1
                except Exception as e:
                    print(f"⚠️ Failed to delete vector {vector_id}: {e}")
            
            return {
                "deleted_count": deleted_count,
                "total_vectors_checked": len(vector_ids),
                "orphaned_found": len(orphaned_vector_ids),
                "orphaned_memory_ids": list(orphaned_memory_ids)[:10]  # First 10 for logging
            }
            
        except Exception as e:
            print(f"❌ Error cleaning up orphaned vectors: {e}")
            return {"deleted_count": 0, "error": str(e)}


# Global instance
memory_optimizer = MemoryOptimizer()

def get_memory_optimizer() -> MemoryOptimizer:
    """Get the global memory optimizer instance"""
    return memory_optimizer

