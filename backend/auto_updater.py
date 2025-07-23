"""
Auto-updater for Ruma AI Assistant.
Checks GitHub releases for updates and handles installation.
"""

import asyncio
import aiohttp
import json
import os
import subprocess
import tempfile
import zipfile
import shutil
from pathlib import Path
from typing import Dict, Any, Optional
import platform
import hashlib
from packaging import version

class AutoUpdater:
    """Handle automatic updates from GitHub releases."""
    
    def __init__(self, 
                 github_repo: str = "Pradhumn115/Ruma",
                 current_version: str = "0.1.0",
                 app_bundle_path: Optional[str] = None):
        self.github_repo = github_repo
        self.current_version = current_version
        self.app_bundle_path = app_bundle_path or self._get_app_bundle_path()
        self.github_api_url = f"https://api.github.com/repos/{github_repo}"
        
    def _get_app_bundle_path(self) -> str:
        """Get the current app bundle path."""
        if platform.system() == "Darwin":  # macOS
            # Try to detect if we're running from an app bundle
            current_path = Path(__file__).parent.absolute()
            
            # Check if we're inside an app bundle
            while current_path != current_path.parent:
                if current_path.name.endswith('.app'):
                    return str(current_path)
                current_path = current_path.parent
            
            # Fallback to assumed app bundle location
            return "/Applications/Ruma.app"
        
        return str(Path(__file__).parent.parent)
    
    async def check_for_updates(self) -> Dict[str, Any]:
        """Check if updates are available."""
        try:
            async with aiohttp.ClientSession() as session:
                # Get latest release info
                url = f"{self.github_api_url}/releases/latest"
                async with session.get(url) as response:
                    if response.status != 200:
                        return {
                            "update_available": False,
                            "error": f"Failed to check for updates: HTTP {response.status}"
                        }
                    
                    release_data = await response.json()
                    
                    latest_version = release_data.get("tag_name", "").lstrip("v")
                    release_notes = release_data.get("body", "")
                    published_at = release_data.get("published_at", "")
                    
                    # Compare versions
                    try:
                        is_newer = version.parse(latest_version) > version.parse(self.current_version)
                    except:
                        # Fallback string comparison
                        is_newer = latest_version != self.current_version
                    
                    result = {
                        "update_available": is_newer,
                        "current_version": self.current_version,
                        "latest_version": latest_version,
                        "release_notes": release_notes,
                        "published_at": published_at,
                        "download_url": None
                    }
                    
                    if is_newer:
                        # Find appropriate download asset
                        assets = release_data.get("assets", [])
                        download_asset = self._find_download_asset(assets)
                        
                        if download_asset:
                            result["download_url"] = download_asset["browser_download_url"]
                            result["download_size"] = download_asset.get("size", 0)
                            result["asset_name"] = download_asset.get("name", "")
                        else:
                            result["error"] = "No compatible download found for this platform"
                    
                    return result
                    
        except Exception as e:
            return {
                "update_available": False,
                "error": f"Error checking for updates: {str(e)}"
            }
    
    def _find_download_asset(self, assets: list) -> Optional[Dict[str, Any]]:
        """Find the appropriate download asset for the current platform."""
        system = platform.system().lower()
        machine = platform.machine().lower()
        
        # Define platform-specific patterns
        patterns = {
            "darwin": {
                "arm64": ["macos", "darwin", "arm64", "apple", "silicon"],
                "x86_64": ["macos", "darwin", "x64", "x86_64", "intel"]
            },
            "linux": {
                "x86_64": ["linux", "x64", "x86_64"],
                "arm64": ["linux", "arm64", "aarch64"]
            },
            "windows": {
                "amd64": ["windows", "win", "x64", "x86_64"],
                "arm64": ["windows", "win", "arm64"]
            }
        }
        
        # Look for assets matching current platform
        platform_patterns = patterns.get(system, {}).get(machine, [])
        
        for asset in assets:
            asset_name = asset.get("name", "").lower()
            
            # Check if asset matches platform
            if any(pattern in asset_name for pattern in platform_patterns):
                # Prefer .dmg for macOS, .exe/.msi for Windows, .AppImage/.deb/.rpm for Linux
                if system == "darwin" and asset_name.endswith(('.dmg', '.zip', '.app.zip')):
                    return asset
                elif system == "windows" and asset_name.endswith(('.exe', '.msi', '.zip')):
                    return asset
                elif system == "linux" and asset_name.endswith(('.appimage', '.deb', '.rpm', '.tar.gz')):
                    return asset
        
        # Fallback: return first asset if no specific match
        return assets[0] if assets else None
    
    async def download_update(self, download_url: str, progress_callback=None) -> Optional[str]:
        """Download the update file."""
        try:
            # Create temporary directory
            temp_dir = Path(tempfile.mkdtemp(prefix="ruma_update_"))
            filename = download_url.split("/")[-1]
            download_path = temp_dir / filename
            
            async with aiohttp.ClientSession() as session:
                async with session.get(download_url) as response:
                    if response.status != 200:
                        return None
                    
                    total_size = int(response.headers.get('content-length', 0))
                    downloaded = 0
                    
                    with open(download_path, 'wb') as file:
                        async for chunk in response.content.iter_chunked(8192):
                            file.write(chunk)
                            downloaded += len(chunk)
                            
                            if progress_callback and total_size > 0:
                                progress = (downloaded / total_size) * 100
                                await progress_callback(progress, downloaded, total_size)
            
            return str(download_path)
            
        except Exception as e:
            print(f"Error downloading update: {e}")
            return None
    
    async def install_update(self, update_file_path: str) -> Dict[str, Any]:
        """Install the downloaded update."""
        try:
            update_path = Path(update_file_path)
            
            if platform.system() == "Darwin":  # macOS
                return await self._install_macos_update(update_path)
            elif platform.system() == "Windows":
                return await self._install_windows_update(update_path)
            elif platform.system() == "Linux":
                return await self._install_linux_update(update_path)
            else:
                return {
                    "success": False,
                    "error": f"Unsupported platform: {platform.system()}"
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": f"Installation failed: {str(e)}"
            }
    
    async def _install_macos_update(self, update_path: Path) -> Dict[str, Any]:
        """Install update on macOS."""
        try:
            if update_path.suffix.lower() == '.dmg':
                # Mount DMG and copy app
                return await self._install_dmg(update_path)
            elif update_path.suffix.lower() == '.zip':
                # Extract ZIP and copy app
                return await self._install_zip(update_path)
            else:
                return {
                    "success": False,
                    "error": f"Unsupported update format: {update_path.suffix}"
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": f"macOS installation failed: {str(e)}"
            }
    
    async def _install_dmg(self, dmg_path: Path) -> Dict[str, Any]:
        """Install from DMG file."""
        try:
            # Mount the DMG
            mount_result = subprocess.run(
                ["hdiutil", "attach", str(dmg_path), "-nobrowse", "-quiet"],
                capture_output=True, text=True
            )
            
            if mount_result.returncode != 0:
                return {
                    "success": False,
                    "error": f"Failed to mount DMG: {mount_result.stderr}"
                }
            
            # Find mounted volume
            mount_point = None
            for line in mount_result.stdout.split('\n'):
                if '/Volumes/' in line:
                    mount_point = line.split('\t')[-1].strip()
                    break
            
            if not mount_point:
                return {
                    "success": False,
                    "error": "Could not find mounted volume"
                }
            
            # Find .app bundle in mounted volume
            mount_path = Path(mount_point)
            app_bundles = list(mount_path.glob("*.app"))
            
            if not app_bundles:
                # Unmount and return error
                subprocess.run(["hdiutil", "detach", mount_point, "-quiet"])
                return {
                    "success": False,
                    "error": "No app bundle found in DMG"
                }
            
            source_app = app_bundles[0]
            
            # Copy to Applications folder
            target_path = Path("/Applications") / source_app.name
            
            # Remove existing app if it exists
            if target_path.exists():
                shutil.rmtree(target_path)
            
            # Copy new app
            shutil.copytree(source_app, target_path)
            
            # Unmount DMG
            subprocess.run(["hdiutil", "detach", mount_point, "-quiet"])
            
            return {
                "success": True,
                "message": f"Successfully installed to {target_path}",
                "restart_required": True
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"DMG installation failed: {str(e)}"
            }
    
    async def _install_zip(self, zip_path: Path) -> Dict[str, Any]:
        """Install from ZIP file."""
        try:
            # Extract ZIP to temporary directory
            extract_dir = zip_path.parent / "extracted"
            extract_dir.mkdir(exist_ok=True)
            
            with zipfile.ZipFile(zip_path, 'r') as zip_file:
                zip_file.extractall(extract_dir)
            
            # Find .app bundle
            app_bundles = list(extract_dir.glob("**/*.app"))
            
            if not app_bundles:
                return {
                    "success": False,
                    "error": "No app bundle found in ZIP"
                }
            
            source_app = app_bundles[0]
            target_path = Path("/Applications") / source_app.name
            
            # Remove existing app if it exists
            if target_path.exists():
                shutil.rmtree(target_path)
            
            # Copy new app
            shutil.copytree(source_app, target_path)
            
            # Clean up
            shutil.rmtree(extract_dir)
            
            return {
                "success": True,
                "message": f"Successfully installed to {target_path}",
                "restart_required": True
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"ZIP installation failed: {str(e)}"
            }
    
    async def _install_windows_update(self, update_path: Path) -> Dict[str, Any]:
        """Install update on Windows."""
        try:
            if update_path.suffix.lower() in ['.exe', '.msi']:
                # Run installer
                process = subprocess.Popen([str(update_path)], shell=True)
                return {
                    "success": True,
                    "message": "Installer launched",
                    "restart_required": True
                }
            else:
                return {
                    "success": False,
                    "error": f"Unsupported update format: {update_path.suffix}"
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": f"Windows installation failed: {str(e)}"
            }
    
    async def _install_linux_update(self, update_path: Path) -> Dict[str, Any]:
        """Install update on Linux."""
        try:
            if update_path.suffix.lower() == '.appimage':
                # Make executable and replace current binary
                os.chmod(update_path, 0o755)
                
                # Copy to application directory
                app_dir = Path.home() / ".local" / "bin"
                app_dir.mkdir(parents=True, exist_ok=True)
                target_path = app_dir / "ruma"
                
                shutil.copy2(update_path, target_path)
                
                return {
                    "success": True,
                    "message": f"Successfully installed to {target_path}",
                    "restart_required": True
                }
            else:
                return {
                    "success": False,
                    "error": f"Unsupported update format: {update_path.suffix}"
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": f"Linux installation failed: {str(e)}"
            }
    
    def get_current_version(self) -> str:
        """Get current application version."""
        return self.current_version
    
    def set_current_version(self, version: str):
        """Set current application version."""
        self.current_version = version

# Global auto-updater instance
auto_updater = AutoUpdater()
