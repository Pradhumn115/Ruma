"""
Separate Process Background Learning
===================================

Production-grade solution: Run background learning in completely separate Python process
to avoid GPU conflicts entirely. This is how professional apps handle this problem.
"""

import subprocess
import json
import sqlite3
import os
import signal
import time
from typing import Dict, List, Any, Optional
from pathlib import Path


class SeparateProcessLearning:
    """Background learning using separate Python process - production approach"""
    
    def __init__(self, db_path: str = "smart_memory.db"):
        self.db_path = db_path
        self.worker_process = None
        self.worker_script = "background_learning_worker.py"
        
    def queue_chat_for_learning(self, user_id: str, chat_id: str, messages: List[Dict]):
        """Queue chat in database for separate process to handle"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Create table if not exists
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS learning_queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    chat_id TEXT NOT NULL,
                    messages TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    processed INTEGER DEFAULT 0,
                    process_started_at TIMESTAMP NULL
                )
            """)
            
            # Insert chat into queue
            cursor.execute("""
                INSERT INTO learning_queue (user_id, chat_id, messages)
                VALUES (?, ?, ?)
            """, (user_id, chat_id, json.dumps(messages)))
            
            print(f"📚 Queued chat {chat_id} for separate process learning")
            
            # Get current queue status for notification
            cursor.execute("SELECT COUNT(*) FROM learning_queue WHERE processed = 0")
            pending_count = cursor.fetchone()[0]
            if pending_count > 0:
                print(f"🔄 Background learning queue: {pending_count} chats pending processing")
            
            conn.commit()
            conn.close()
            
            # Start worker if not running
            self.ensure_worker_running()
            
        except Exception as e:
            print(f"❌ Failed to queue chat for learning: {e}")
    
    def ensure_worker_running(self):
        """Ensure background worker process is running"""
        try:
            # Check if worker process is still alive
            if self.worker_process and self.worker_process.poll() is None:
                return  # Already running
            
            # Start new worker process
            self.start_worker()
            
        except Exception as e:
            print(f"❌ Failed to ensure worker running: {e}")
    
    def start_worker(self):
        """Start the background learning worker process"""
        try:
            # Create the worker script if it doesn't exist
            self.create_worker_script()
            
            # Start worker process
            env = os.environ.copy()
            env['PYTHONPATH'] = os.getcwd()  # Ensure worker can import our modules
            
            self.worker_process = subprocess.Popen([
                'python', self.worker_script,
                '--db-path', self.db_path
            ], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            print(f"🚀 Started background learning worker (PID: {self.worker_process.pid})")
            
        except Exception as e:
            print(f"❌ Failed to start worker: {e}")
    
    def stop_worker(self):
        """Stop the background learning worker process"""
        try:
            if self.worker_process and self.worker_process.poll() is None:
                print("🛑 Stopping background learning worker...")
                self.worker_process.terminate()
                
                # Wait for graceful shutdown
                try:
                    self.worker_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    print("🚨 Force killing worker process...")
                    self.worker_process.kill()
                    self.worker_process.wait()
                
                print("✅ Background learning worker stopped")
                self.worker_process = None
                
        except Exception as e:
            print(f"❌ Failed to stop worker: {e}")
    
    def get_queue_status(self) -> Dict[str, int]:
        """Get status of learning queue"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("SELECT COUNT(*) FROM learning_queue WHERE processed = 0")
            pending = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM learning_queue WHERE processed = 1")
            processed = cursor.fetchone()[0]
            
            conn.close()
            
            return {
                "pending": pending,
                "processed": processed,
                "worker_running": self.worker_process and self.worker_process.poll() is None
            }
            
        except Exception as e:
            print(f"❌ Failed to get queue status: {e}")
            return {"pending": 0, "processed": 0, "worker_running": False}
    
    def create_worker_script(self):
        """Create the background learning worker script"""
        worker_code = '''#!/usr/bin/env python3
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
'''
        
        # Only write file if it doesn't exist or content has changed
        should_write = True
        if os.path.exists(self.worker_script):
            try:
                with open(self.worker_script, 'r') as f:
                    existing_content = f.read()
                if existing_content == worker_code:
                    should_write = False
            except:
                pass  # If we can't read, write anyway
        
        if should_write:
            with open(self.worker_script, 'w') as f:
                f.write(worker_code)
            
            # Make executable
            os.chmod(self.worker_script, 0o755)
            print(f"✅ Created worker script: {self.worker_script}")
        else:
            print(f"✅ Worker script already exists: {self.worker_script}")


# Global instance
_separate_learning = None

def get_separate_learning() -> SeparateProcessLearning:
    """Get the global separate process learning instance"""
    global _separate_learning
    if _separate_learning is None:
        _separate_learning = SeparateProcessLearning()
    return _separate_learning

def queue_chat_for_learning(user_id: str, chat_id: str, messages: List[Dict]):
    """Queue a chat for separate process learning"""
    get_separate_learning().queue_chat_for_learning(user_id, chat_id, messages)

def stop_background_learning():
    """Stop background learning worker"""
    get_separate_learning().stop_worker()

def get_learning_status() -> Dict[str, int]:
    """Get learning queue status"""
    return get_separate_learning().get_queue_status()