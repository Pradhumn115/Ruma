import os
import json
import shutil
import asyncio
import requests
from typing import List, Dict, Any
from fastapi import FastAPI, BackgroundTasks, Path
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from datetime import datetime
import threading
import time
from huggingface_hub import list_repo_files, model_info
import json, os, threading, tempfile

# Data models
class DownloadRequest(BaseModel):
    model_id: str
    model_type: str
    files: List[str] = []

class DownloadState(BaseModel):
    model_id: str
    model_type: str
    files: List[str]
    total_size: int
    downloaded: int
    status: str  # downloading, paused, cancelled, ready, error
    created_at: str
    updated_at: str
    file_progress: Dict[str, Dict[str, Any]] = {}  # Track individual file progress
    error_message: str = ""
    # New field to store the unique identifier for GGUF files
    unique_id: str = ""

class PersistentDownloadManager:
    def __init__(self, state_file: str = None, models_dir: str = None):
        # Get writable paths for Ruma v0.1.0
        if state_file is None or models_dir is None:
            default_state_file, default_models_dir = self._get_writable_paths()
            state_file = state_file or default_state_file
            models_dir = models_dir or default_models_dir
        self.state_file = state_file
        self.models_dir = models_dir
        self.download_states: Dict[str, DownloadState] = {}
        self.download_threads: Dict[str, threading.Thread] = {}
        self.cancel_flags: Dict[str, bool] = {}
        self.pause_flags: Dict[str, bool] = {}
        self._state_lock = threading.Lock()           # module-level: one lock for all calls
        # Ensure directories exist
        os.makedirs(os.path.dirname(self.state_file), exist_ok=True)
        os.makedirs(self.models_dir, exist_ok=True)
        
        # Load existing state after path setup
        self.load_state()
        
        # Resume incomplete downloads on startup
        self.resume_incomplete_downloads()
        
    def _get_writable_paths(self):
        """Get writable file paths for Ruma v0.1.0"""
        import sys
        from pathlib import Path
        
        if sys.platform == "darwin":  # macOS
            home = Path.home()
            app_support = home / "Library" / "Application Support" / "Ruma"
            app_support.mkdir(parents=True, exist_ok=True)
            
            state_file = str(app_support / "download_state.json")
            models_dir = str(app_support / "Models")
            
            # Ensure Models subdirectory exists
            os.makedirs(models_dir, exist_ok=True)
            
            print(f"✅ Using download paths: {app_support}")
            return state_file, models_dir
        else:
            # Fallback for development/other platforms
            return "./download_state.json", "./Models"
    
    def generate_unique_id(self, model_id: str, model_type: str, files: List[str]) -> str:
        """Generate a unique identifier for the download"""
        if model_type == "gguf" and len(files) == 1:
            # For GGUF files, use model_id + filename (without extension) for uniqueness
            file_name = files[0]
            # Remove .gguf extension and any path components
            base_name = os.path.splitext(os.path.basename(file_name))[0]
            model_author = model_id.split("/")[0]
            return f"{model_author}/{base_name}"
        else:
            # For MLX or multi-file downloads, use the model_id as-is
            return model_id
    
    def get_model_directory(self, unique_id: str) -> str:
        """Get the directory path for a model based on its unique ID"""
        return os.path.join(self.models_dir, unique_id)
    
    def get_models_directory(self) -> str:
        """Get the current models directory path"""
        return self.models_dir
    
    def set_models_directory(self, new_path: str) -> bool:
        """Set a new models directory path"""
        try:
            # Validate the path
            if not os.path.isabs(new_path):
                return False
            
            # Create the directory if it doesn't exist
            os.makedirs(new_path, exist_ok=True)
            
            # Update the models directory
            old_path = self.models_dir
            self.models_dir = new_path
            
            print(f"✅ Models directory changed from {old_path} to {new_path}")
            return True
            
        except Exception as e:
            print(f"❌ Failed to set models directory: {e}")
            return False
    
    def load_state(self):
        """Load download states from persistent storage"""
        if os.path.exists(self.state_file):
            try:
                with open(self.state_file, 'r') as f:
                    data = json.load(f)
                    for unique_id, state_dict in data.items():
                        state = DownloadState(**state_dict)
                        # Ensure unique_id is set (for backward compatibility)
                        if not state.unique_id:
                            state.unique_id = unique_id
                        self.download_states[unique_id] = state
                print(f"Loaded {len(self.download_states)} download states from {self.state_file}")
            except Exception as e:
                print(f"Error loading state file: {e}")
                self.download_states = {}
    
    def save_state(self):
        """Atomically persist download_states → JSON, thread-safe."""
        with self._state_lock:                     # ① prevent concurrent writers
            try:
                data = {unique_id: st.model_dump() for unique_id, st in self.download_states.items()}

                # ② write to temp file in the same directory
                dir_ = os.path.dirname(self.state_file)
                with tempfile.NamedTemporaryFile("w",
                                                delete=False,
                                                dir=dir_,
                                                encoding="utf-8") as tmp:
                    json.dump(data, tmp, indent=2, ensure_ascii=False)
                    tmp.flush()
                    os.fsync(tmp.fileno())    # ③ force to disk
                os.replace(tmp.name, self.state_file)   # ④ atomic swap
            except Exception as e:
                print(f"[save_state] {e}")
    
    def resume_incomplete_downloads(self):
        """
        For each model with status in {downloading, paused}:
        1. Sanity-check & fix local files vs. remote.
        2. Recompute downloaded/total_size.
        3. If already done → mark `ready`.
        4. Otherwise → spawn exactly one thread with start_download().
        """
        for unique_id, state in list(self.download_states.items()):
            if state.status not in {"downloading"}:
                continue

            model_dir = self.get_model_directory(unique_id)
            os.makedirs(model_dir, exist_ok=True)

            # Ensure file_progress is populated
            if not state.file_progress and state.files:
                for fn in state.files:
                    state.file_progress[fn] = {
                        "downloaded": 0,
                        "total_size": 0,
                        "complete": False
                    }

            # 1) Fix per-file state
            for fn, info in state.file_progress.items():
                if 'url' not in info:
                    continue  # Skip files without URL info
                url  = info['url']
                path = os.path.join(model_dir, fn)

                remote = self.get_remote_file_size(url)
                local  = self.get_file_size_on_disk(path)
                

                # a) Truncate if local > remote
                if remote > 0 and local > remote:
                    with open(path, "rb+") as f:
                        f.truncate(remote)
                    local = remote

                # b) If local == remote → mark complete
                if remote > 0 and local == remote:
                    info["downloaded"]   = remote
                    info["total_size"]   = remote
                    info["complete"]     = True
                    continue

                # c) Otherwise record the partial sizes
                info["downloaded"] = local
                info["total_size"] = remote

            # 2) Recompute overall counters
            state.total_size  = sum(i["total_size"] for i in state.file_progress.values())
            state.downloaded  = sum(i["downloaded"] for i in state.file_progress.values())
            

            # 3) If all shards are done
            if all(i["complete"] for i in state.file_progress.values()):
                state.status     = "ready"
                state.updated_at = datetime.now().isoformat()
                continue

            # 4) Otherwise clear flags & restart the job
            state.status           = "paused"
            state.updated_at       = datetime.now().isoformat()
            self.cancel_flags[unique_id] = False
            self.pause_flags[unique_id]  = False

            # Persist all the fixes you've just made
            if state.downloaded <= state.total_size:
                self.save_state()
            else:
                # skip writing bogus state if some race made them inverted
                print(f"Skipped saving: downloaded > total_size for {unique_id}")

    def get_file_size_on_disk(self, file_path: str) -> int:
        """Get the current size of a file on disk"""
        if os.path.exists(file_path):
            return os.path.getsize(file_path)
        return 0
    
    def get_remote_file_size(self, url: str) -> int:
        """Get the size of a remote file"""
        try:
            response = requests.head(url, allow_redirects=True,timeout=10,headers={"Accept": "application/octet-stream"})
            return int(response.headers.get('content-length', 0))
        except:
            return 0
    
    def calculate_total_downloaded(self, unique_id: str) -> int:
        """Calculate total bytes downloaded for a model"""
        state = self.download_states.get(unique_id)
        if not state:
            return 0
        
        total_downloaded = 0
        model_dir = self.get_model_directory(unique_id)
        
        if state.model_type == "gguf" and len(state.files) == 1:
            # Single file download
            file_path = os.path.join(model_dir, state.files[0])
            total_downloaded = self.get_file_size_on_disk(file_path)
        else:
            # Multiple files (MLX)
            for file_name in state.file_progress.keys():
                file_path = os.path.join(model_dir, file_name)
                total_downloaded += self.get_file_size_on_disk(file_path)
        
        return total_downloaded
    
    def is_download_complete(self, unique_id: str) -> bool:
        """Check if download is complete by comparing file sizes"""
        state = self.download_states.get(unique_id)
        if not state:
            return False
        
        model_dir = self.get_model_directory(unique_id)
        
        if state.model_type == "gguf" and len(state.files) == 1:
            # Single file download
            file_path = os.path.join(model_dir, state.files[0])
            if not os.path.exists(file_path):
                return False
            
            file_url = f"https://huggingface.co/{state.model_id}/resolve/main/{state.files[0]}"
            expected_size = self.get_remote_file_size(file_url)
            actual_size = self.get_file_size_on_disk(file_path)
            
            return actual_size >= expected_size and expected_size > 0
        else:
            # Multiple files (MLX)
            for file_name, file_info in state.file_progress.items():
                file_path = os.path.join(model_dir, file_name)
                if not os.path.exists(file_path):
                    return False
                
                expected_size = file_info.get('total_size', 0)
                actual_size = self.get_file_size_on_disk(file_path)
                
                if actual_size < expected_size:
                    return False
            
            return True
    
    def update_download_progress(self, unique_id: str):
        """Update download progress and save state"""
        state = self.download_states.get(unique_id)
        if not state:
            return
        
        # Calculate current downloaded amount
        downloaded = self.calculate_total_downloaded(unique_id)
        state.downloaded = downloaded
        state.updated_at = datetime.now().isoformat()
        
        # Update percentage
        if state.total_size > 0:
            percentage = round((downloaded / state.total_size) * 100, 2)
        else:
            percentage = 0
        
        # Save state periodically (every 1MB downloaded)
        if downloaded % (1024 * 1024) < 8192:  # Roughly every 1MB
            self.save_state()
    
    def download_single_file(self, unique_id: str, file_url: str, file_name: str):
        """Download a single file with resume support"""
        state = self.download_states[unique_id]
        model_dir = self.get_model_directory(unique_id)
        file_path = os.path.join(model_dir, file_name)
        print(f"Downloading to: {file_path}")
        
        # Create directory
        os.makedirs(model_dir, exist_ok=True)
        
        # Get existing file size for resume
        existing_size = self.get_file_size_on_disk(file_path)
        
        # Set up headers for resume
        headers = {}
        if existing_size > 0:
            headers['Range'] = f'bytes={existing_size}-'
        
        try:
            response = requests.get(file_url, headers=headers, stream=True, timeout=30)
            response.raise_for_status()
            
            # Handle partial content response
            if response.status_code == 206:  # Partial content
                content_range = response.headers.get('content-range', '')
                if content_range:
                    total_size = int(content_range.split('/')[-1])
                else:
                    total_size = existing_size + int(response.headers.get('content-length', 0))
            elif response.status_code == 200:
                total_size = int(response.headers.get('content-length', 0))
                if existing_size > 0 and total_size == existing_size:
                    # File already complete
                    return
                existing_size = 0  # Reset if server doesn't support resume
            else:
                raise Exception(f"Unexpected response code: {response.status_code}")
            
            # Update total size if not set
            if state.total_size == 0:
                state.total_size = total_size
                self.save_state()
            
            downloaded = existing_size
            chunk_size = 8192
            
            # Open file in append mode if resuming, write mode otherwise
            mode = "ab" if existing_size > 0 else "wb"
            
            with open(file_path, mode) as f:
                for chunk in response.iter_content(chunk_size):
                    # Check for cancellation
                    if self.cancel_flags.get(unique_id, False):
                        state.status = "cancelled"
                        state.updated_at = datetime.now().isoformat()
                        self.save_state()
                        return
                    
                    # Check for pause
                    while self.pause_flags.get(unique_id, False):
                        if state.status != "paused":
                            state.status = "paused"
                            state.updated_at = datetime.now().isoformat()
                            self.save_state()
                        time.sleep(0.1)
                    
                    # Resume status when unpaused
                    if state.status == "paused":
                        state.status = "downloading"
                        state.updated_at = datetime.now().isoformat()
                    
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        state.downloaded = downloaded
                        
                        # Update progress periodically
                        self.update_download_progress(unique_id)
            
            # Mark as complete
            state.status = "ready"
            state.downloaded = total_size
            state.updated_at = datetime.now().isoformat()
            self.save_state()
            
        except Exception as e:
            state.status = "error"
            state.error_message = str(e)
            state.updated_at = datetime.now().isoformat()
            self.save_state()
            print(f"Download error for {unique_id}: {e}")
    
    def download_multiple_files(self, unique_id: str, file_urls: List[str]):
        """Download multiple files with resume support"""
        state = self.download_states[unique_id]
        model_dir = self.get_model_directory(unique_id)
        
        try:
            # Initialize file progress if not exists
            if not state.file_progress:
                for file_url in file_urls:
                    file_name = file_url.split("/")[-1]
                    remote_size = self.get_remote_file_size(file_url)
                    state.file_progress[file_name] = {
                        "url": file_url,
                        "total_size": remote_size,
                        "downloaded": 0,
                        "complete": False
                    }
                
                # Calculate total size
                state.total_size = sum(info["total_size"] for info in state.file_progress.values())
                self.save_state()
            
            for file_url in file_urls:
                # Check for cancellation
                if self.cancel_flags.get(unique_id, False):
                    state.status = "cancelled"
                    state.updated_at = datetime.now().isoformat()
                    self.save_state()
                    return
                
                file_name = file_url.split("/")[-1]
                file_path = os.path.join(model_dir, file_name)
                file_info = state.file_progress[file_name]
                
                # Skip if file is already complete
                if file_info.get("complete", False):
                    continue
                
                # Check if file is actually complete on disk
                expected_size = file_info["total_size"]
                actual_size = self.get_file_size_on_disk(file_path)
                if actual_size >= expected_size and expected_size > 0:
                    file_info["complete"] = True
                    file_info["downloaded"] = expected_size
                    continue
                
                # Download the file
                self.download_single_file_in_multi(unique_id, file_url, file_name, file_info)
            
            # Check if all files are complete
            if all(info.get("complete", False) for info in state.file_progress.values()):
                state.status = "ready"
                state.downloaded = state.total_size
                state.updated_at = datetime.now().isoformat()
                self.save_state()
                
        except Exception as e:
            state.status = "error"
            state.error_message = str(e)
            state.updated_at = datetime.now().isoformat()
            self.save_state()
            print(f"Download error for {unique_id}: {e}")
    
    def download_single_file_in_multi(self, unique_id: str, file_url: str, file_name: str, file_info: dict):
        """Download a single file as part of multiple file download"""
        state = self.download_states[unique_id]
        model_dir = self.get_model_directory(unique_id)
        file_path = os.path.join(model_dir, file_name)
        
        # Create directory
        os.makedirs(model_dir, exist_ok=True)
        
        # Get existing file size for resume
        existing_size = self.get_file_size_on_disk(file_path)
        
        # Set up headers for resume
        headers = {}
        if existing_size > 0:
            headers['Range'] = f'bytes={existing_size}-'
        
        try:
            response = requests.get(file_url, headers=headers, stream=True, timeout=30)
            response.raise_for_status()
            
            chunk_size = 8192
            mode = "ab" if existing_size > 0 else "wb"
            
            with open(file_path, mode) as f:
                for chunk in response.iter_content(chunk_size):
                    # Check for cancellation
                    if self.cancel_flags.get(unique_id, False):
                        return
                    
                    # Check for pause
                    while self.pause_flags.get(unique_id, False):
                        if state.status != "paused":
                            state.status = "paused"
                            state.updated_at = datetime.now().isoformat()
                            self.save_state()
                        time.sleep(0.1)
                    
                    # Resume status when unpaused
                    if state.status == "paused":
                        state.status = "downloading"
                        state.updated_at = datetime.now().isoformat()
                    
                    if chunk:
                        f.write(chunk)
                        existing_size += len(chunk)
                        
                        # Update file progress
                        file_info["downloaded"] = existing_size
                        
                        # Update overall progress
                        self.update_download_progress(unique_id)
            
            # Mark file as complete
            file_info["complete"] = True
            file_info["downloaded"] = file_info["total_size"]
            
        except Exception as e:
            print(f"Error downloading {file_name}: {e}")
            raise e
    
    def start_download(self, model_id: str, model_type: str, files: List[str] = None) -> str:
        """Start a new download or resume existing one"""
        current_time = datetime.now().isoformat()
        
        # Generate unique identifier
        if files is None or len(files) == 0:
            if model_type=="mlx":
                from model_size_calc import process_model_files
                files = list_repo_files(model_id)
            else:
                files = []
        
        unique_id = self.generate_unique_id(model_id, model_type, files)
        
        # Check if download already exists
        if unique_id in self.download_states:
            state = self.download_states[unique_id]
            if state.status == "ready":
                return "already_downloaded"
            elif state.status == "downloading":
                return "already_downloading"
            elif state.status in ["paused", "cancelled", "error"]:
                # Resume existing download
                state.status = "downloading"
                state.updated_at = current_time
                self.cancel_flags[unique_id] = False
                self.pause_flags[unique_id] = False
                
                # Start download thread
                if model_type == "gguf" and len(state.files) == 1:
                    file_url = f"https://huggingface.co/{model_id}/resolve/main/{state.files[0]}"
                    thread = threading.Thread(
                        target=self.download_single_file,
                        args=(unique_id, file_url, state.files[0])
                    )
                else:
                    file_urls = [f"https://huggingface.co/{model_id}/resolve/main/{f}" 
                               for f in state.files]
                    thread = threading.Thread(
                        target=self.download_multiple_files,
                        args=(unique_id, file_urls)
                    )
                
                thread.start()
                self.download_threads[unique_id] = thread
                self.save_state()
                return "resumed"
        
        # Create new download state
        state = DownloadState(
            model_id=model_id,
            model_type=model_type,
            files=files,
            total_size=0,
            downloaded=0,
            status="downloading",
            created_at=current_time,
            updated_at=current_time,
            unique_id=unique_id
        )
        
        self.download_states[unique_id] = state
        self.cancel_flags[unique_id] = False
        self.pause_flags[unique_id] = False
        
        # Start download thread
        if model_type == "gguf" and len(files) == 1:
            file_url = f"https://huggingface.co/{model_id}/resolve/main/{files[0]}"
            thread = threading.Thread(
                target=self.download_single_file,
                args=(unique_id, file_url, files[0])
            )
        else:
            # For MLX, we need to get the file list (this would need to be implemented)
            # For now, assuming files are provided
            
            file_urls = [f"https://huggingface.co/{model_id}/resolve/main/{f}" for f in state.files]
            thread = threading.Thread(
                target=self.download_multiple_files,
                args=(unique_id, file_urls)
            )
        
        thread.start()
        self.download_threads[unique_id] = thread
        self.save_state()
        return "started"
    
    def pause_download(self, unique_id: str) -> str:
        """Pause a download"""
        if unique_id not in self.download_states:
            return "not_found"
        
        state = self.download_states[unique_id]
        if state.status != "downloading":
            return f"cannot_pause_{state.status}"
        
        self.pause_flags[unique_id] = True
        return "pausing"
    
    def resume_download(self, unique_id: str) -> str:
        """Resume a paused download (even after a restart)."""
        if unique_id not in self.download_states:
            return "not_found"

        state = self.download_states[unique_id]

        # ---- Handle the normal paused->running transition -------------------
        if state.status in ["paused","downloading"]:
            # clear flag so any *existing* worker can move on
            self.pause_flags[unique_id] = False

            # if no worker thread is alive, spin up a fresh one
            thread_alive = (
                unique_id in self.download_threads
                and self.download_threads[unique_id].is_alive()
            )
            if not thread_alive:
                if state.model_type == "gguf" and len(state.files) == 1:
                    file_url = f"https://huggingface.co/{state.model_id}/resolve/main/{state.files[0]}"
                    thread = threading.Thread(
                        target=self.download_single_file,
                        args=(unique_id, file_url, state.files[0]),
                        daemon=True,
                    )
                else:
                    file_urls = [
                        f"https://huggingface.co/{state.model_id}/resolve/main/{f}"
                        for f in state.files
                    ]
                    thread = threading.Thread(
                        target=self.download_multiple_files,
                        args=(unique_id, file_urls),
                        daemon=True,
                    )
                thread.start()
                self.download_threads[unique_id] = thread

            # reflect the running state
            state.status = "downloading"
            state.updated_at = datetime.now().isoformat()
            self.save_state()
            return "resumed"

        # ---- If the user tries to resume a cancelled/error download ----------
        elif state.status in {"cancelled", "error"}:
            return self.start_download(state.model_id, state.model_type, state.files)

        # ---- Anything else cannot be resumed ---------------------------------
        else:
            return f"cannot_resume_{state.status}"

    
    def cancel_download(self, unique_id: str, cleanup_files: bool = True) -> str:
        """Cancel a download and optionally cleanup partial files"""
        if unique_id not in self.download_states:
            return "not_found"
        
        state = self.download_states[unique_id]
        if state.status not in ["downloading", "paused"]:
            return f"cannot_cancel_{state.status}"
        
        self.cancel_flags[unique_id] = True
        self.pause_flags[unique_id] = False
        
        # Wait for thread to finish if needed
        if unique_id in self.download_threads:
            thread = self.download_threads[unique_id]
            if thread.is_alive():
                thread.join(timeout=2)
        
        # Update status to cancelled
        state.status = "cancelled"
        state.updated_at = datetime.now().isoformat()
        
        # Clean up partial files if requested
        if cleanup_files:
            self.cleanup_partial_files(unique_id)
        
        self.save_state()
        return "cancelled"
    
    def delete_model(self, unique_id: str) -> str:
        """Delete a model and cleanup"""
        try:
            # Cancel any active download
            if unique_id in self.download_states:
                self.cancel_download(unique_id, cleanup_files=False)  # We'll do cleanup below
                
                # Wait for thread to finish
                if unique_id in self.download_threads:
                    thread = self.download_threads[unique_id]
                    if thread.is_alive():
                        thread.join(timeout=5)
            
            # Remove model files
            model_dir = self.get_model_directory(unique_id)
            if os.path.exists(model_dir):
                shutil.rmtree(model_dir)
                print(f"🗑️ Cleaned up model directory: {model_dir}")
            
            # Clean up state
            self.download_states.pop(unique_id, None)
            self.download_threads.pop(unique_id, None)
            self.cancel_flags.pop(unique_id, None)
            self.pause_flags.pop(unique_id, None)
            
            self.save_state()
            return "deleted"
            
        except Exception as e:
            return f"error: {str(e)}"
    
    def get_progress(self, unique_id: str) -> dict:
        """Get download progress"""
        if unique_id not in self.download_states:
            return {"error": "Download not found"}
        
        state = self.download_states[unique_id]
        
        # Update current downloaded amount
        downloaded = self.calculate_total_downloaded(unique_id)
        percentage = round((downloaded / state.total_size) * 100, 2) if state.total_size > 0 else 0
        
        return {
            "downloaded": downloaded,
            "total": state.total_size,
            "status": state.status,
            "percentage": percentage,
            "error": state.error_message
        }
    
    def get_all_downloads(self) -> dict:
        """Get all downloads"""
        downloads = {}
        for unique_id, state in self.download_states.items():
            downloaded = self.calculate_total_downloaded(unique_id)
            percentage = round((downloaded / state.total_size) * 100, 2) if state.total_size > 0 else 0
            
            downloads[unique_id] = {
                "model_id": state.model_id,
                "unique_id": unique_id,
                "downloaded": downloaded,
                "total": state.total_size,
                "status": state.status,
                "percentage": percentage,
                "created_at": state.created_at,
                "updated_at": state.updated_at
            }
        
        return {
            "downloads": downloads,
            "total_downloads": len(downloads)
        }

    def cleanup_partial_files(self, unique_id: str) -> Dict[str, Any]:
        """Clean up partial files and broken model directories for cancelled or failed downloads"""
        try:
            state = self.download_states.get(unique_id)
            if not state:
                return {"success": False, "error": "Download not found"}
            
            model_dir = self.get_model_directory(unique_id)
            cleaned_files = []
            total_freed = 0
            
            if os.path.exists(model_dir):
                # For cancelled/error downloads, remove the entire model directory
                if state.status in ["cancelled", "error"]:
                    # Calculate total directory size before removal
                    for root, dirs, files in os.walk(model_dir):
                        for file in files:
                            file_path = os.path.join(root, file)
                            if os.path.exists(file_path):
                                file_size = os.path.getsize(file_path)
                                total_freed += file_size
                                cleaned_files.append(file)
                    
                    # Remove entire model directory
                    shutil.rmtree(model_dir)
                    print(f"🗑️ Removed entire model directory: {model_dir} ({len(cleaned_files)} files, {total_freed} bytes)")
                    
                    # Remove from download states as well since it's completely cleaned up
                    if unique_id in self.download_states:
                        del self.download_states[unique_id]
                        self.download_threads.pop(unique_id, None)
                        self.cancel_flags.pop(unique_id, None)
                        self.pause_flags.pop(unique_id, None)
                        self.save_state()
                        print(f"🗑️ Removed download state for cleaned model: {unique_id}")
                    
                    return {
                        "success": True,
                        "cleaned_files": cleaned_files,
                        "bytes_freed": total_freed,
                        "message": f"Cleaned up entire model directory with {len(cleaned_files)} files, freed {total_freed} bytes"
                    }
                else:
                    # For other statuses, only remove incomplete files
                    for file_name, file_info in state.file_progress.items():
                        if not file_info.get("complete", False):
                            file_path = os.path.join(model_dir, file_name)
                            if os.path.exists(file_path):
                                file_size = os.path.getsize(file_path)
                                os.remove(file_path)
                                cleaned_files.append(file_name)
                                total_freed += file_size
                                print(f"🧹 Removed partial file: {file_name} ({file_size} bytes)")
                    
                    # Remove empty directories
                    try:
                        if not os.listdir(model_dir):
                            os.rmdir(model_dir)
                            print(f"🗑️ Removed empty model directory: {model_dir}")
                    except OSError:
                        pass  # Directory not empty, that's fine
                    
                    return {
                        "success": True,
                        "cleaned_files": cleaned_files,
                        "bytes_freed": total_freed,
                        "message": f"Cleaned up {len(cleaned_files)} partial files, freed {total_freed} bytes"
                    }
            else:
                return {
                    "success": True,
                    "cleaned_files": [],
                    "bytes_freed": 0,
                    "message": "Model directory does not exist, nothing to clean"
                }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Cleanup failed: {str(e)}"
            }
    
    def get_failed_downloads(self) -> List[Dict[str, Any]]:
        """Get list of failed downloads (cancelled or error status) that can be cleaned up"""
        failed_downloads = []
        
        for unique_id, state in self.download_states.items():
            if state.status in ["cancelled", "error"]:
                model_dir = self.get_model_directory(unique_id)
                partial_files = []
                total_partial_size = 0
                
                # Check if model directory exists and has files to clean
                if os.path.exists(model_dir):
                    # For cancelled/error downloads, report all files in directory
                    for root, dirs, files in os.walk(model_dir):
                        for file in files:
                            file_path = os.path.join(root, file)
                            if os.path.exists(file_path):
                                file_size = os.path.getsize(file_path)
                                # Get relative path from model directory
                                rel_path = os.path.relpath(file_path, model_dir)
                                partial_files.append({
                                    "name": rel_path,
                                    "size": file_size
                                })
                                total_partial_size += file_size
                
                if partial_files:  # Only include if there are files to clean
                    failed_downloads.append({
                        "unique_id": unique_id,
                        "model_id": state.model_id,
                        "status": state.status,
                        "error_message": state.error_message,
                        "partial_files": partial_files,
                        "total_partial_size": total_partial_size,
                        "updated_at": state.updated_at
                    })
        
        return failed_downloads
    
    def cleanup_all_failed_downloads(self) -> Dict[str, Any]:
        """Clean up all failed downloads"""
        failed_downloads = self.get_failed_downloads()
        
        if not failed_downloads:
            return {
                "success": True,
                "message": "No failed downloads to clean up",
                "cleaned_count": 0,
                "bytes_freed": 0
            }
        
        total_cleaned = 0
        total_freed = 0
        cleanup_results = []
        
        for download in failed_downloads:
            unique_id = download["unique_id"]
            result = self.cleanup_partial_files(unique_id)
            
            if result["success"]:
                total_cleaned += len(result["cleaned_files"])
                total_freed += result["bytes_freed"]
                cleanup_results.append({
                    "unique_id": unique_id,
                    "model_id": download["model_id"],
                    "cleaned_files": result["cleaned_files"],
                    "bytes_freed": result["bytes_freed"]
                })
        
        return {
            "success": True,
            "message": f"Cleaned up {total_cleaned} files from {len(cleanup_results)} failed downloads",
            "cleaned_count": total_cleaned,
            "bytes_freed": total_freed,
            "cleanup_results": cleanup_results
        }

