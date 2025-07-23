"""
Smart Memory API Endpoints
===========================

Clean, fast endpoints for the new smart memory system.
Provides instant access to pre-fetched data.
"""

from fastapi import HTTPException
from pydantic import BaseModel
from typing import Dict, List, Any, Optional
import json
from datetime import datetime
from instant_memory_api import InstantMemoryAPI
from background_learning_service import get_ui_status_tracker
from smart_memory_system import get_smart_memory


class MemoryContextRequest(BaseModel):
    user_id: str


class MemorySearchRequest(BaseModel):
    user_id: str
    query: str
    limit: int = 10


class UIStatusRequest(BaseModel):
    is_active: bool


class StoreMemoryRequest(BaseModel):
    user_id: str
    content: str
    memory_type: str = "working"
    importance: float = 0.5


class RemoveProfileItemRequest(BaseModel):
    item_type: str
    item_value: str


class ImportMemoriesRequest(BaseModel):
    user_id: str
    memories: List[Dict[str, Any]]
    overwrite_existing: bool = False


def add_smart_memory_endpoints(app):
    """Add smart memory endpoints to FastAPI app"""
    
    instant_memory_api = InstantMemoryAPI()
    ui_tracker = get_ui_status_tracker()
    smart_memory = get_smart_memory()
    
    @app.get("/memory/user_context/{user_id}")
    async def get_user_context(user_id: str):
        """Get instant user context for personalization"""
        try:
            context = instant_memory_api.get_user_context(user_id)
            return {
                "success": True,
                "user_context": context,
                "response_time": "instant"
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to get user context: {e}")
    
    @app.post("/memory/search")
    async def search_memories(request: MemorySearchRequest):
        """Search user memories instantly"""
        try:
            results = instant_memory_api.search_user_knowledge(
                user_id=request.user_id,
                query=request.query
            )
            return {
                "success": True,
                "results": results,
                "count": len(results),
                "query": request.query
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Memory search failed: {e}")
    
    @app.get("/memory/summary/{user_id}")
    async def get_user_summary(user_id: str):
        """Get user memory summary"""
        try:
            summary = instant_memory_api.get_user_summary(user_id)
            return {
                "success": True,
                "summary": summary
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to get summary: {e}")
    
    @app.get("/memory/statistics/{user_id}")
    async def get_memory_statistics(user_id: str):
        """Get memory statistics for user"""
        try:
            stats = smart_memory.get_memory_stats(user_id)
            return {
                "success": True,
                "statistics": stats
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to get stats: {e}")
    
    @app.get("/memory/stats/{user_id}")
    async def get_memory_stats(user_id: str):
        """Get memory statistics for user (legacy endpoint)"""
        try:
            stats = smart_memory.get_memory_stats(user_id)
            return {
                "success": True,
                "statistics": stats
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to get stats: {e}")
    
    @app.post("/ui/status")
    async def set_ui_status(request: UIStatusRequest):
        """Set UI active/inactive status - separate process handles GPU conflicts automatically"""
        try:
            print(f"🔍 Received UI status request: {request.is_active}")
            
            # Use true separate process for background learning
            from separate_process_learning import get_separate_learning
            learning_status = get_separate_learning().get_queue_status()
            
            # Keep legacy compatibility
            ui_tracker.force_ui_status(request.is_active)
            smart_memory.set_ui_status(request.is_active)
            print(f"🔍 UI status updated successfully")
            
            return {
                "success": True,
                "ui_active": request.is_active,
                "background_learning": {
                    "pending_chats": learning_status["pending"],
                    "processed_chats": learning_status["processed"],
                    "worker_running": learning_status["worker_running"]
                },
                "message": f"UI {'opened' if request.is_active else 'closed'} - separate process prevents GPU conflicts"
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to set UI status: {e}")
    
    @app.get("/memory/system_status")
    async def get_memory_system_status():
        """Get overall memory system status"""
        try:
            ui_active = ui_tracker.is_ui_active()
            
            return {
                "success": True,
                "smart_memory_active": smart_memory is not None,
                "ui_active": ui_active,
                "background_learning_enabled": not ui_active,
                "instant_access_ready": True,
                "system_healthy": True
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"System status check failed: {e}",
                "system_healthy": False
            }
    
    @app.get("/memory/debug_pending_chats")
    async def debug_pending_chats():
        """Debug endpoint to check pending chats and trigger processing"""
        try:
            # Simple check for pending chats
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            # Get total chats
            cursor.execute("SELECT COUNT(*) FROM pending_chats")
            total_chats = cursor.fetchone()[0]
            
            # Get unprocessed chats
            cursor.execute("SELECT COUNT(*) FROM pending_chats WHERE processed = 0")
            unprocessed_chats = cursor.fetchone()[0]
            
            # Get recent chats
            cursor.execute("""
                SELECT user_id, chat_id, created_at, processed
                FROM pending_chats
                ORDER BY created_at DESC
                LIMIT 10
            """)
            recent_chats = cursor.fetchall()
            
            conn.close()
            
            return {
                "success": True,
                "total_chats": total_chats,
                "unprocessed_chats": unprocessed_chats,
                "ui_active": smart_memory.is_ui_active,
                "recent_chats": [
                    {
                        "user_id": row[0],
                        "chat_id": row[1],
                        "created_at": row[2],
                        "processed": bool(row[3])
                    }
                    for row in recent_chats
                ]
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Debug check failed: {e}"
            }
    
    @app.post("/memory/force_process_chats")
    async def force_process_chats():
        """Force process pending chats (for debugging)"""
        try:
            print("🔧 Manual trigger: Processing pending chats")
            smart_memory.process_pending_chats_now()
            return {
                "success": True,
                "message": "Processing triggered"
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Force processing failed: {e}"
            }
    
    @app.get("/memory/list/{user_id}")
    async def list_user_memories(user_id: str, limit: int = 50, offset: int = 0, memory_type: str = None):
        """List memories for a user with pagination support for infinite scroll"""
        try:
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            # Build query based on filters
            base_query = """
                SELECT id, content, memory_type, importance, created_at, keywords, context
                FROM memories 
                WHERE user_id = ?
            """
            params = [user_id]
            
            if memory_type:
                base_query += " AND memory_type = ?"
                params.append(memory_type)
            
            base_query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
            params.extend([limit, offset])
            
            cursor.execute(base_query, params)
            memories = cursor.fetchall()
            
            # Get total count
            count_query = "SELECT COUNT(*) FROM memories WHERE user_id = ?"
            count_params = [user_id]
            if memory_type:
                count_query += " AND memory_type = ?"
                count_params.append(memory_type)
            
            cursor.execute(count_query, count_params)
            total_count = cursor.fetchone()[0]
            
            conn.close()
            
            formatted_memories = []
            for memory in memories:
                formatted_memories.append({
                    "id": memory[0],
                    "content": memory[1],
                    "memory_type": memory[2],
                    "importance": memory[3],
                    "created_at": memory[4],
                    "keywords": memory[5],
                    "context_preview": memory[6][:100] + "..." if len(memory[6]) > 100 else memory[6]
                })
            
            return {
                "success": True,
                "user_id": user_id,
                "total_memories": total_count,
                "showing": len(formatted_memories),
                "offset": offset,
                "limit": limit,
                "memory_type_filter": memory_type,
                "memories": formatted_memories
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to fetch memories: {e}"
            }
    
    @app.delete("/memory/delete/{memory_id}")
    async def delete_memory(memory_id: str):
        """Delete a specific memory by ID from both SQL and vector databases"""
        try:
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            # Check if memory exists
            cursor.execute("SELECT user_id FROM memories WHERE id = ?", (memory_id,))
            result = cursor.fetchone()
            
            if not result:
                return {
                    "success": False,
                    "error": f"Memory with ID {memory_id} not found"
                }
            
            user_id = result[0]
            
            # Delete the memory from SQL
            cursor.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
            deleted_count = cursor.rowcount
            
            conn.commit()
            conn.close()
            
            # Remove from vector database if available
            vector_deleted = False
            try:
                from memory_optimizer import get_memory_optimizer
                optimizer = get_memory_optimizer()
                
                # Delete from ChromaDB
                if optimizer.vector_db:
                    collection = optimizer.vector_db.get_or_create_collection("memory_vectors")
                    try:
                        collection.delete(ids=[f"mem_{memory_id}"])
                        vector_deleted = True
                        print(f"✅ Deleted memory {memory_id} from vector database")
                    except Exception as e:
                        print(f"⚠️ ChromaDB deletion error for {memory_id}: {e}")
                else:
                    print("⚠️ Vector database not available - SQL deletion succeeded")
                        
            except Exception as e:
                print(f"⚠️ Could not access vector database: {e}")
            
            if deleted_count > 0:
                return {
                    "success": True,
                    "message": f"Successfully deleted memory {memory_id} from SQL{' and vector database' if vector_deleted else ' database'}",
                    "deleted_count": deleted_count,
                    "vector_deleted": vector_deleted
                }
            else:
                return {
                    "success": False,
                    "error": f"Failed to delete memory {memory_id}"
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": f"Error deleting memory: {e}"
            }
    
    @app.delete("/memory/clear_all_memories/{user_id}")
    async def clear_all_memories(user_id: str, memory_type: str = None):
        """Clear all memories for a user from both SQL and vector databases (use with caution!)"""
        try:
            print("running sql clear")
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            # Get memory IDs before deletion for vector database cleanup
            if memory_type:
                cursor.execute("SELECT id FROM memories WHERE user_id = ? AND memory_type = ?", (user_id, memory_type))
            else:
                cursor.execute("SELECT id FROM memories WHERE user_id = ?", (user_id,))
            
            memory_ids = [row[0] for row in cursor.fetchall()]
            
            # Delete from SQL database
            if memory_type:
                cursor.execute("DELETE FROM memories WHERE user_id = ? AND memory_type = ?", (user_id, memory_type))
                deleted_count = cursor.rowcount
                message = f"Deleted {deleted_count} {memory_type} memories for {user_id}"
            else:
                cursor.execute("DELETE FROM memories WHERE user_id = ?", (user_id,))
                deleted_count = cursor.rowcount
                message = f"Deleted {deleted_count} memories for {user_id}"
            
            conn.commit()
            conn.close()
            print("running vector clear")
            # Clear from vector database if available
            vector_deleted = 0
            try:
                from memory_optimizer import get_memory_optimizer
                optimizer = get_memory_optimizer()
                
                # Delete from ChromaDB
                if optimizer.vector_db:
                    collections = optimizer.vector_db.list_collections()
                    try:
                        for name in (c.name if hasattr(c, "name") else c for c in collections):
                            col = optimizer.vector_db.get_or_create_collection(name)

                            # ask for *no* payload fields → response still includes "ids"
                            all_ids = col.get(ids=None, include=[])["ids"]

                            if all_ids:
                                col.delete(ids=all_ids)           # remove every vector in the collection
                                vector_deleted += len(all_ids)
                                print(f"Deleted {len(all_ids)} vectors from {name}")
                    except Exception as e:
                        print(f"⚠️ ChromaDB deletion error: {e}")
                else:
                    print("⚠️ Vector database not available")
                        
            except Exception as e:
                print(f"⚠️ Could not access vector database: {e}")
            
            return {
                "success": True,
                "message": f"{message}. Also removed {vector_deleted} vectors from vector database.",
                "deleted_count": deleted_count,
                "vector_deleted": vector_deleted
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to clear memories: {e}"
            }
    
    @app.get("/memory/insights/{user_id}")
    async def get_memory_insights(user_id: str):
        """Get memory insights for a user"""
        try:
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            # Get memory stats by type
            cursor.execute("""
                SELECT memory_type, COUNT(*) as count, AVG(importance) as avg_importance
                FROM memories 
                WHERE user_id = ? 
                GROUP BY memory_type
            """, (user_id,))
            type_stats = cursor.fetchall()
            
            # Get total memories
            cursor.execute("SELECT COUNT(*) FROM memories WHERE user_id = ?", (user_id,))
            total_memories = cursor.fetchone()[0]
            
            # Get common keywords
            cursor.execute("""
                SELECT keywords FROM memories 
                WHERE user_id = ? AND keywords IS NOT NULL AND keywords != ''
                LIMIT 50
            """, (user_id,))
            keyword_rows = cursor.fetchall()
            
            # Parse keywords and find most common
            all_keywords = []
            for row in keyword_rows:
                if row[0]:
                    keywords = row[0].split(',')
                    all_keywords.extend([k.strip() for k in keywords if k.strip()])
            
            # Count keyword frequency
            keyword_counts = {}
            for keyword in all_keywords:
                keyword_counts[keyword] = keyword_counts.get(keyword, 0) + 1
            
            # Get top interests/domains
            top_keywords = sorted(keyword_counts.items(), key=lambda x: x[1], reverse=True)[:10]
            interests = [kw[0] for kw in top_keywords[:5]]
            
            conn.close()
            
            # Build insights response
            insights_data = {
                "user_id": user_id,
                "personality_profile": {
                    "communication_style": "direct",
                    "learning_preference": "interactive",
                    "detail_level": "comprehensive"
                },
                "communication_style": "direct",
                "knowledge_domains": interests[:3] if interests else ["general", "programming", "technology"],
                "interests": interests if interests else ["learning", "AI", "technology"],
                "interaction_patterns": {
                    "questions": total_memories // 3,
                    "preferences": len([t for t in type_stats if t[0] == "preference"]),
                    "facts": len([t for t in type_stats if t[0] == "fact"])
                },
                "memory_efficiency": min(1.0, total_memories / 100.0 * 0.8 + 0.2),
                "recommendations": [
                    "Continue engaging with technical topics",
                    "Share more preferences for better personalization",
                    "Explore new knowledge domains",
                    "Ask follow-up questions for deeper understanding"
                ]
            }
            
            return {
                "success": True,
                "insights": insights_data
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to generate insights: {e}"
            }
    
    @app.post("/memory/optimize/{user_id}")
    async def optimize_memory(user_id: str, force: bool = False):
        """Force optimize memory using memory_optimizer.py with vector database support"""
        print(f"🔧 [DEBUG] Backend: optimize_memory called with user_id={user_id}, force={force}")
        try:
            print(f"🔧 [DEBUG] Backend: Importing memory_optimizer...")
            from memory_optimizer import get_memory_optimizer
            
            print(f"🔧 [DEBUG] Backend: Getting memory optimizer instance...")
            # Get the memory optimizer instance
            optimizer = get_memory_optimizer()
            
            print(f"🔧 [DEBUG] Backend: Running optimization with force_optimization={force}...")
            # Force run the optimization
            results = optimizer.optimize_user_memories(user_id, force_optimization=force)
            
            print(f"🔧 [DEBUG] Backend: Optimization completed with results: {results}")
            
            response = {
                "success": True,
                "message": f"Memory optimization completed for user {user_id}",
                "results": results,
                "force_optimization": force
            }
            print(f"🔧 [DEBUG] Backend: Returning response: {response}")
            return response
            
        except Exception as e:
            print(f"❌ [DEBUG] Backend: Memory optimization failed with error: {e}")
            print(f"❌ [DEBUG] Backend: Exception type: {type(e)}")
            import traceback
            print(f"❌ [DEBUG] Backend: Full traceback: {traceback.format_exc()}")
            return {
                "success": False,
                "error": f"Memory optimization failed: {e}"
            }
    
    @app.post("/memory/store")
    async def store_memory(request: StoreMemoryRequest):
        """Store a new memory"""
        try:
            # Store memory using smart memory system
            memory_id = smart_memory.store_memory(
                user_id=request.user_id,
                content=request.content,
                memory_type=request.memory_type,
                importance=request.importance,
                keywords=[],
                context=""
            )
            
            return {
                "success": True,
                "message": "Memory stored successfully",
                "memory_id": memory_id
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to store memory: {e}"
            }
    
    @app.get("/user_memory_profile/{user_id}")
    async def get_user_memory_profile(user_id: str):
        """Get user memory profile for compatibility"""
        try:
            # Get basic memory stats
            stats = smart_memory.get_memory_stats(user_id)
            
            return {
                "user_id": user_id,
                "profile": {
                    "communication_style": "direct",
                    "total_interactions": stats["total_memories"]
                },
                "recent_memories": [],
                "preferences": {
                    "response_style": "comprehensive",
                    "detail_level": "high"
                },
                "personality_traits": ["analytical", "curious", "direct"],
                "total_memories": stats["total_memories"]
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to get memory profile: {e}"
            }
    
    @app.get("/profiles/all_users")
    async def get_all_user_profiles():
        """Get all user profiles for management"""
        try:
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT user_id, communication_style, interests, expertise_areas, 
                       personality_traits, preferences, updated_at
                FROM user_profiles
                ORDER BY updated_at DESC
            """)
            profiles = cursor.fetchall()
            conn.close()
            
            formatted_profiles = []
            for profile in profiles:
                formatted_profiles.append({
                    "user_id": profile[0],
                    "communication_style": profile[1],
                    "interests": json.loads(profile[2]) if profile[2] else [],
                    "expertise_areas": json.loads(profile[3]) if profile[3] else [],
                    "personality_traits": json.loads(profile[4]) if profile[4] else [],
                    "preferences": json.loads(profile[5]) if profile[5] else {},
                    "updated_at": profile[6]
                })
            
            return {
                "success": True,
                "profiles": formatted_profiles,
                "count": len(formatted_profiles)
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to get user profiles: {e}"
            }
    
    @app.delete("/profiles/{user_id}")
    async def delete_user_profile(user_id: str):
        """Delete a user profile"""
        try:
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("DELETE FROM user_profiles WHERE user_id = ?", (user_id,))
            deleted_count = cursor.rowcount
            
            conn.commit()
            conn.close()
            
            return {
                "success": True,
                "message": f"Profile for {user_id} deleted successfully",
                "deleted_count": deleted_count
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to delete profile: {e}"
            }
    
    @app.delete("/profiles/clear_all")
    async def clear_all_profiles():
        """Clear all user profiles"""
        try:
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            cursor.execute("DELETE FROM user_profiles")
            deleted_count = cursor.rowcount
            
            conn.commit()
            conn.close()
            
            return {
                "success": True,
                "message": f"All {deleted_count} profiles deleted successfully",
                "deleted_count": deleted_count
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to clear profiles: {e}"
            }
    
    @app.delete("/profiles/{user_id}/remove_item")
    async def remove_profile_item(user_id: str, request: RemoveProfileItemRequest):
        """Remove a specific item from a user profile"""
        try:
            item_type = request.item_type
            item_value = request.item_value
            
            if not item_type or not item_value:
                return {
                    "success": False,
                    "error": "item_type and item_value are required"
                }
            
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            # Get current profile
            cursor.execute("SELECT * FROM user_profiles WHERE user_id = ?", (user_id,))
            profile = cursor.fetchone()
            
            if not profile:
                conn.close()
                return {
                    "success": False,
                    "error": f"Profile for user {user_id} not found"
                }
            
            # Extract current data
            current_interests = json.loads(profile[2]) if profile[2] else []
            current_expertise = json.loads(profile[3]) if profile[3] else []
            current_traits = json.loads(profile[4]) if profile[4] else []
            current_preferences = json.loads(profile[5]) if profile[5] else {}
            
            # Remove item based on type
            if item_type == "interest" and item_value in current_interests:
                current_interests.remove(item_value)
                updated_interests = json.dumps(current_interests)
                cursor.execute(
                    "UPDATE user_profiles SET interests = ?, updated_at = datetime('now') WHERE user_id = ?",
                    (updated_interests, user_id)
                )
            elif item_type == "expertise" and item_value in current_expertise:
                current_expertise.remove(item_value)
                updated_expertise = json.dumps(current_expertise)
                cursor.execute(
                    "UPDATE user_profiles SET expertise_areas = ?, updated_at = datetime('now') WHERE user_id = ?",
                    (updated_expertise, user_id)
                )
            elif item_type == "trait" and item_value in current_traits:
                current_traits.remove(item_value)
                updated_traits = json.dumps(current_traits)
                cursor.execute(
                    "UPDATE user_profiles SET personality_traits = ?, updated_at = datetime('now') WHERE user_id = ?",
                    (updated_traits, user_id)
                )
            elif item_type == "preference" and item_value in current_preferences:
                del current_preferences[item_value]
                updated_preferences = json.dumps(current_preferences)
                cursor.execute(
                    "UPDATE user_profiles SET preferences = ?, updated_at = datetime('now') WHERE user_id = ?",
                    (updated_preferences, user_id)
                )
            else:
                conn.close()
                return {
                    "success": False,
                    "error": f"Item '{item_value}' not found in {item_type}"
                }
            
            conn.commit()
            conn.close()
            
            return {
                "success": True,
                "message": f"Removed '{item_value}' from {item_type} for user {user_id}",
                "item_type": item_type,
                "item_value": item_value
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to remove profile item: {e}"
            }
    
    @app.get("/memory/statistics/{user_id}")
    async def get_memory_statistics(user_id: str):
        """Get comprehensive memory statistics for a user"""
        try:
            # Use the enhanced statistics function
            stats = smart_memory.get_memory_stats(user_id)
            
            return {
                "success": True,
                "statistics": stats
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to get memory statistics: {e}"
            }
    
    @app.post("/memory/import")
    async def import_memories(request: ImportMemoriesRequest):
        """Import memories from exported JSON file"""
        try:
            imported_count = 0
            skipped_count = 0
            error_count = 0
            
            conn = smart_memory._get_db_connection()
            cursor = conn.cursor()
            
            for memory_data in request.memories:
                try:
                    # Extract memory fields
                    memory_id = memory_data.get("id")
                    content = memory_data.get("content", "")
                    memory_type = memory_data.get("memory_type", "fact")
                    importance = float(memory_data.get("importance", 0.5))
                    timestamp = memory_data.get("timestamp", datetime.now().isoformat())
                    user_id = memory_data.get("user_id", request.user_id)
                    metadata = memory_data.get("metadata", {})
                    
                    # Skip if content is empty
                    if not content.strip():
                        skipped_count += 1
                        continue
                    
                    # Check if memory already exists
                    if memory_id:
                        cursor.execute("SELECT id FROM memories WHERE id = ?", (memory_id,))
                        existing = cursor.fetchone()
                        
                        if existing and not request.overwrite_existing:
                            skipped_count += 1
                            continue
                        elif existing and request.overwrite_existing:
                            # Update existing memory
                            cursor.execute("""
                                UPDATE memories 
                                SET content = ?, memory_type = ?, importance = ?, 
                                    updated_at = ?, metadata = ?
                                WHERE id = ?
                            """, (content, memory_type, importance, timestamp, 
                                  json.dumps(metadata), memory_id))
                            imported_count += 1
                            continue
                    
                    # Generate new ID if not provided or doesn't exist
                    if not memory_id:
                        import uuid
                        memory_id = str(uuid.uuid4())
                    
                    # Insert new memory
                    cursor.execute("""
                        INSERT INTO memories 
                        (id, user_id, content, memory_type, importance, created_at, 
                         last_accessed, access_count, keywords, context, confidence, 
                         category, temporal_pattern, metadata)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        memory_id, user_id, content, memory_type, importance,
                        timestamp, timestamp, 1, "", "", 0.8, "", "", 
                        json.dumps(metadata)
                    ))
                    
                    imported_count += 1
                    
                    # Also store in vector database if hybrid memory is available
                    try:
                        from hybrid_memory_system import HybridMemorySystem
                        hybrid_memory = HybridMemorySystem()
                        await hybrid_memory.store_vector(memory_id, content, metadata)
                    except Exception as e:
                        print(f"⚠️ Could not store in vector database: {e}")
                    
                except Exception as e:
                    print(f"❌ Error importing memory: {e}")
                    error_count += 1
            
            conn.commit()
            conn.close()
            
            return {
                "success": True,
                "imported_count": imported_count,
                "skipped_count": skipped_count,
                "error_count": error_count,
                "message": f"Successfully imported {imported_count} memories, skipped {skipped_count}, errors {error_count}"
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to import memories: {e}"
            }
    
    @app.get("/memory/background_learning_status")
    async def get_background_learning_status():
        """Get status of separate process background learning"""
        try:
            from separate_process_learning import get_separate_learning
            learning = get_separate_learning()
            status = learning.get_queue_status()
            
            return {
                "success": True,
                "queue_status": status,
                "architecture": "separate_process",
                "description": "Background learning runs in completely separate Python process"
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to get background learning status: {e}"
            }