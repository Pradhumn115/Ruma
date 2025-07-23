from fastapi import Query, HTTPException, APIRouter
from pydantic import BaseModel
from huggingface_hub import HfApi, list_repo_files, model_info, hf_hub_download
import os
import humanize
from datetime import datetime, timezone
from pprint import pprint

import frontmatter
from typing import List
import re
from html import unescape

app = APIRouter()

# Directory to store downloaded models is managed by downloadManager.py

# Initialize Hugging Face API
hf_api = HfApi()

# Legacy status functions removed - using modern download manager instead

def generate_unique_id(model_id: str, model_type: str, files: List[str]) -> str:
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


# Enhanced filtering configuration
ALLOWED_MODEL_TAGS = [
    "text-generation", "text2text-generation", "conversational",
    "question-answering", "summarization", "translation", 
    "text-to-image", "image-to-text", "image-classification",
    "feature-extraction", "sentence-similarity"
]

BLOCKED_REPOS = [
    "meta-llama/", "facebook/", "openai/", "anthropic/",
    "microsoft/DialoGPT", "google/", "deepmind/"
]

RESTRICTED_PREFIXES = ["meta-llama/", "facebook/", "openai/"]

def is_model_allowed(model) -> bool:
    """Check if model is allowed based on repository restrictions (more permissive now)"""
    model_id = model.id
    tags = model.tags or []
    
    # Check if model is from blocked repositories
    for blocked_repo in BLOCKED_REPOS:
        if model_id.startswith(blocked_repo):
            return False
    
    # Allow models with relevant tags or if it's a text generation model
    relevant_tags = [
        "text-generation", "text2text-generation", "conversational", 
        "question-answering", "summarization", "translation",
        "text-to-image", "image-to-text", "image-classification",
        "feature-extraction", "sentence-similarity", "fill-mask",
        "token-classification", "text-classification"
    ]
    
    # More permissive: allow if has any relevant tag OR if no specific pipeline tag (generic models)
    has_relevant_tag = any(tag in relevant_tags for tag in tags)
    has_no_pipeline_restriction = not any(tag.startswith("tabular") or tag.startswith("audio") or tag.startswith("video") for tag in tags)
    
    return has_relevant_tag or (has_no_pipeline_restriction and len(tags) < 5)

def validate_model_access_fast(model_id: str) -> bool:
    """Fast validation using only prefix checking to avoid API calls"""
    # Check against known restricted prefixes (no API call needed)
    for prefix in RESTRICTED_PREFIXES:
        if model_id.startswith(prefix):
            return False
    return True