# Initialize the persistent download manager
download_manager = PersistentDownloadManager()
from fastapi import APIRouter
# FastAPI app
app = APIRouter()

@app.post("/download_model")
async def download_model(request: DownloadRequest):
    """Start or resume model download"""
    result = download_manager.start_download(
        request.model_id, 
        request.model_type, 
        request.files
    )
    
    status_map = {
        "started": {"status": "started"},
        "resumed": {"status": "resumed"},
        "already_downloaded": {"status": "already downloaded"},
        "already_downloading": {"status": "already downloading"}
    }
    
    return status_map.get(result, {"error": result})

@app.post("/pause_download")
async def pause_download(unique_id: str):
    """Pause an active download"""
    result = download_manager.pause_download(unique_id)
    
    if result == "not_found":
        return JSONResponse({"error": "Download not found"}, status_code=404)
    elif result.startswith("cannot_pause"):
        return JSONResponse({"error": f"Cannot pause download with status: {result.split('_')[-1]}"}, 
                          status_code=400)
    else:
        return {"status": result}

@app.post("/resume_download")
async def resume_download(unique_id: str):
    """Resume a paused download"""
    result = download_manager.resume_download(unique_id)
    
    if result == "not_found":
        return JSONResponse({"error": "Download not found"}, status_code=404)
    elif result.startswith("cannot_resume"):
        return JSONResponse({"error": f"Cannot resume download with status: {result.split('_')[-1]}"}, 
                          status_code=400)
    else:
        return {"status": result}

