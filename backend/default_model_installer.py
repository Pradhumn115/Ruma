"""Default model installer for Ruma AI."""

import os
import asyncio
from model_manager import ModelManager
from downloadManager import download_manager

DEFAULT_MODELS = {
    "primary": {
        "model_id": "mlx-community/Llama-3.2-3B-Instruct-4bit",
        "model_type": "mlx",
        "files": []
    },
    "fallback_gguf": {
        "model_id": "unsloth/Llama-3.2-1B-Instruct-GGUF",
        "model_type": "gguf", 
        "files": ["Llama-3.2-1B-Instruct-Q8_0.gguf"]
    }
}

class DefaultModelInstaller:
    """Handles automatic installation of default models."""
    
    def __init__(self):
        self.model_manager = ModelManager()
    
    async def ensure_default_model(self):
        """
        Ensure that at least one default model is available.
        Will attempt to download if none are found.
        """
        print("🔍 Checking for default models...")
        
        # Check primary default model first
        primary_model = DEFAULT_MODELS["primary"]
        availability = self.model_manager.is_model_available(primary_model["model_id"])
        
        if availability["available"]:
            print(f"✅ Primary default model found: {primary_model['model_id']}")
            return primary_model["model_id"]
        
        print(f"⚠️ Primary default model not found: {primary_model['model_id']}")
        
        # Check fallback model
        fallback_model = DEFAULT_MODELS["fallback_gguf"]
        availability = self.model_manager.is_model_available(fallback_model["model_id"])
        
        if availability["available"]:
            print(f"✅ Fallback default model found: {fallback_model['model_id']}")
            return fallback_model["model_id"]
        
        print(f"⚠️ No default models found locally.")
        print(f"🔄 Starting download of primary default model...")
        
        # Start download of primary model
        try:
            download_result = download_manager.start_download(
                primary_model["model_id"],
                primary_model["model_type"],
                primary_model["files"]
            )
            
            print(f"📦 Download started: {download_result}")
            
            # Wait for download to complete or make progress
            await self.wait_for_download_progress(primary_model["model_id"])
            
            return primary_model["model_id"]
            
        except Exception as e:
            print(f"❌ Failed to start download: {e}")
            return None
    
    async def wait_for_download_progress(self, model_id: str, timeout_minutes: int = 10):
        """
        Wait for download to make progress or complete.
        
        Args:
            model_id: Model being downloaded
            timeout_minutes: Maximum time to wait
        """
        unique_id = download_manager.generate_unique_id(model_id, "mlx", [])
        timeout_seconds = timeout_minutes * 60
        elapsed = 0
        check_interval = 5  # Check every 5 seconds
        
        print(f"⏳ Waiting for download progress (timeout: {timeout_minutes} minutes)...")
        
        while elapsed < timeout_seconds:
            try:
                progress = download_manager.get_progress(unique_id)
                
                if progress.get("error"):
                    print(f"❌ Download error: {progress['error']}")
                    break
                
                status = progress.get("status", "unknown")
                percentage = progress.get("percentage", 0)
                
                print(f"📊 Download status: {status} ({percentage:.1f}%)")
                
                if status == "ready":
                    print("✅ Download completed successfully!")
                    break
                elif status == "error":
                    print(f"❌ Download failed: {progress.get('error', 'Unknown error')}")
                    break
                elif percentage > 10:  # If we've made some progress
                    print(f"📈 Download in progress ({percentage:.1f}%), continuing...")
                    # We can return once we have some progress
                    # The model will continue downloading in the background
                    break
                
            except Exception as e:
                print(f"⚠️ Error checking download progress: {e}")
            
            await asyncio.sleep(check_interval)
            elapsed += check_interval
        
        if elapsed >= timeout_seconds:
            print(f"⏰ Download check timeout reached ({timeout_minutes} minutes)")

async def main():
    """Main function to test the installer."""
    installer = DefaultModelInstaller()
    result = await installer.ensure_default_model()
    print(f"Result: {result}")

if __name__ == "__main__":
    asyncio.run(main())