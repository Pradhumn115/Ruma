"""
Simple Background Learning Control System
========================================

A clean, reliable system for stopping and starting background learning
when the UI opens and closes. No complex threading or state management.
"""

import threading
import time
from typing import Dict, Any, Optional


class SimpleBackgroundControl:
    """Simple, reliable background learning control"""
    
    def __init__(self):
        self.ui_active = False
        self.processing_active = False
        self.current_task = None
        self.stop_event = threading.Event()
        self.lock = threading.Lock()
        
    def ui_opened(self):
        """Call this when UI opens - immediately stops background processing"""
        with self.lock:
            print("🔴 UI OPENED - Stopping background learning")
            self.ui_active = True
            self.stop_event.set()  # Signal all background tasks to stop
            
            # Wait briefly for current task to finish
            if self.current_task and self.current_task.is_alive():
                print("⏹️ Waiting for current background task to stop...")
                self.current_task.join(timeout=2.0)  # Wait max 2 seconds
                
            self.processing_active = False
            print("✅ Background learning stopped")
    
    def ui_closed(self):
        """Call this when UI closes - allows background processing to start"""
        with self.lock:
            print("🟢 UI CLOSED - Background learning can start")
            self.ui_active = False
            self.stop_event.clear()  # Clear stop signal
            
            # Start background processing after a brief delay
            def delayed_start():
                time.sleep(3.0)  # Wait 3 seconds to ensure UI is fully closed
                if not self.ui_active:  # Double check UI is still closed
                    self.start_background_processing()
                    
            thread = threading.Thread(target=delayed_start, daemon=True)
            thread.start()
    
    def start_background_processing(self):
        """Start background processing if UI is not active"""
        with self.lock:
            if self.ui_active:
                print("⏹️ Cannot start background processing - UI is active")
                return
                
            if self.processing_active:
                print("⏹️ Background processing already running")
                return
                
            print("🧠 Starting background learning...")
            self.processing_active = True
            
            # Start the actual processing in a separate thread
            self.current_task = threading.Thread(
                target=self._background_worker,
                daemon=True
            )
            self.current_task.start()
    
    def _background_worker(self):
        """Background worker that processes pending chats"""
        try:
            from smart_memory_system import get_smart_memory
            smart_memory = get_smart_memory()
            
            while not self.stop_event.is_set() and not self.ui_active:
                try:
                    # Process one batch of chats
                    processed = smart_memory.process_single_batch()
                    
                    if processed == 0:
                        # No work to do, wait a bit
                        if self.stop_event.wait(10.0):  # Check every 10 seconds
                            break
                    else:
                        # Brief pause between batches
                        if self.stop_event.wait(1.0):
                            break
                            
                except Exception as e:
                    print(f"❌ Background processing error: {e}")
                    if self.stop_event.wait(5.0):  # Wait 5 seconds before retry
                        break
                        
        except Exception as e:
            print(f"❌ Background worker failed: {e}")
        finally:
            with self.lock:
                self.processing_active = False
            print("🛑 Background learning worker stopped")
    
    def should_stop(self) -> bool:
        """Check if background processing should stop"""
        return self.ui_active or self.stop_event.is_set()
    
    def is_ui_active(self) -> bool:
        """Check if UI is currently active"""
        return self.ui_active
    
    def is_processing_active(self) -> bool:
        """Check if background processing is active"""
        return self.processing_active
    
    def force_stop(self):
        """Force stop all background processing"""
        with self.lock:
            print("🚨 Force stopping background learning")
            self.stop_event.set()
            self.processing_active = False
            
            if self.current_task and self.current_task.is_alive():
                self.current_task.join(timeout=1.0)


# Global instance
_background_control = None

def get_background_control() -> SimpleBackgroundControl:
    """Get the global background control instance"""
    global _background_control
    if _background_control is None:
        _background_control = SimpleBackgroundControl()
    return _background_control


def ui_opened():
    """Simple function to call when UI opens"""
    get_background_control().ui_opened()


def ui_closed():
    """Simple function to call when UI closes"""
    get_background_control().ui_closed()


def should_stop_processing() -> bool:
    """Check if background processing should stop"""
    return get_background_control().should_stop()


def is_ui_active() -> bool:
    """Check if UI is active"""
    return get_background_control().is_ui_active()