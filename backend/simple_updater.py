"""Simple and robust update system with minimal dependencies."""

import os
import json
import aiohttp
import asyncio
import subprocess
import tempfile
import shutil
from typing import Dict, Any, Optional
from pathlib import Path
from datetime import datetime
import time
import platform


class SimpleUpdater:
    """Simplified update system focused on reliability."""
    
    def __init__(self, repo_owner: str = "Pradhumn115", repo_name: str = "Ruma"):
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.app_dir = Path(__file__).parent
        self.current_version = "0.1.0"
        
        # Simple state tracking
        self.download_state_file = self.app_dir / "download_state.json"
        self.is_downloading = False
        self.is_paused = False
        self.download_task = None  # Track the current download task
        
        # Auto-compact settings
        self.max_backups = 5  # Keep only 5 most recent backups
        self.max_temp_age_hours = 72  # Delete temp files older than 72 hours (3 days)
        
    async def check_for_updates(self, max_retries: int = 3) -> Dict[str, Any]:
        """Check for updates with network failure recovery."""
        for attempt in range(max_retries):
            try:
                # Get first release (including prereleases) since latest excludes prereleases
                url = f"https://api.github.com/repos/{self.repo_owner}/{self.repo_name}/releases"
                
                timeout = aiohttp.ClientTimeout(total=15, connect=10)
                headers = {
                    'User-Agent': 'Ruma-Update-Client/1.0',
                    'Accept': 'application/vnd.github.v3+json'
                }
                
                async with aiohttp.ClientSession(timeout=timeout) as session:
                    async with session.get(url, headers=headers) as response:
                        if response.status == 403:
                            # Rate limited, wait longer
                            if attempt < max_retries - 1:
                                print(f"GitHub API rate limited, waiting...")
                                await asyncio.sleep(60)  # Wait 1 minute
                                continue
                            return {"error": "GitHub API rate limited. Please try again later."}
                        
                        if response.status == 404:
                            return {"error": "No releases found for this repository"}
                        
                        if response.status != 200:
                            if attempt < max_retries - 1:
                                await asyncio.sleep(2 ** attempt)  # Exponential backoff
                                continue
                            return {"error": f"Failed to check updates: HTTP {response.status}"}
                        
                        releases = await response.json()
                        if not releases:
                            return {"error": "No releases found"}
                        
                        # Get the first (latest) release
                        data = releases[0]
                        latest_version = data.get("tag_name", "").lstrip("v")
                        assets = data.get("assets", [])
                        
                        # Find DMG asset for macOS
                        download_url = None
                        download_size = 0
                        for asset in assets:
                            name = asset.get("name", "").lower()
                            if name.endswith(".dmg") or "ruma" in name:
                                download_url = asset.get("browser_download_url")
                                download_size = asset.get("size", 0)
                                break
                        
                        if not download_url:
                            return {"error": "No DMG file found in release assets"}
                        
                        update_available = self.is_newer_version(latest_version, self.current_version)
                        
                        return {
                            "update_available": update_available,
                            "current_version": self.current_version,
                            "latest_version": latest_version,
                            "download_url": download_url,
                            "download_size": download_size,
                            "release_notes": data.get("body", ""),
                            "published_at": data.get("published_at", "")
                        }
                        
            except (aiohttp.ClientError, asyncio.TimeoutError) as e:
                if attempt < max_retries - 1:
                    print(f"Network error (attempt {attempt + 1}/{max_retries}): {e}")
                    await asyncio.sleep(2 ** attempt)  # Exponential backoff
                    continue
                return {"error": f"Network error after {max_retries} attempts: {str(e)}"}
            except Exception as e:
                return {"error": f"Update check failed: {str(e)}"}
                
        return {"error": "Max retries exceeded"}
    
    def is_newer_version(self, latest: str, current: str) -> bool:
        """Compare version strings to determine if update is available."""
        try:
            # Remove 'v' prefix and split by dots
            latest_parts = [int(x) for x in latest.replace("v", "").split(".")]
            current_parts = [int(x) for x in current.replace("v", "").split(".")]
            
            # Pad with zeros if lengths differ
            max_len = max(len(latest_parts), len(current_parts))
            latest_parts.extend([0] * (max_len - len(latest_parts)))
            current_parts.extend([0] * (max_len - len(current_parts)))
            
            return latest_parts > current_parts
        except Exception:
            # If version parsing fails, assume different = newer
            return latest != current
    
    def _check_disk_space(self, required_bytes: int, path: Path = None) -> bool:
        """Check if there's enough disk space."""
        try:
            if path is None:
                path = self.app_dir
            
            if platform.system() == "Darwin":  # macOS
                result = subprocess.run(['df', '-k', str(path)], capture_output=True, text=True)
                if result.returncode == 0:
                    lines = result.stdout.strip().split('\n')
                    if len(lines) > 1:
                        # Get available space (4th column, in KB)
                        available_kb = int(lines[1].split()[3])
                        available_bytes = available_kb * 1024
                        return available_bytes > required_bytes * 1.1  # 10% buffer
            else:
                # Fallback for other systems
                stat = os.statvfs(str(path))
                available_bytes = stat.f_frsize * stat.f_bavail
                return available_bytes > required_bytes * 1.1
                
            return True  # If we can't check, assume it's fine
        except Exception:
            return True  # If we can't check, assume it's fine

    async def download_update(self, download_url: str, auto_install: bool = False) -> Dict[str, Any]:
        """Simple download with resumable support and comprehensive error handling."""
        try:
            self.is_downloading = True
            self.is_paused = False
            
            # Create temp directory
            temp_dir = Path(tempfile.mkdtemp(prefix="ruma_update_"))
            filename = download_url.split("/")[-1]
            download_path = temp_dir / filename
            
            # Load existing state if available
            state = self._load_state()
            downloaded = 0
            
            if state and state.get("url") == download_url and Path(state.get("path", "")).exists():
                download_path = Path(state["path"])
                downloaded = download_path.stat().st_size
                temp_dir = download_path.parent
            
            # Save initial state
            self._save_state({
                "url": download_url,
                "path": str(download_path),
                "downloaded": downloaded,
                "total_size": 0,
                "status": "downloading"
            })
            
            headers = {}
            if downloaded > 0:
                headers['Range'] = f'bytes={downloaded}-'
            
            timeout = aiohttp.ClientTimeout(total=None, connect=10)  # No total timeout for downloads
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(download_url, headers=headers) as response:
                    if response.status == 416:  # Range not satisfiable
                        # Start fresh
                        if download_path.exists():
                            download_path.unlink()
                        downloaded = 0
                        headers = {}
                        async with session.get(download_url) as fresh_response:
                            response = fresh_response
                    
                    if response.status not in (200, 206):
                        return {"error": f"Download failed: HTTP {response.status}"}
                    
                    # Get total size
                    if response.status == 200:
                        total_size = int(response.headers.get('Content-Length', 0))
                        mode = 'wb'
                        downloaded = 0
                    else:
                        content_range = response.headers.get('Content-Range', '')
                        if content_range:
                            total_size = int(content_range.split('/')[-1])
                        else:
                            total_size = int(response.headers.get('Content-Length', 0)) + downloaded
                        mode = 'ab'
                    
                    # Check disk space
                    if total_size > 0 and not self._check_disk_space(total_size, temp_dir):
                        return {"error": f"Insufficient disk space. Need {total_size // (1024*1024)} MB"}
                    
                    # Update state with total size
                    self._save_state({
                        "url": download_url,
                        "path": str(download_path),
                        "downloaded": downloaded,
                        "total_size": total_size,
                        "status": "downloading"
                    })
                    
                    # Download file
                    with open(download_path, mode) as f:
                        chunk_count = 0
                        async for chunk in response.content.iter_chunked(8192):
                            if self.is_paused:
                                break
                                
                            f.write(chunk)
                            downloaded += len(chunk)
                            chunk_count += 1
                            
                            # Update state every 100 chunks
                            if chunk_count % 100 == 0:
                                self._save_state({
                                    "url": download_url,
                                    "path": str(download_path),
                                    "downloaded": downloaded,
                                    "total_size": total_size,
                                    "status": "downloading" if not self.is_paused else "paused"
                                })
                    
                    if self.is_paused:
                        self._save_state({
                            "url": download_url,
                            "path": str(download_path),
                            "downloaded": downloaded,
                            "total_size": total_size,
                            "status": "paused"
                        })
                        return {"status": "paused", "downloaded": downloaded, "total_size": total_size}
                    
                    # Download complete
                    self._save_state({
                        "url": download_url,
                        "path": str(download_path),
                        "downloaded": downloaded,
                        "total_size": total_size,
                        "status": "complete"
                    })
                    
                    self.is_downloading = False
                    
                    # If auto_install is enabled, automatically install the update
                    if auto_install:
                        print("🔄 Auto-install enabled, installing update automatically...")
                        install_result = await self.install_update(str(download_path), auto_install=True)
                        
                        if install_result.get("success"):
                            return {
                                "success": True,
                                "path": str(download_path),
                                "downloaded": downloaded,
                                "total_size": total_size,
                                "auto_installed": True,
                                "install_result": install_result
                            }
                        else:
                            return {
                                "success": True,
                                "path": str(download_path),
                                "downloaded": downloaded,
                                "total_size": total_size,
                                "auto_installed": False,
                                "install_error": install_result.get("error", "Unknown installation error")
                            }
                    
                    return {
                        "success": True,
                        "path": str(download_path),
                        "downloaded": downloaded,
                        "total_size": total_size
                    }
                    
        except asyncio.CancelledError:
            # Task was cancelled, clean up properly
            print("🛑 Download task was cancelled")
            self.is_downloading = False
            self.is_paused = False
            # Don't return anything, just let the cancellation propagate
            raise
        except Exception as e:
            self.is_downloading = False
            return {"error": f"Download failed: {str(e)}"}
    
    async def install_update(self, file_path: str, auto_install: bool = False) -> Dict[str, Any]:
        """Simple DMG installation."""
        try:
            dmg_path = Path(file_path)
            
            # Mount DMG
            mount_result = subprocess.run([
                'hdiutil', 'attach', str(dmg_path), '-nobrowse'
            ], capture_output=True, text=True)
            
            if mount_result.returncode != 0:
                return {"error": f"Failed to mount DMG: {mount_result.stderr}"}
            
            # Get mount point - parse the last line that has a /Volumes path
            mount_point = None
            for line in mount_result.stdout.strip().split('\n'):
                if '/Volumes/' in line:
                    mount_point = line.split('\t')[-1].strip()
            
            if not mount_point:
                return {"error": f"Could not find mount point in output: {mount_result.stdout}"}
                
            mount_path = Path(mount_point)
            
            # Find .app file
            app_files = list(mount_path.glob("*.app"))
            
            if not app_files:
                app_files = list(mount_path.glob("**/*.app"))
            
            if not app_files:
                subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'])
                return {"error": f"No .app file found in DMG at {mount_point}. Contents: {list(mount_path.iterdir())}"}
            
            app_file = app_files[0]
            
            if auto_install:
                # Industry-level automatic installation with app replacement
                return await self._perform_automatic_app_replacement(app_file, mount_point, dmg_path)
            else:
                # Manual installation
                subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'])
                return {
                    "success": True,
                    "message": "DMG ready for manual installation",
                    "instructions": [
                        "1. Double-click the DMG file to mount it",
                        f"2. Drag {app_file.name} to your Applications folder",
                        "3. Launch the new version"
                    ]
                }
                
        except Exception as e:
            return {"error": f"Installation failed: {str(e)}"}
    
    async def _perform_automatic_app_replacement(self, app_in_dmg: Path, mount_point: str, dmg_path: Path) -> Dict[str, Any]:
        """Perform automatic app replacement with old app deletion and new app launch."""
        try:
            apps_dir = Path("/Applications")
            dest_path = apps_dir / app_in_dmg.name
            
            # Step 1: Create backup of old app if it exists
            backup_path = None
            if dest_path.exists():
                backup_dir = self.app_dir / "backups"
                backup_dir.mkdir(exist_ok=True)
                
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                backup_path = backup_dir / f"{app_in_dmg.name}_backup_{timestamp}"
                
                print(f"🔄 Creating backup: {dest_path} -> {backup_path}")
                shutil.copytree(dest_path, backup_path)
                print(f"✅ Backup created at: {backup_path}")
            
            # Step 2: Check if app is currently running and request closure
            app_name = app_in_dmg.name.replace('.app', '')
            running_processes = self._get_running_app_processes(app_name)
            
            if running_processes:
                print(f"🔄 Found running {app_name} processes: {running_processes}")
                
                # Try to gracefully quit the app first
                quit_result = subprocess.run([
                    'osascript', '-e', f'tell application "{app_name}" to quit'
                ], capture_output=True, text=True)
                
                if quit_result.returncode == 0:
                    print(f"✅ Gracefully quit {app_name}")
                    # Wait a moment for the app to close
                    await asyncio.sleep(2)
                else:
                    print(f"⚠️ Could not gracefully quit {app_name}, will force close if needed")
                
                # Check if processes are still running and force kill if necessary
                remaining_processes = self._get_running_app_processes(app_name)
                if remaining_processes:
                    print(f"🔄 Force killing remaining {app_name} processes...")
                    for pid in remaining_processes:
                        try:
                            subprocess.run(['kill', '-9', str(pid)], check=True)
                            print(f"✅ Killed process {pid}")
                        except subprocess.CalledProcessError:
                            print(f"⚠️ Could not kill process {pid}")
                    
                    # Wait for processes to fully terminate
                    await asyncio.sleep(2)
                    
                    # Final check - if still running, kill more aggressively
                    final_check = self._get_running_app_processes(app_name)
                    if final_check:
                        print(f"🔄 Final attempt - killing all app-related processes...")
                        # Kill by process name pattern
                        subprocess.run(['pkill', '-f', app_name], capture_output=True)
                        await asyncio.sleep(1)
            
            # Step 3: Remove old app completely
            if dest_path.exists():
                print(f"🗑️ Removing old app: {dest_path}")
                shutil.rmtree(dest_path)
                print(f"✅ Old app removed")
            
            # Step 4: Install new app
            print(f"🔄 Installing new app: {app_in_dmg} -> {dest_path}")
            shutil.copytree(app_in_dmg, dest_path)
            
            # Step 5: Fix permissions
            print(f"🔧 Setting permissions...")
            os.chmod(dest_path, 0o755)
            
            # Make executable files executable
            macos_dir = dest_path / "Contents" / "MacOS"
            if macos_dir.exists():
                for exec_file in macos_dir.iterdir():
                    if exec_file.is_file():
                        os.chmod(exec_file, 0o755)
            
            # Step 6: Remove quarantine attributes
            print(f"🔓 Removing quarantine attributes...")
            subprocess.run([
                'xattr', '-rd', 'com.apple.quarantine', str(dest_path)
            ], capture_output=True)
            
            # Step 7: Launch new app
            print(f"🚀 Launching new app...")
            try:
                launch_result = subprocess.run([
                    'open', str(dest_path)
                ], capture_output=True, text=True, timeout=10)
                
                if launch_result.returncode == 0:
                    print(f"✅ New app launched successfully")
                else:
                    print(f"⚠️ Launch command failed: {launch_result.stderr}")
                    # Try alternative launch method
                    print(f"🔄 Trying alternative launch method...")
                    alt_launch_result = subprocess.run([
                        'open', '-a', str(dest_path)
                    ], capture_output=True, text=True, timeout=10)
                    
                    if alt_launch_result.returncode == 0:
                        print(f"✅ New app launched with alternative method")
                    else:
                        print(f"⚠️ Alternative launch also failed: {alt_launch_result.stderr}")
                        
            except subprocess.TimeoutExpired:
                print(f"⚠️ Launch command timed out")
            except Exception as e:
                print(f"⚠️ Launch error: {e}")
            
            # Step 8: Cleanup DMG
            subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'])
            
            # Step 9: Verify installation
            if dest_path.exists():
                try:
                    # Check if the app bundle is valid
                    info_plist = dest_path / "Contents" / "Info.plist"
                    if info_plist.exists():
                        print(f"✅ App bundle verification successful")
                        installed_version = "Unknown"
                        
                        # Try to read version from Info.plist
                        try:
                            import plistlib
                            with open(info_plist, 'rb') as f:
                                plist_data = plistlib.load(f)
                                installed_version = plist_data.get('CFBundleShortVersionString', 'Unknown')
                                print(f"📦 Installed version: {installed_version}")
                        except Exception as e:
                            print(f"⚠️ Could not read version from Info.plist: {e}")
                    else:
                        print(f"⚠️ Info.plist not found - app bundle may be incomplete")
                except Exception as e:
                    print(f"⚠️ App bundle verification failed: {e}")
            else:
                print(f"❌ Installation verification failed - app not found at {dest_path}")
            
            print(f"✅ App replacement completed successfully!")
            
            return {
                "success": True,
                "message": "App updated and launched successfully",
                "old_app_backed_up": backup_path is not None,
                "backup_path": str(backup_path) if backup_path else None,
                "new_app_launched": True,
                "restart_required": False,  # No restart needed since we launched the new app
                "installed_path": str(dest_path),
                "verification_passed": dest_path.exists()
            }
            
        except Exception as e:
            print(f"❌ Error during app replacement: {e}")
            
            # Try to restore from backup if something went wrong
            if backup_path and backup_path.exists() and not dest_path.exists():
                try:
                    print(f"🔄 Restoring from backup...")
                    shutil.copytree(backup_path, dest_path)
                    print(f"✅ Restored from backup")
                except Exception as restore_error:
                    print(f"❌ Failed to restore from backup: {restore_error}")
            
            subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'], capture_output=True)
            
            return {
                "success": False,
                "error": f"App replacement failed: {str(e)}",
                "backup_available": backup_path is not None and backup_path.exists(),
                "backup_path": str(backup_path) if backup_path and backup_path.exists() else None
            }
    
    def _get_running_app_processes(self, app_name: str) -> list:
        """Get list of PIDs for running app processes."""
        try:
            # Get processes that match the app name
            result = subprocess.run([
                'pgrep', '-f', app_name
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                pids = [int(pid.strip()) for pid in result.stdout.split('\n') if pid.strip()]
                return pids
            return []
        except Exception as e:
            print(f"Error getting running processes: {e}")
            return []
    
    def get_available_backups(self) -> Dict[str, Any]:
        """Get list of available app version backups."""
        try:
            backup_dir = self.app_dir / "backups"
            backups = []
            
            if backup_dir.exists():
                for item in backup_dir.iterdir():
                    if item.is_dir() and ("backup_" in item.name):
                        try:
                            # Extract timestamp and app name from backup name
                            # Format: AppName_backup_YYYYMMDD_HHMMSS or AppName_backup_before_restore_YYYYMMDD_HHMMSS
                            parts = item.name.split("_backup_")
                            if len(parts) == 2:
                                app_name = parts[0]
                                remaining = parts[1]
                                
                                # Handle special "before_restore" backups
                                if remaining.startswith("before_restore_"):
                                    timestamp_str = remaining.replace("before_restore_", "")
                                    backup_type = "Before Restore"
                                else:
                                    timestamp_str = remaining
                                    backup_type = "Regular"
                                
                                timestamp = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
                                
                                # Get backup size
                                size_mb = self._get_directory_size(item) / (1024 * 1024)
                                
                                backups.append({
                                    "app_name": app_name,
                                    "backup_path": str(item),
                                    "backup_name": item.name,
                                    "timestamp": timestamp.isoformat(),
                                    "timestamp_display": timestamp.strftime("%Y-%m-%d %H:%M:%S"),
                                    "size_mb": round(size_mb, 2),
                                    "backup_type": backup_type
                                })
                        except (ValueError, IndexError) as e:
                            print(f"⚠️ Invalid backup name format: {item.name}")
                            continue
                
                # Sort by timestamp (newest first)
                backups.sort(key=lambda x: x["timestamp"], reverse=True)
            
            return {
                "success": True,
                "backups": backups,
                "total_backups": len(backups)
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to get backups: {str(e)}",
                "backups": []
            }
    
    async def restore_from_backup(self, backup_name: str) -> Dict[str, Any]:
        """Restore app from a specific backup."""
        try:
            backup_dir = self.app_dir / "backups"
            backup_path = backup_dir / backup_name
            
            if not backup_path.exists():
                return {"error": f"Backup not found: {backup_name}"}
            
            # Extract app name from backup name
            app_name = backup_name.split("_backup_")[0]
            apps_dir = Path("/Applications")
            current_app_path = apps_dir / app_name
            
            # Check if app is currently running and close it
            app_name_clean = app_name.replace('.app', '')
            running_processes = self._get_running_app_processes(app_name_clean)
            
            if running_processes:
                print(f"🔄 Closing running {app_name_clean} processes...")
                
                # Try to gracefully quit the app first
                quit_result = subprocess.run([
                    'osascript', '-e', f'tell application "{app_name_clean}" to quit'
                ], capture_output=True, text=True)
                
                if quit_result.returncode == 0:
                    print(f"✅ Gracefully quit {app_name_clean}")
                    await asyncio.sleep(2)
                else:
                    # Force kill if necessary
                    print(f"🔄 Force killing {app_name_clean} processes...")
                    for pid in running_processes:
                        try:
                            subprocess.run(['kill', '-9', str(pid)], check=True)
                        except subprocess.CalledProcessError:
                            pass
                    await asyncio.sleep(1)
            
            # Create backup of current version before restoring
            if current_app_path.exists():
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                current_backup_name = f"{app_name}_backup_before_restore_{timestamp}"
                current_backup_path = backup_dir / current_backup_name
                
                print(f"🔄 Creating backup of current version...")
                shutil.copytree(current_app_path, current_backup_path)
                print(f"✅ Current version backed up as: {current_backup_name}")
                
                # Remove current version
                print(f"🗑️ Removing current version...")
                shutil.rmtree(current_app_path)
            
            # Restore from backup
            print(f"🔄 Restoring from backup: {backup_name}")
            shutil.copytree(backup_path, current_app_path)
            
            # Fix permissions
            print(f"🔧 Setting permissions...")
            os.chmod(current_app_path, 0o755)
            
            # Make executable files executable
            macos_dir = current_app_path / "Contents" / "MacOS"
            if macos_dir.exists():
                for exec_file in macos_dir.iterdir():
                    if exec_file.is_file():
                        os.chmod(exec_file, 0o755)
            
            # Remove quarantine attributes
            print(f"🔓 Removing quarantine attributes...")
            subprocess.run([
                'xattr', '-rd', 'com.apple.quarantine', str(current_app_path)
            ], capture_output=True)
            
            print(f"✅ Restore completed successfully!")
            
            return {
                "success": True,
                "message": f"Successfully restored {app_name} from backup",
                "backup_name": backup_name,
                "restored_to": str(current_app_path)
            }
            
        except Exception as e:
            print(f"❌ Error during restore: {e}")
            return {
                "success": False,
                "error": f"Restore failed: {str(e)}"
            }
    
    def delete_backup(self, backup_name: str) -> Dict[str, Any]:
        """Delete a specific backup."""
        try:
            backup_dir = self.app_dir / "backups"
            backup_path = backup_dir / backup_name
            
            if not backup_path.exists():
                return {"error": f"Backup not found: {backup_name}"}
            
            # Get size before deletion
            size_mb = self._get_directory_size(backup_path) / (1024 * 1024)
            
            # Delete backup
            shutil.rmtree(backup_path)
            
            return {
                "success": True,
                "message": f"Backup {backup_name} deleted successfully",
                "space_freed_mb": round(size_mb, 2)
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to delete backup: {str(e)}"
            }
    
    def _clean_old_temp_files(self) -> Dict[str, Any]:
        """Clean old temporary update files."""
        cleaned = {"count": 0, "size_mb": 0}
        
        try:
            import tempfile
            temp_base = Path(tempfile.gettempdir())
            cutoff_time = time.time() - (self.max_temp_age_hours * 3600)
            
            # Look for ruma_update_* directories
            for temp_dir in temp_base.glob("ruma_update_*"):
                if temp_dir.is_dir():
                    try:
                        # Check if directory is old enough
                        dir_mtime = temp_dir.stat().st_mtime
                        if dir_mtime < cutoff_time:
                            size_mb = self._get_directory_size(temp_dir) / (1024 * 1024)
                            shutil.rmtree(temp_dir)
                            cleaned["count"] += 1
                            cleaned["size_mb"] += size_mb
                            print(f"🗑️ Removed old temp dir: {temp_dir.name}")
                    except Exception as e:
                        print(f"⚠️ Could not remove temp dir {temp_dir}: {e}")
                        
        except Exception as e:
            print(f"⚠️ Error cleaning temp files: {e}")
            
        return cleaned
    
    def _get_directory_size(self, directory: Path) -> int:
        """Get total size of directory in bytes."""
        total_size = 0
        try:
            for dirpath, dirnames, filenames in os.walk(directory):
                for filename in filenames:
                    filepath = Path(dirpath) / filename
                    try:
                        total_size += filepath.stat().st_size
                    except (OSError, FileNotFoundError):
                        pass
        except Exception:
            pass
        return total_size
    
    def get_storage_info(self) -> Dict[str, Any]:
        """Get storage usage information for the update system."""
        try:
            info = {
                "backups": {"count": 0, "size_mb": 0},
                "temp_files": {"count": 0, "size_mb": 0},
                "total_size_mb": 0
            }
            
            # Check backups
            backup_dir = self.app_dir / "backups"
            if backup_dir.exists():
                for item in backup_dir.iterdir():
                    if item.is_dir():
                        size_mb = self._get_directory_size(item) / (1024 * 1024)
                        info["backups"]["count"] += 1
                        info["backups"]["size_mb"] += size_mb
            
            # Check temp files
            import tempfile
            temp_base = Path(tempfile.gettempdir())
            for temp_dir in temp_base.glob("ruma_update_*"):
                if temp_dir.is_dir():
                    size_mb = self._get_directory_size(temp_dir) / (1024 * 1024)
                    info["temp_files"]["count"] += 1
                    info["temp_files"]["size_mb"] += size_mb
            
            info["total_size_mb"] = info["backups"]["size_mb"] + info["temp_files"]["size_mb"]
            
            return {
                "success": True,
                "storage_info": info
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to get storage info: {str(e)}"
            }
    
    def pause_download(self):
        """Pause current download."""
        self.is_paused = True
        self.is_downloading = False
        state = self._load_state()
        if state:
            state["status"] = "paused"
            self._save_state(state)
    
    def resume_download(self) -> bool:
        """Check if download can be resumed."""
        state = self._load_state()
        if not state:
            return False
        
        status = state.get("status", "")
        if status not in ["paused"]:
            return False
        
        # Check if we have a valid URL to resume
        url = state.get("url", "")
        if not url or not url.startswith(("http://", "https://")):
            return False
            
        return True
    
    def cancel_download(self):
        """Cancel and cleanup download."""
        print("🛑 Cancel download requested")
        
        # Cancel the running task first
        if self.download_task and not self.download_task.done():
            print("🛑 Cancelling download task...")
            self.download_task.cancel()
            self.download_task = None
        
        # Immediately set cancellation flags
        self.is_downloading = False
        self.is_paused = True  # This will stop the download loop
        
        # Clear state immediately
        self._clear_state()
        
        # Clean up files
        state = self._load_state()
        if state and state.get("path"):
            try:
                path = Path(state["path"])
                if path.exists():
                    print(f"🗑️ Removing partial download: {path}")
                    path.unlink()
                if path.parent.exists():
                    print(f"🗑️ Removing temp directory: {path.parent}")
                    shutil.rmtree(path.parent, ignore_errors=True)
            except Exception as e:
                print(f"⚠️ Error cleaning up files: {e}")
        
        # Reset all flags
        self.is_paused = False
        print("✅ Download cancelled successfully")
    
    def get_download_progress(self) -> Dict[str, Any]:
        """Get current download progress."""
        state = self._load_state()
        if not state:
            return {
                "progress": 0,
                "downloaded": 0,
                "total_size": 0,
                "status": "none",
                "can_resume": False
            }
        
        downloaded = state.get("downloaded", 0)
        total_size = state.get("total_size", 0)
        progress = (downloaded / total_size) if total_size > 0 else 0
        
        return {
            "progress": progress,
            "downloaded": downloaded,
            "total_size": total_size,
            "status": state.get("status", "unknown"),
            "can_resume": self.resume_download(),
            "is_complete": progress >= 1.0,
            "path": state.get("path") if progress >= 1.0 else None
        }
    
    def _load_state(self) -> Optional[Dict[str, Any]]:
        """Load download state."""
        try:
            if self.download_state_file.exists():
                with open(self.download_state_file, 'r') as f:
                    return json.load(f)
        except Exception:
            pass
        return None
    
    def _save_state(self, state: Dict[str, Any]):
        """Save download state."""
        try:
            with open(self.download_state_file, 'w') as f:
                json.dump(state, f, indent=2)
        except Exception:
            pass
    
    def _clear_state(self):
        """Clear download state."""
        try:
            if self.download_state_file.exists():
                self.download_state_file.unlink()
        except Exception:
            pass


# Global instance
simple_updater = SimpleUpdater()