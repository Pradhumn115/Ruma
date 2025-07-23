#!/usr/bin/env python3
"""
Crash Guardian for SuriAI Backend
================================

Monitors and automatically restarts the Python backend if it crashes.
Provides crash recovery, cleanup, and logging functionality.
"""

import os
import sys
import time
import signal
import subprocess
import psutil
from datetime import datetime
from pathlib import Path

class CrashGuardian:
    """Guardian process that monitors and restarts the backend on crashes"""
    
    def __init__(self, script_path="unified_app.py", max_restarts=5, restart_delay=3):
        self.script_path = script_path
        self.max_restarts = max_restarts
        self.restart_delay = restart_delay
        self.restart_count = 0
        self.last_restart_time = 0
        self.process = None
        self.running = True
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
        
        # Create logs directory
        self.log_dir = Path("logs")
        self.log_dir.mkdir(exist_ok=True)
        
        print("🛡️ Crash Guardian initialized")
        print(f"   Script: {self.script_path}")
        print(f"   Max restarts: {self.max_restarts}")
        print(f"   Restart delay: {self.restart_delay}s")
    
    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        print(f"\n🛑 Received signal {signum}, shutting down...")
        self.running = False
        if self.process:
            self.stop_backend()
    
    def cleanup_before_start(self):
        """Clean up any lingering processes and resources"""
        print("🧹 Cleaning up before start...")
        
        # Kill any existing background processes
        try:
            subprocess.run(["pkill", "-f", "background_learning_worker"], 
                         capture_output=True, timeout=5)
        except:
            pass
        
        # Kill any existing unified_app processes
        try:
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                try:
                    if proc.info['name'] == 'python3' or proc.info['name'] == 'python':
                        cmdline = ' '.join(proc.info['cmdline'] or [])
                        if 'unified_app.py' in cmdline:
                            print(f"🔪 Killing existing process: PID {proc.info['pid']}")
                            proc.kill()
                            proc.wait(timeout=3)
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.TimeoutExpired):
                    pass
        except Exception as e:
            print(f"⚠️ Cleanup warning: {e}")
        
        # Clear MLX cache if it exists
        try:
            mlx_cache = Path.home() / ".cache" / "mlx"
            if mlx_cache.exists():
                import shutil
                shutil.rmtree(mlx_cache)
                print("🗑️ Cleared MLX cache")
        except Exception as e:
            print(f"⚠️ Cache cleanup warning: {e}")
        
        # Wait a moment for cleanup to complete
        time.sleep(1)
    
    def start_backend(self):
        """Start the backend process"""
        try:
            print(f"🚀 Starting backend: {self.script_path}")
            
            # Setup environment
            env = os.environ.copy()
            env['PYTHONUNBUFFERED'] = '1'  # Force unbuffered output
            
            # Start the process
            self.process = subprocess.Popen([
                sys.executable, self.script_path
            ], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, 
               text=True, bufsize=1)
            
            print(f"✅ Backend started with PID: {self.process.pid}")
            return True
            
        except Exception as e:
            print(f"❌ Failed to start backend: {e}")
            return False
    
    def stop_backend(self):
        """Stop the backend process gracefully"""
        if not self.process:
            return
        
        try:
            print("🛑 Stopping backend gracefully...")
            self.process.terminate()
            
            # Wait for graceful shutdown
            try:
                self.process.wait(timeout=10)
                print("✅ Backend stopped gracefully")
            except subprocess.TimeoutExpired:
                print("⚠️ Force killing backend...")
                self.process.kill()
                self.process.wait()
                print("✅ Backend force stopped")
                
        except Exception as e:
            print(f"❌ Error stopping backend: {e}")
        finally:
            self.process = None
    
    def is_backend_healthy(self):
        """Check if backend is running and healthy"""
        if not self.process:
            return False
        
        # Check if process is still alive
        poll_result = self.process.poll()
        if poll_result is not None:
            return False
        
        # TODO: Add health check via HTTP request to /status
        # For now, just check if process exists
        return True
    
    def log_crash(self, exit_code):
        """Log crash information"""
        timestamp = datetime.now().isoformat()
        log_file = self.log_dir / f"crash_{datetime.now().strftime('%Y%m%d')}.log"
        
        crash_info = f"""
CRASH REPORT - {timestamp}
===========================
Exit Code: {exit_code}
Restart Count: {self.restart_count}
PID: {self.process.pid if self.process else 'Unknown'}

"""
        
        try:
            with open(log_file, 'a') as f:
                f.write(crash_info)
        except Exception as e:
            print(f"⚠️ Failed to write crash log: {e}")
    
    def should_restart(self):
        """Determine if we should restart after a crash"""
        current_time = time.time()
        
        # Reset restart count if it's been a while since last restart
        if current_time - self.last_restart_time > 300:  # 5 minutes
            self.restart_count = 0
        
        # Check if we've exceeded max restarts
        if self.restart_count >= self.max_restarts:
            print(f"❌ Maximum restart attempts ({self.max_restarts}) reached")
            return False
        
        return True
    
    def run(self):
        """Main guardian loop"""
        print("🛡️ Starting Crash Guardian...")
        
        # Initial cleanup
        self.cleanup_before_start()
        
        # Start the backend
        if not self.start_backend():
            print("❌ Failed to start backend initially")
            return 1
        
        try:
            while self.running:
                # Check backend health
                if not self.is_backend_healthy():
                    exit_code = self.process.poll() if self.process else -1
                    print(f"💥 Backend crashed with exit code: {exit_code}")
                    
                    # Log the crash
                    self.log_crash(exit_code)
                    
                    # Check if we should restart
                    if not self.should_restart():
                        print("🛑 Not restarting due to restart limits")
                        break
                    
                    print(f"⏳ Waiting {self.restart_delay}s before restart...")
                    time.sleep(self.restart_delay)
                    
                    # Cleanup and restart
                    self.cleanup_before_start()
                    self.restart_count += 1
                    self.last_restart_time = time.time()
                    
                    print(f"🔄 Restart attempt {self.restart_count}/{self.max_restarts}")
                    
                    if not self.start_backend():
                        print("❌ Failed to restart backend")
                        break
                
                # Wait before next health check
                time.sleep(2)
                
        except KeyboardInterrupt:
            print("\n🛑 Guardian interrupted by user")
        
        # Cleanup on exit
        self.stop_backend()
        print("🛡️ Crash Guardian stopped")
        return 0

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Crash Guardian for SuriAI Backend")
    parser.add_argument("--script", default="unified_app.py", 
                       help="Python script to monitor (default: unified_app.py)")
    parser.add_argument("--max-restarts", type=int, default=5,
                       help="Maximum restart attempts (default: 5)")
    parser.add_argument("--restart-delay", type=int, default=3,
                       help="Delay between restarts in seconds (default: 3)")
    
    args = parser.parse_args()
    
    guardian = CrashGuardian(
        script_path=args.script,
        max_restarts=args.max_restarts,
        restart_delay=args.restart_delay
    )
    
    return guardian.run()

if __name__ == "__main__":
    sys.exit(main())