def clean_readme_content(content: str) -> str:
    """Minimally clean README content to fix rendering issues while preserving structure"""
    if not content or content in ["No README available", "README not available"]:
        return content
    
    try:
        # Check if content is already mostly Markdown (has #, *, -, etc.)
        markdown_indicators = content.count('#') + content.count('**') + content.count('```') + content.count('[') + content.count('|')
        html_indicators = content.count('<') + content.count('>')
        
        # If it's already mostly Markdown, do minimal cleaning
        if markdown_indicators > html_indicators * 2:
            print(f"Content appears to be mostly Markdown already (MD: {markdown_indicators}, HTML: {html_indicators})")
            # Just decode HTML entities and return
            cleaned = unescape(content)
            return cleaned
        
        print(f"Content appears to have significant HTML (MD: {markdown_indicators}, HTML: {html_indicators}) - applying conversions")
        
        # Parse frontmatter if present
        try:
            post = frontmatter.loads(content)
            readme_content = post.content
            metadata = post.metadata
        except:
            readme_content = content
            metadata = {}
        
        # Convert common HTML entities
        readme_content = unescape(readme_content)
        
        # Only convert the most problematic HTML elements that break Markdown rendering
        
        # Convert headings (preserve structure)
        readme_content = re.sub(r'<h([1-6])(?:[^>]*)>(.*?)</h[1-6]>', lambda m: '\n' + '#' * int(m.group(1)) + ' ' + m.group(2).strip() + '\n', readme_content, flags=re.IGNORECASE | re.DOTALL)
        
        # Convert line breaks
        readme_content = re.sub(r'<br\s*/?>', '\n', readme_content, flags=re.IGNORECASE)
        
        # Convert basic formatting (be more conservative)
        readme_content = re.sub(r'<strong(?:[^>]*)>(.*?)</strong>', r'**\1**', readme_content, flags=re.IGNORECASE | re.DOTALL)
        readme_content = re.sub(r'<b(?:[^>]*)>(.*?)</b>', r'**\1**', readme_content, flags=re.IGNORECASE | re.DOTALL)
        readme_content = re.sub(r'<em(?:[^>]*)>(.*?)</em>', r'*\1*', readme_content, flags=re.IGNORECASE | re.DOTALL)
        readme_content = re.sub(r'<i(?:[^>]*)>(.*?)</i>', r'*\1*', readme_content, flags=re.IGNORECASE | re.DOTALL)
        
        # Convert links
        readme_content = re.sub(r'<a(?:[^>]*?)href=["\']([^"\'>]*)["\'](?:[^>]*?)>(.*?)</a>', r'[\2](\1)', readme_content, flags=re.IGNORECASE | re.DOTALL)
        
        # Convert simple paragraphs (but preserve complex structures)
        readme_content = re.sub(r'<p(?:[^>]*)>([^<]*?)</p>', r'\n\1\n', readme_content, flags=re.IGNORECASE)
        
        # Convert inline code
        readme_content = re.sub(r'<code(?:[^>]*)>([^<]*?)</code>', r'`\1`', readme_content, flags=re.IGNORECASE)
        
        # Convert simple lists (preserve complex nested lists)
        readme_content = re.sub(r'<li(?:[^>]*)>([^<]*?)</li>', r'- \1\n', readme_content, flags=re.IGNORECASE)
        
        # Remove only obviously problematic tags (preserve others that might be needed)
        problematic_tags = ['div', 'span', 'section', 'article', 'header', 'footer', 'nav']
        for tag in problematic_tags:
            readme_content = re.sub(f'<{tag}(?:[^>]*)>', '', readme_content, flags=re.IGNORECASE)
            readme_content = re.sub(f'</{tag}>', '', readme_content, flags=re.IGNORECASE)
        
        # Clean up excessive whitespace but preserve intentional spacing
        readme_content = re.sub(r'\n\s*\n\s*\n+', '\n\n', readme_content)
        readme_content = readme_content.strip()
        
        # Don't use mdformat as it might be too aggressive
        
        return readme_content
        
    except Exception as e:
        print(f"Error cleaning README content: {e}")
        # Return original content if cleaning fails
        return content

def validate_model_access(model_id: str) -> bool:
    """Validate if model is accessible (not gated or private) - only use when necessary"""
    try:
        # First do fast prefix check
        if not validate_model_access_fast(model_id):
            return False
            
        # Try to get model info to check accessibility (expensive operation)
        info = model_info(model_id)
        
        # Check if model is gated or private
        if hasattr(info, 'gated') and info.gated:
            return False
            
        if hasattr(info, 'private') and info.private:
            return False
                
        return True
    except Exception as e:
        print(f"Error validating model access for {model_id}: {e}")
        return False

@app.get("/search_models")
async def search_models(
    q: str = Query(..., alias="query"),
    model_type: str = Query(None),
    enable_filtering: bool = Query(True, description="Enable enhanced filtering for safe models")
):
    
    filter_model_type = model_type
    
    # Enhanced search with multiple relevant tags for better results
    if filter_model_type == 'all' or filter_model_type is None:
        # Search with text generation tags for LLM models
        results = hf_api.list_models(
            search=q, 
            tags=["text-generation", "conversational"], 
            sort="downloads", 
            direction=-1, 
            limit=20,  # Get more results to filter
            full=True
        )
    else:
        results = hf_api.list_models(
            search=q,
            tags=[filter_model_type],
            sort="downloads", 
            direction=-1, 
            limit=20,
            full=True
        )
    
    output = []
    for model in results:
        try:
            # Apply smart filtering if enabled
            if enable_filtering:
                if not is_model_allowed(model):
                    continue
                    
                # Use fast validation to avoid API calls during search
                if not validate_model_access_fast(model.id):
                    continue
            
            model_author = model.modelId.split('/')[0] if '/' in model.modelId else "unknown"
            model_name = model.modelId.split('/')[1] if '/' in model.modelId else model.modelId
            
            model_last_modified = model.last_modified
            now = datetime.now(timezone.utc)
            model_last_modified = humanize.naturaltime(now - model_last_modified)

            tags = model.tags or []
            
            # Enhanced model type detection
            detected_model_type = 'gguf'
            if "mlx" in tags or "safetensors" in tags:
                detected_model_type = "mlx"
            elif any(tag in ["text-to-image", "image-to-text"] for tag in tags):
                detected_model_type = "vision"
            
            # Additional metadata for better model information
            output.append({
                "modelId": model.id,
                "tags": tags,
                "downloads": model.downloads or 0,
                "likes": model.likes or 0,
                "lastModified": model_last_modified,
                "author": model_author,
                "modelName" : model_name,
                "modelType" : detected_model_type,
                "isGated": getattr(model, 'gated', False),
                "isPrivate": getattr(model, 'private', False),
                "library": getattr(model, 'library_name', None),
                "pipeline_tag": getattr(model, 'pipeline_tag', None)
            })
            
            # Limit final results to 10 high-quality models
            if len(output) >= 10:
                break
                
        except Exception as e:
            print(f"Error processing model {model.id}: {e}")
            continue

    return output


