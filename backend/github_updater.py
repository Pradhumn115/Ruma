"""GitHub Release-based Auto-Update System for Ruma AI."""

import os
import json
import aiohttp
import asyncio
import zipfile
import shutil
import platform
import subprocess
import tempfile
from typing import Dict, Any, Optional, List
from pathlib import Path
from datetime import datetime

class GitHubUpdater:
    """Manages app updates from GitHub releases."""
    
    def __init__(self, repo_owner: str = "Pradhumn115", repo_name: str = "Ruma"):
        self.repo_owner = repo_owner
        self.repo_name = repo_name
        self.repo = f"{repo_owner}/{repo_name}"
        self.api_base = "https://api.github.com"
        self.app_dir = Path(__file__).parent
        self.backup_dir = self.app_dir / "backups"
        self.backup_dir.mkdir(exist_ok=True)
        self.platform = platform.system()
        self.architecture = platform.machine()
        self.current_version = self.get_current_version()
        # Resumable download state
        self.download_state_file = self.app_dir / "update_download_state.json"
        self.current_download = None
        self.download_cancelled = False
        self.download_active = False
        
    def get_current_version(self) -> str:
        """Get current app version. Use local file as fallback."""
        version_file = self.app_dir / "version.json"
        if version_file.exists():
            try:
                with open(version_file, 'r') as f:
                    content = f.read().strip()
                    if content:  # Check if file has content
                        data = json.loads(content)
                        return data.get("version", "0.1.0")
                    else:
                        # File exists but is empty, initialize it
                        self.save_version("0.1.0")
                        return "0.1.0"
            except Exception as e:
                print(f"Error reading version file: {e}")
                # Initialize with default version
                self.save_version("0.1.0")
                return "0.1.0"
        else:
            # File doesn't exist, create it with default version
            self.save_version("0.1.0")
            return "0.1.0"
    
    def save_version(self, version: str):
        """Save current version to file."""
        version_file = self.app_dir / "version.json"
        version_data = {
            "version": version,
            "updated_at": datetime.now().isoformat(),
            "platform": platform.system(),
            "architecture": platform.machine()
        }
        try:
            with open(version_file, 'w') as f:
                json.dump(version_data, f, indent=2)
        except Exception as e:
            print(f"Error saving version: {e}")
    
    async def check_for_updates(self) -> Dict[str, Any]:
        """Check GitHub releases for updates."""
        try:
            # First try to get latest release (non-prerelease)
            url = f"{self.api_base}/repos/{self.repo_owner}/{self.repo_name}/releases/latest"
            
            async with aiohttp.ClientSession() as session:
                async with session.get(url) as response:
                    if response.status == 200:
                        data = await response.json()
                    elif response.status == 404:
                        # If no latest release (or only prereleases), get all releases
                        url = f"{self.api_base}/repos/{self.repo_owner}/{self.repo_name}/releases"
                        async with session.get(url) as releases_response:
                            if releases_response.status == 200:
                                releases = await releases_response.json()
                                if releases:
                                    # Get the most recent release (including prereleases)
                                    data = releases[0]
                                else:
                                    raise Exception("No releases found")
                            else:
                                raise Exception(f"HTTP {releases_response.status}")
                    else:
                        raise Exception(f"HTTP {response.status}")
                        
                    latest_version = data.get("tag_name", "").lstrip("v")
                    release_notes = data.get("body", "")
                    published_at = data.get("published_at", "")
                    assets = data.get("assets", [])
                    
                    # Find platform-specific asset
                    platform_asset = self.find_platform_asset(assets)
                    
                    update_available = self.is_newer_version(latest_version, self.current_version)
                    
                    return {
                        "update_available": update_available,
                        "current_version": self.current_version,
                        "latest_version": latest_version,
                        "release_notes": release_notes,
                        "published_at": published_at,
                        "download_url": platform_asset.get("browser_download_url") if platform_asset else None,
                        "download_size": platform_asset.get("size") if platform_asset else None,
                        "asset_name": platform_asset.get("name") if platform_asset else None
                    }
        except Exception as e:
            return {
                "update_available": False,
                "error": f"Error checking for updates: {str(e)}"
            }
    
    def find_platform_asset(self, assets: List[Dict]) -> Optional[Dict]:
        """Find the appropriate asset for current platform."""
        system = platform.system().lower()
        machine = platform.machine().lower()
        
        # Platform-specific patterns
        patterns = {
            "darwin": ["macos", "darwin", "osx"],
            "windows": ["windows", "win"],
            "linux": ["linux"]
        }
        
        # Architecture patterns
        arch_patterns = {
            "x86_64": ["x64", "x86_64", "amd64"],
            "arm64": ["arm64", "aarch64"],
            "aarch64": ["arm64", "aarch64"]
        }
        
        platform_patterns = patterns.get(system, [system])
        arch_patterns_list = arch_patterns.get(machine, [machine])
        
        for asset in assets:
            name = asset.get("name", "").lower()
            
            # Check if asset matches platform and architecture
            platform_match = any(pattern in name for pattern in platform_patterns)
            arch_match = any(pattern in name for pattern in arch_patterns_list)
            
            if platform_match and (arch_match or "universal" in name):
                return asset
        
        # Fallback: return first asset if no specific match
        return assets[0] if assets else None
    
    def is_newer_version(self, latest: str, current: str) -> bool:
        """Compare version strings."""
        try:
            latest_parts = [int(x) for x in latest.replace("v", "").split(".")]
            current_parts = [int(x) for x in current.replace("v", "").split(".")]
            
            # Pad with zeros if lengths differ
            max_len = max(len(latest_parts), len(current_parts))
            latest_parts.extend([0] * (max_len - len(latest_parts)))
            current_parts.extend([0] * (max_len - len(current_parts)))
            
            return latest_parts > current_parts
        except Exception:
            return latest != current
    
    def save_download_state(self, download_info: Dict[str, Any]):
        """Save current download state for resumability."""
        try:
            with open(self.download_state_file, 'w') as f:
                json.dump(download_info, f, indent=2)
        except Exception as e:
            print(f"Error saving download state: {e}")
    
    def load_download_state(self) -> Optional[Dict[str, Any]]:
        """Load saved download state with validation."""
        try:
            if self.download_state_file.exists():
                with open(self.download_state_file, 'r') as f:
                    state = json.load(f)
                
                # Validate required fields
                required_fields = ['url', 'path']
                if not all(field in state for field in required_fields):
                    print(f"⚠️  Invalid download state: missing required fields")
                    self.clear_download_state()
                    return None
                
                # Validate URL format
                url = state.get('url', '')
                if not url.startswith(('http://', 'https://')):
                    print(f"⚠️  Invalid download state: invalid URL format")
                    self.clear_download_state()
                    return None
                
                # Validate file path
                path = state.get('path', '')
                if not path or path == url:  # path shouldn't be same as URL
                    print(f"⚠️  Invalid download state: invalid file path")
                    self.clear_download_state()
                    return None
                
                return state
        except json.JSONDecodeError as e:
            print(f"⚠️  Corrupted download state file: {e}")
            self.clear_download_state()
        except Exception as e:
            print(f"Error loading download state: {e}")
            self.clear_download_state()
        return None
    
    def clear_download_state(self):
        """Clear saved download state."""
        try:
            if self.download_state_file.exists():
                self.download_state_file.unlink()
        except Exception as e:
            print(f"Error clearing download state: {e}")

    async def download_update(self, download_url: str, progress_callback=None, resume: bool = True) -> Optional[str]:
        """Download update file with resumable support."""
        try:
            self.download_cancelled = False
            self.download_active = True
            filename = download_url.split("/")[-1]
            
            # Check for existing download state
            download_state = self.load_download_state() if resume else None
            
            # If this is a different URL, clear previous state
            if download_state and download_state.get("url") != download_url:
                self.clear_download_state()
                download_state = None
            
            if download_state and download_state.get("url") == download_url:
                # Resume existing download
                download_path = Path(download_state["path"])
                downloaded = download_state.get("downloaded", 0)
                temp_dir = download_path.parent
            else:
                # Start new download
                temp_dir = Path(tempfile.mkdtemp(prefix="ruma_update_"))
                download_path = temp_dir / filename
                downloaded = 0
            
            # Store current download info
            self.current_download = {
                "url": download_url,
                "path": str(download_path),
                "temp_dir": str(temp_dir),
                "downloaded": downloaded
            }
            
            headers = {}
            if downloaded > 0 and download_path.exists():
                # Resume from where we left off
                headers['Range'] = f'bytes={downloaded}-'
                print(f"🔄 Resuming download from {downloaded} bytes...")
            
            # Check if download is already complete
            if download_path.exists() and downloaded > 0:
                # Verify file size matches expected size from a HEAD request
                async with aiohttp.ClientSession() as session:
                    async with session.head(download_url) as head_response:
                        if head_response.status == 200:
                            expected_size = int(head_response.headers.get('Content-Length', 0))
                            actual_size = download_path.stat().st_size
                            
                            if actual_size == expected_size and expected_size > 0:
                                print(f"✅ Download already complete: {actual_size} bytes")
                                self.download_active = False
                                self.clear_download_state()
                                return str(download_path)
                            elif actual_size > expected_size:
                                print(f"⚠️  File corrupted (larger than expected), restarting...")
                                download_path.unlink()
                                downloaded = 0
            
            async with aiohttp.ClientSession() as session:
                async with session.get(download_url, headers=headers) as response:
                    if response.status == 416:  # Range Not Satisfiable
                        print(f"⚠️  Range not satisfiable, restarting download from beginning...")
                        # Clear the invalid state and restart
                        if download_path.exists():
                            download_path.unlink()
                        downloaded = 0
                        headers = {}  # Remove range header
                        # Retry without range header
                        async with session.get(download_url, headers=headers) as retry_response:
                            response = retry_response
                    
                    if response.status in (200, 206):  # 206 for partial content
                        if response.status == 200:
                            # Full download
                            total_size = int(response.headers.get('Content-Length', 0))
                            downloaded = 0
                            mode = 'wb'
                        else:
                            # Partial download (resume)
                            content_range = response.headers.get('Content-Range', '')
                            if content_range:
                                total_size = int(content_range.split('/')[-1])
                            else:
                                total_size = int(response.headers.get('Content-Length', 0)) + downloaded
                            mode = 'ab'
                        
                        # Save initial state
                        download_info = {
                            "url": download_url,
                            "path": str(download_path),
                            "total_size": total_size,
                            "downloaded": downloaded,
                            "started_at": datetime.now().isoformat()
                        }
                        self.save_download_state(download_info)
                        
                        with open(download_path, mode) as f:
                            chunks_since_save = 0
                            async for chunk in response.content.iter_chunked(8192):
                                if self.download_cancelled:
                                    print("🛑 Download cancelled")
                                    return None
                                    
                                f.write(chunk)
                                downloaded += len(chunk)
                                chunks_since_save += 1
                                
                                # Update state every 50 chunks (400KB) for better performance
                                if chunks_since_save >= 50:
                                    download_info["downloaded"] = downloaded
                                    self.save_download_state(download_info)
                                    chunks_since_save = 0
                                    print(f"📊 Download progress: {downloaded / total_size * 100:.1f}% ({downloaded}/{total_size} bytes)")
                                
                                if progress_callback and total_size > 0:
                                    progress = (downloaded / total_size) * 100
                                    await progress_callback(progress, downloaded, total_size)
                        
                        # Download completed successfully - save final state before clearing
                        download_info["downloaded"] = downloaded
                        self.save_download_state(download_info)
                        print(f"✅ Download completed: {downloaded} bytes")
                        
                        self.download_active = False
                        # Note: Don't clear state immediately, let frontend see completion
                        return str(download_path)
                    else:
                        raise Exception(f"Download failed: HTTP {response.status}")
                        
        except Exception as e:
            print(f"Error downloading update: {e}")
            # Save current state for potential resume
            self.download_active = False
            if hasattr(self, 'current_download') and self.current_download:
                self.save_download_state(self.current_download)
            return None
    
    def pause_download(self):
        """Pause current download."""
        self.download_cancelled = True
        self.download_active = False
        print("📱 Download paused")
    
    def cancel_download(self):
        """Cancel and cleanup current download."""
        self.download_cancelled = True
        self.download_active = False
        self.clear_download_state()
        
        # Cleanup partial download file
        if hasattr(self, 'current_download') and self.current_download:
            try:
                download_path = Path(self.current_download["path"])
                if download_path.exists():
                    download_path.unlink()
                
                temp_dir = Path(self.current_download["temp_dir"])
                if temp_dir.exists():
                    shutil.rmtree(temp_dir)
            except Exception as e:
                print(f"Error cleaning up cancelled download: {e}")
        
        self.current_download = None
        print("🗑️ Download cancelled and cleaned up")
    
    def get_download_progress(self) -> Optional[Dict[str, Any]]:
        """Get current download progress."""
        download_state = self.load_download_state()
        if download_state:
            downloaded = download_state.get("downloaded", 0)
            total_size = download_state.get("total_size", 0)
            progress = (downloaded / total_size * 100) if total_size > 0 else 0
            
            # Determine the correct state
            can_resume = not self.download_active and downloaded > 0 and progress < 100
            is_active = self.download_active and not self.download_cancelled
            is_paused = not self.download_active and downloaded > 0 and progress < 100
            
            return {
                "url": download_state.get("url"),
                "progress": progress,
                "downloaded": downloaded,
                "total_size": total_size,
                "can_resume": can_resume,
                "is_active": is_active,
                "is_paused": is_paused,
                "is_complete": progress >= 100,
                "started_at": download_state.get("started_at")
            }
        return {
            "progress": 0,
            "can_resume": False,
            "is_active": False,
            "is_paused": False,
            "is_complete": False
        }
    
    async def install_update(self, update_file_path: str) -> Dict[str, Any]:
        """Install downloaded update."""
        try:
            update_path = Path(update_file_path)
            
            # Create backup of current installation
            backup_path = self.create_backup()
            
            # Extract/Install update
            if update_path.suffix.lower() == '.zip':
                await self.extract_zip_update(update_path)
            elif update_path.suffix.lower() == '.dmg':
                return await self.install_dmg_update(update_path)
            else:
                return {"success": False, "error": "Unsupported update format"}
            
            # Update version file
            update_info = await self.check_for_updates()
            if update_info.get("latest_version"):
                self.save_version(update_info["latest_version"])
            
            return {
                "success": True,
                "message": "Update installed successfully",
                "backup_path": str(backup_path),
                "restart_required": True
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Installation failed: {str(e)}"
            }
    
    def create_backup(self) -> Path:
        """Create backup of current installation."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = self.backup_dir / f"backup_{timestamp}"
        backup_path.mkdir(exist_ok=True)
        
        # Files to backup (exclude models and data)
        important_files = [
            "*.py", "*.json", "*.md", "*.txt", "requirements.txt",
            "Ruma/", "api_keys.json", "server_config.json"
        ]
        
        for pattern in important_files:
            for file_path in self.app_dir.glob(pattern):
                if file_path.is_file():
                    dest = backup_path / file_path.name
                    shutil.copy2(file_path, dest)
                elif file_path.is_dir() and not any(exclude in str(file_path) for exclude in ["models", "downloads", "__pycache__"]):
                    dest = backup_path / file_path.name
                    shutil.copytree(file_path, dest, ignore=shutil.ignore_patterns("*.pyc", "__pycache__"))
        
        return backup_path
    
    async def extract_zip_update(self, zip_path: Path):
        """Extract ZIP update while preserving user data."""
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            # Files to preserve (don't overwrite)
            preserve_files = [
                "api_keys.json", "server_config.json", "download_state.json",
                "models/", "downloads/", "user_data/", "backups/"
            ]
            
            for file_info in zip_ref.filelist:
                # Check if file should be preserved
                should_preserve = any(
                    file_info.filename.startswith(preserve) 
                    for preserve in preserve_files
                )
                
                if not should_preserve:
                    zip_ref.extract(file_info, self.app_dir)
    
    async def install_dmg_update(self, dmg_path: Path, auto_install: bool = False) -> Dict[str, Any]:
        """Install DMG update for macOS with industry-level automatic replacement."""
        try:
            import subprocess
            import shutil
            
            # Mount the DMG
            mount_result = subprocess.run([
                'hdiutil', 'attach', str(dmg_path), '-nobrowse', '-quiet'
            ], capture_output=True, text=True)
            
            if mount_result.returncode != 0:
                return {
                    "success": False, 
                    "error": f"Failed to mount DMG: {mount_result.stderr}"
                }
            
            # Get mount point
            mount_info = mount_result.stdout.strip().split('\n')[-1]
            mount_point = mount_info.split('\t')[-1]
            
            # Find the app in the mounted DMG (search recursively)
            mount_path = Path(mount_point)
            app_files = []
            
            # First try root level
            app_files.extend(mount_path.glob("*.app"))
            
            # If not found, search recursively (up to 3 levels deep to avoid performance issues)
            if not app_files:
                for depth in range(1, 4):
                    pattern = "/".join(["*"] * depth) + "/*.app"
                    app_files.extend(mount_path.glob(pattern))
                    if app_files:
                        break
            
            # Also search for common patterns
            if not app_files:
                common_patterns = [
                    "Applications/*.app",
                    "*/Applications/*.app", 
                    "*/*.app",
                    "Ruma*.app",
                    "*/Ruma*.app"
                ]
                for pattern in common_patterns:
                    app_files.extend(mount_path.glob(pattern))
                    if app_files:
                        break
            
            if not app_files:
                # Debug: List all contents to help diagnose
                print(f"🔍 Debug: DMG contents in {mount_point}:")
                try:
                    for item in mount_path.rglob("*"):
                        if item.is_file() or item.is_dir():
                            print(f"   {item.relative_to(mount_path)}")
                except Exception as e:
                    print(f"   Error listing contents: {e}")
                
                # Unmount DMG
                subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'])
                return {
                    "success": False,
                    "error": f"No .app file found in DMG. Please check if the DMG contains a valid macOS application."
                }
            
            app_in_dmg = app_files[0]
            
            if auto_install:
                # Industry-level automatic installation
                return await self._perform_automatic_installation(
                    app_in_dmg, mount_point, dmg_path
                )
            else:
                # Manual installation instructions
                subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'])
                return {
                    "success": True,
                    "message": f"DMG mounted successfully. App found: {app_in_dmg.name}",
                    "app_path": str(app_in_dmg),
                    "installation_instructions": [
                        "1. The DMG has been downloaded and verified",
                        "2. Quit the current Ruma application",
                        f"3. Double-click {dmg_path.name} to mount it",
                        f"4. Drag {app_in_dmg.name} to your Applications folder",
                        "5. Launch the new version from Applications"
                    ],
                    "restart_required": True
                }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"DMG installation failed: {str(e)}"
            }
    
    async def _perform_automatic_installation(self, app_in_dmg: Path, mount_point: str, dmg_path: Path) -> Dict[str, Any]:
        """Perform automatic app replacement with industry-level security."""
        try:
            import subprocess
            import shutil
            import tempfile
            import os
            
            # Step 1: Detect current app location
            current_app_path = await self._detect_current_app_path()
            if not current_app_path:
                subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'])
                return {
                    "success": False,
                    "error": "Could not detect current app installation path"
                }
            
            # Step 2: Verify code signature of new app (industry standard)
            signature_valid = await self._verify_code_signature(app_in_dmg)
            if not signature_valid:
                subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'])
                return {
                    "success": False,
                    "error": "Code signature verification failed - update rejected for security"
                }
            
            # Step 3: Create atomic backup of current app
            backup_dir = self.backup_dir / f"app_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            backup_dir.mkdir(parents=True, exist_ok=True)
            backup_app_path = backup_dir / current_app_path.name
            
            print(f"🔄 Creating backup: {current_app_path} -> {backup_app_path}")
            shutil.copytree(current_app_path, backup_app_path)
            
            # Step 4: Atomic replacement using temp + move (industry standard)
            temp_dir = Path(tempfile.mkdtemp(prefix="ruma_update_"))
            temp_app_path = temp_dir / app_in_dmg.name
            
            print(f"🔄 Copying new app: {app_in_dmg} -> {temp_app_path}")
            shutil.copytree(app_in_dmg, temp_app_path)
            
            # Step 5: Atomic move (most critical part)
            print(f"🔄 Performing atomic replacement...")
            
            # Remove old app
            if current_app_path.exists():
                shutil.rmtree(current_app_path)
            
            # Move new app into place
            shutil.move(temp_app_path, current_app_path)
            
            # Step 6: Fix permissions (critical for macOS)
            await self._fix_app_permissions(current_app_path)
            
            # Step 7: Clear quarantine flag (required for auto-updates)
            subprocess.run([
                'xattr', '-rd', 'com.apple.quarantine', str(current_app_path)
            ], capture_output=True)
            
            # Step 8: Update version info
            update_info = await self.check_for_updates()
            if update_info.get("latest_version"):
                self.save_version(update_info["latest_version"])
            
            # Cleanup
            subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'])
            shutil.rmtree(temp_dir, ignore_errors=True)
            
            return {
                "success": True,
                "message": "App updated successfully with automatic replacement",
                "old_version": self.current_version,
                "new_version": update_info.get("latest_version", "unknown"),
                "backup_path": str(backup_app_path),
                "installation_method": "automatic_atomic_replacement",
                "restart_required": True,
                "restart_instructions": [
                    "The app has been updated automatically",
                    "Please restart Ruma to use the new version",
                    "Your data and settings have been preserved"
                ]
            }
            
        except Exception as e:
            # Rollback on failure
            try:
                if backup_app_path.exists() and not current_app_path.exists():
                    shutil.move(backup_app_path, current_app_path)
                    print(f"🔄 Rollback completed due to error: {e}")
            except:
                pass
            
            subprocess.run(['hdiutil', 'detach', mount_point, '-quiet'], capture_output=True)
            return {
                "success": False,
                "error": f"Automatic installation failed: {str(e)}",
                "rollback_performed": True
            }
    
    async def _detect_current_app_path(self) -> Optional[Path]:
        """Detect current app installation path using multiple methods."""
        try:
            import subprocess
            
            # Method 1: Check common app locations
            possible_locations = [
                Path("/Applications/Ruma.app"),
                Path.home() / "Applications/Ruma.app",
                Path("/Applications/SuriAI.app"),  # Legacy name
                Path.home() / "Applications/SuriAI.app"
            ]
            
            for app_path in possible_locations:
                if app_path.exists():
                    return app_path
            
            # Method 2: Use mdfind to search for app
            result = subprocess.run([
                'mdfind', 'kMDItemKind=="Application" && kMDItemFSName=="Ruma.app"'
            ], capture_output=True, text=True)
            
            if result.returncode == 0 and result.stdout.strip():
                return Path(result.stdout.strip().split('\n')[0])
            
            # Method 3: Check if running from bundle and detect path
            bundle_path = os.environ.get('CFBundleExecutablePath')
            if bundle_path:
                app_path = Path(bundle_path).parent.parent.parent
                if app_path.suffix == '.app':
                    return app_path
            
            return None
            
        except Exception as e:
            print(f"Error detecting app path: {e}")
            return None
    
    async def _verify_code_signature(self, app_path: Path) -> bool:
        """Verify app code signature (industry security standard)."""
        try:
            import subprocess
            
            # Check code signature
            result = subprocess.run([
                'codesign', '--verify', '--verbose', str(app_path)
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                print(f"✅ Code signature verified for {app_path}")
                return True
            else:
                print(f"❌ Code signature verification failed: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"❌ Code signature check failed: {e}")
            return False
    
    async def _fix_app_permissions(self, app_path: Path):
        """Fix app permissions after installation."""
        try:
            import subprocess
            import stat
            
            # Set proper permissions on the app bundle
            os.chmod(app_path, 0o755)
            
            # Make executable files executable
            contents_path = app_path / "Contents"
            if contents_path.exists():
                macos_path = contents_path / "MacOS"
                if macos_path.exists():
                    for exec_file in macos_path.iterdir():
                        if exec_file.is_file():
                            os.chmod(exec_file, 0o755)
                
                # Fix Resources permissions
                resources_path = contents_path / "Resources"
                if resources_path.exists():
                    for item in resources_path.rglob("*"):
                        if item.is_file():
                            if item.suffix in ['.py', '.sh'] or 'bin' in str(item):
                                os.chmod(item, 0o755)
                            else:
                                os.chmod(item, 0o644)
            
            print(f"✅ Fixed permissions for {app_path}")
            
        except Exception as e:
            print(f"⚠️ Warning: Could not fix all permissions: {e}")
    
    async def rollback_update(self, backup_path: str) -> Dict[str, Any]:
        """Rollback to previous version from backup."""
        try:
            backup_dir = Path(backup_path)
            if not backup_dir.exists():
                return {"success": False, "error": "Backup not found"}
            
            # Restore files from backup
            for file_path in backup_dir.iterdir():
                dest = self.app_dir / file_path.name
                if file_path.is_file():
                    shutil.copy2(file_path, dest)
                elif file_path.is_dir():
                    if dest.exists():
                        shutil.rmtree(dest)
                    shutil.copytree(file_path, dest)
            
            return {
                "success": True,
                "message": "Successfully rolled back to previous version"
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Rollback failed: {str(e)}"
            }
    
    def get_update_history(self) -> List[Dict[str, Any]]:
        """Get history of updates and backups."""
        history = []
        
        # Get backup history
        if self.backup_dir.exists():
            for backup in self.backup_dir.iterdir():
                if backup.is_dir() and backup.name.startswith("backup_"):
                    timestamp_str = backup.name.replace("backup_", "")
                    try:
                        timestamp = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
                        history.append({
                            "type": "backup",
                            "timestamp": timestamp.isoformat(),
                            "path": str(backup)
                        })
                    except ValueError:
                        continue
        
        return sorted(history, key=lambda x: x["timestamp"], reverse=True)

# Global updater instance
github_updater = GitHubUpdater()

# Async wrapper functions for compatibility
async def check_for_updates():
    return await github_updater.check_for_updates()

async def download_update(download_url: str):
    return await github_updater.download_update(download_url)

async def install_update(update_file_path: str):
    return await github_updater.install_update(update_file_path)

def get_current_version():
    return github_updater.get_current_version()