@app.post("/cancel_download")
async def cancel_download(unique_id: str):
    """Cancel an active download"""
    result = download_manager.cancel_download(unique_id)
    
    if result == "not_found":
        return JSONResponse({"error": "Download not found"}, status_code=404)
    elif result.startswith("cannot_cancel"):
        return JSONResponse({"error": f"Cannot cancel download with status: {result.split('_')[-1]}"}, 
                          status_code=400)
    else:
        return {"status": result}

@app.delete("/delete_model")
async def delete_model(unique_id: str):
    """Delete a downloaded model and cleanup"""
    result = download_manager.delete_model(unique_id)
    
    if result.startswith("error"):
        return JSONResponse({"error": result}, status_code=500)
    else:
        return {"status": result}

@app.get("/progress")
async def get_progress(unique_id: str):
    """Get download progress"""
    progress = download_manager.get_progress(unique_id)

    if progress.get("error"):
        return JSONResponse(progress, status_code=404)
    return progress

@app.get("/downloads")
async def list_downloads():
    """List all downloads and their status"""
    return download_manager.get_all_downloads()

@app.get("/download_status/{unique_id:path}")
async def get_download_status(unique_id: str = Path(...)):
    """Get detailed status of a specific download"""
    if unique_id not in download_manager.download_states:
        return JSONResponse({"error": "Download not found"}, status_code=404)
    
    state = download_manager.download_states[unique_id]
    progress = download_manager.get_progress(unique_id)
    
    status_info = {
        **progress,
        "model_id": state.model_id,
        "unique_id": unique_id,
        "model_type": state.model_type,
        "files": state.files,
        "is_paused": download_manager.pause_flags.get(unique_id, False),
        "is_cancelled": download_manager.cancel_flags.get(unique_id, False),
        "created_at": state.created_at,
        "updated_at": state.updated_at,
        "file_progress": state.file_progress
    }
    
    return status_info