class ModelRequest(BaseModel):
    model_id: str
    


@app.post("/search_one_model_in_detail")
def search_one_model_in_detail(request:ModelRequest):
    from model_size_calc import process_model_files
    
    try:
        # Validate model access before processing
        if not validate_model_access(request.model_id):
            raise HTTPException(
                status_code=403, 
                detail=f"Model {request.model_id} is not accessible or requires authentication"
            )
        
        model = model_info(request.model_id)
        pprint(model)
        
        # Enhanced file listing with error handling
        try:
            files = list_repo_files(model.id)
        except Exception as e:
            print(f"Error listing files for {request.model_id}: {e}")
            raise HTTPException(
                status_code=404,
                detail=f"Cannot access files for model {request.model_id}. Model may be gated or private."
            )
        
        gguf_files = [f for f in files if f.endswith(".gguf")]
        model_type="gguf"
        if not gguf_files:
            model_type="mlx"

        model_size, model_filenames = process_model_files(model, model_type, files)
        print(request.model_id, model_size)
        
        # Validate model sizes to catch incorrect metadata
        if not model_size or all(size == "0" for size in model_size.values()):
            print(f"Warning: Model {request.model_id} has invalid size metadata")
            # Still continue but mark as potentially problematic
            
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error processing model details for {request.model_id}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error processing model {request.model_id}: {str(e)}"
        )
    
    # Safely read README with proper error handling
    readme_content = "No README available"
    readme_path = None
    
    try:
        readme_path = hf_hub_download(
            repo_id=model.id,
            filename="README.md"
        )

        with open(readme_path, "r", encoding="utf-8") as f:
            raw_content = f.read()
            print(f"\n=== RAW README CONTENT for {request.model_id} ===")
            print(f"Length: {len(raw_content)} characters")
            print(f"First 500 chars: {raw_content[:500]}")
            print("=== END RAW CONTENT ===")
            
            readme_content = clean_readme_content(raw_content)
            
            print(f"\n=== CLEANED README CONTENT ===")
            print(f"Length: {len(readme_content)} characters")
            print(f"First 500 chars: {readme_content[:500]}")
            print("=== END CLEANED CONTENT ===")
    except Exception as e:
        print(f"Could not read README for {request.model_id}: {e}")
        readme_content = "README not available"
    finally:
        if readme_path and os.path.exists(readme_path):
            try:
                os.remove(readme_path)
            except:
                pass  # Ignore cleanup errors

    # For GGUF models, include actual available files
    actual_gguf_files = []
    if model_type == "gguf" and gguf_files:
        for gguf_file in gguf_files:
            # Extract quantization type from filename
            file_parts = gguf_file.replace('.gguf', '').split('_')
            quant_type = "Unknown"
            if len(file_parts) > 1:
                quant_type = '_'.join(file_parts[-2:]) if len(file_parts) > 2 else file_parts[-1]
            
            actual_gguf_files.append({
                "filename": gguf_file,
                "quantization": quant_type,
                "display_name": f"{quant_type.replace('_', ' ').title()}"
            })
    
    output = {
        "modelId" : model.id,
        "modelSize" : model_size,
        "modelFilenames": model_filenames,
        "readme": readme_content,
        "actualFiles": actual_gguf_files,  # Add actual GGUF files available
        "modelType": model_type
    }
    
    return output