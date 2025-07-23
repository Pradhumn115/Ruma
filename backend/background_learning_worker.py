#!/usr/bin/env python3
"""
Background Learning Worker Process
=================================

Runs in separate process to avoid GPU conflicts with main UI.
Processes learning queue continuously with proper resource management.
"""

import sqlite3
import json
import time
import sys
import os
import argparse
import signal
from typing import List, Dict, Any

class BackgroundLearningWorker:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.running = True
        self.smart_memory = None
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
    
    def signal_handler(self, signum, frame):
        print(f"🛑 Worker received signal {signum}, shutting down...")
        self.running = False
    
    def initialize_memory_system(self):
        """Initialize smart memory system in worker process"""
        try:
            # Import here to avoid issues in main process
            from smart_memory_system import get_smart_memory
            self.smart_memory = get_smart_memory()
            print("✅ Worker: Smart memory system initialized")
            return True
        except Exception as e:
            print(f"❌ Worker: Failed to initialize memory system: {e}")
            return False
    
    def run(self):
        """Main worker loop"""
        print(f"🚀 Background learning worker started (PID: {os.getpid()})")
        
        # Initialize memory system
        if not self.initialize_memory_system():
            print("❌ Worker: Failed to initialize, exiting")
            return
        
        # Main processing loop
        idle_count = 0
        while self.running:
            try:
                processed = self.process_batch()
                
                if processed == 0:
                    # No work, wait a bit
                    idle_count += 1
                    if idle_count % 6 == 0:  # Every 60 seconds (10s * 6)
                        print(f"💤 Worker: Waiting for new chats to process...")
                    time.sleep(10)
                else:
                    # Brief pause between batches
                    idle_count = 0
                    time.sleep(2)
                    
            except Exception as e:
                print(f"❌ Worker: Error in main loop: {e}")
                time.sleep(5)  # Wait before retrying
        
        print("✅ Worker: Shutdown complete")
    
    def process_batch(self) -> int:
        """Process one batch of learning queue"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Get next pending item
            cursor.execute("""
                SELECT id, user_id, chat_id, messages 
                FROM learning_queue 
                WHERE processed = 0 
                ORDER BY created_at ASC 
                LIMIT 1
            """)
            
            row = cursor.fetchone()
            if not row:
                conn.close()
                return 0
            
            queue_id, user_id, chat_id, messages_json = row
            messages = json.loads(messages_json)
            
            print(f"🧠 Worker: Processing chat {chat_id} (user: {user_id})")
            
            # Get remaining queue count
            cursor.execute("SELECT COUNT(*) FROM learning_queue WHERE processed = 0")
            remaining = cursor.fetchone()[0]
            print(f"📊 Background learning progress: {remaining} chats remaining in queue")
            
            # Mark as being processed
            cursor.execute("""
                UPDATE learning_queue 
                SET process_started_at = CURRENT_TIMESTAMP 
                WHERE id = ?
            """, (queue_id,))
            conn.commit()
            conn.close()
            
            # Process the chat directly with database operations
            try:
                print(f"⚡ Worker: Starting memory extraction for chat {chat_id}")
                
                # Move chat to SmartMemorySystem's pending_chats table for processing
                smart_conn = sqlite3.connect('smart_memory.db')
                smart_cursor = smart_conn.cursor()
                
                # Insert into pending_chats table
                smart_cursor.execute("""
                    INSERT OR REPLACE INTO pending_chats 
                    (id, user_id, chat_id, messages, created_at, processed)
                    VALUES (?, ?, ?, ?, datetime('now'), 0)
                """, (f"{user_id}_{chat_id}_{int(time.time())}", user_id, chat_id, json.dumps(messages)))
                
                smart_conn.commit()
                smart_conn.close()
                
                print(f"✅ Worker: Moved chat {chat_id} to SmartMemorySystem pending_chats table")
                
                # Mark as completed
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute("""
                    UPDATE learning_queue 
                    SET processed = 1 
                    WHERE id = ?
                """, (queue_id,))
                conn.commit()
                conn.close()
                
                return 1
                
            except Exception as e:
                print(f"❌ Worker: Error processing chat {chat_id}: {e}")
                
                # Mark as failed (processed = -1)
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute("""
                    UPDATE learning_queue 
                    SET processed = -1 
                    WHERE id = ?
                """, (queue_id,))
                conn.commit()
                conn.close()
                
                return 0
                
        except Exception as e:
            print(f"❌ Worker: Error in process_batch: {e}")
            return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Background Learning Worker")
    parser.add_argument("--db-path", required=True, help="Path to SQLite database")
    args = parser.parse_args()
    
    worker = BackgroundLearningWorker(args.db_path)
    worker.run()