@app.get("/models")
async def list_models():
    """List all models and their current status"""
    models = {}
    for unique_id, state in download_manager.download_states.items():
        models[unique_id] = {
            "model_id": state.model_id,
            "status": state.status,
            "unique_id": unique_id
        }
    
    return {
        "models": models,
        "total_models": len(models)
    }

@app.get("/model_status/{unique_id:path}")
async def get_model_status(unique_id: str = Path(...)):
    """Get comprehensive model status including file location"""
    if unique_id not in download_manager.download_states:
        return JSONResponse({"error": "Model not found"}, status_code=404)
    
    state = download_manager.download_states[unique_id]
    model_path = os.path.join(download_manager.models_dir, unique_id)
    
    return {
        "model_id": state.model_id,
        "unique_id": unique_id,
        "status": state.status,
        "model_path": model_path,
        "absolute_path": os.path.abspath(model_path),
        "exists": os.path.exists(model_path),
        "is_complete": state.status == "ready",
        "created_at": state.created_at,
        "updated_at": state.updated_at,
        "files": os.listdir(model_path) if os.path.exists(model_path) else []
    }

@app.get("/failed_downloads")
async def get_failed_downloads():
    """Get list of failed downloads that can be cleaned up"""
    failed_downloads = download_manager.get_failed_downloads()
    return {
        "failed_downloads": failed_downloads,
        "total_failed": len(failed_downloads),
        "total_partial_size": sum(d["total_partial_size"] for d in failed_downloads)
    }

@app.post("/cleanup_failed_download")
async def cleanup_failed_download(unique_id: str):
    """Clean up partial files for a specific failed download"""
    if unique_id not in download_manager.download_states:
        return JSONResponse({"error": "Download not found"}, status_code=404)
    
    state = download_manager.download_states[unique_id]
    if state.status not in ["cancelled", "error"]:
        return JSONResponse({"error": "Download is not in failed state"}, status_code=400)
    
    result = download_manager.cleanup_partial_files(unique_id)
    
    if result["success"]:
        return {
            "status": "cleaned",
            "cleaned_files": result["cleaned_files"],
            "bytes_freed": result["bytes_freed"],
            "message": result["message"]
        }
    else:
        return JSONResponse({"error": result["error"]}, status_code=500)

@app.post("/cleanup_all_failed")
async def cleanup_all_failed_downloads():
    """Clean up all failed downloads"""
    result = download_manager.cleanup_all_failed_downloads()
    
    if result["success"]:
        return {
            "status": "cleaned",
            "cleaned_count": result["cleaned_count"],
            "bytes_freed": result["bytes_freed"],
            "message": result["message"],
            "cleanup_results": result["cleanup_results"]
        }
    else:
        return JSONResponse({"error": "Cleanup failed"}, status_code=500)

@app.get("/models_directory")
async def get_models_directory():
    """Get the current models directory path"""
    return {
        "models_directory": download_manager.get_models_directory(),
        "absolute_path": os.path.abspath(download_manager.get_models_directory())
    }

class ModelsDirectoryRequest(BaseModel):
    new_path: str

@app.post("/models_directory")
async def set_models_directory(request: ModelsDirectoryRequest):
    """Set a new models directory path"""
    success = download_manager.set_models_directory(request.new_path)
    
    if success:
        return {
            "status": "success",
            "models_directory": download_manager.get_models_directory(),
            "absolute_path": os.path.abspath(download_manager.get_models_directory())
        }
    else:
        return JSONResponse({
            "error": "Failed to set models directory. Please ensure the path is valid and accessible."
        }, status_code=400)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
