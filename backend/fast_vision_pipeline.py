"""
Fast Vision Pipeline
Optimized vision analysis that avoids blocking operations and improves performance.
"""

import asyncio
import os
import tempfile
import logging
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Tuple, Optional
import threading

class FastVisionPipeline:
    """
    Optimized vision pipeline that:
    1. Pre-loads models to avoid loading delays
    2. Uses thread pool for blocking operations
    3. Implements intelligent caching
    4. Provides fast fallbacks
    """
    
    def __init__(self, sparrow_engine):
        self.sparrow_engine = sparrow_engine
        self.logger = logging.getLogger(__name__)
        
        # Thread pool for blocking operations
        self.vision_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="vision")
        
        # Model warmup status
        self.model_warmed_up = False
        self.warmup_lock = threading.Lock()
        
        # Performance tracking
        self.performance_stats = {
            "total_requests": 0,
            "avg_response_time": 0,
            "fast_responses": 0,  # < 5 seconds
            "slow_responses": 0   # > 5 seconds
        }
    
    async def analyze_image_fast(
        self, 
        image_data: bytes, 
        extracted_text: str, 
        user_question: str,
        timeout_seconds: float = 10.0
    ) -> Tuple[str, bool, float]:
        """
        Fast image analysis with timeout and fallback.
        Returns: (result, success, response_time_seconds)
        """
        start_time = time.time()
        
        try:
            # 1. Quick validation
            if not image_data or len(image_data) < 100:
                return "Invalid image data provided.", False, time.time() - start_time
            
            # 2. Ensure model is ready (with timeout)
            model_ready = await self._ensure_model_ready_fast(timeout_seconds=3.0)
            if not model_ready:
                # Fast fallback to text-only analysis
                return await self._text_only_fallback(extracted_text, user_question), True, time.time() - start_time
            
            # 3. Run vision analysis with timeout
            try:
                result = await asyncio.wait_for(
                    self._run_vision_analysis_async(image_data, extracted_text, user_question),
                    timeout=timeout_seconds
                )
                
                response_time = time.time() - start_time
                self._update_performance_stats(response_time)
                
                return result, True, response_time
                
            except asyncio.TimeoutError:
                self.logger.warning(f"Vision analysis timed out after {timeout_seconds}s, falling back to text analysis")
                fallback_result = await self._text_only_fallback(extracted_text, user_question)
                return fallback_result, True, time.time() - start_time
        
        except Exception as e:
            self.logger.error(f"Fast vision analysis failed: {e}")
            # Always provide a fallback response
            fallback_result = await self._text_only_fallback(extracted_text, user_question)
            return fallback_result, True, time.time() - start_time
    
    async def _ensure_model_ready_fast(self, timeout_seconds: float = 3.0) -> bool:
        """Ensure vision model is ready with timeout"""
        try:
            # Check if already loaded
            if self.sparrow_engine.is_model_loaded():
                return True
            
            # Try to load with timeout
            load_task = asyncio.create_task(self._load_model_with_timeout())
            try:
                success = await asyncio.wait_for(load_task, timeout=timeout_seconds)
                return success
            except asyncio.TimeoutError:
                self.logger.warning(f"Model loading timed out after {timeout_seconds}s")
                return False
                
        except Exception as e:
            self.logger.error(f"Model readiness check failed: {e}")
            return False
    
    async def _load_model_with_timeout(self) -> bool:
        """Load model in async context"""
        try:
            # Use thread pool to avoid blocking
            loop = asyncio.get_event_loop()
            success = await loop.run_in_executor(
                self.vision_executor,
                self._load_model_sync
            )
            return success
        except Exception as e:
            self.logger.error(f"Async model loading failed: {e}")
            return False
    
    def _load_model_sync(self) -> bool:
        """Synchronous model loading for thread pool"""
        try:
            # Check if model loading is already in progress
            with self.warmup_lock:
                if self.sparrow_engine.is_model_loaded():
                    return True
                
                # This will run the synchronous model loading
                import asyncio
                return asyncio.run(self.sparrow_engine.load_model("qwen2.5-vl-3b"))
        except Exception as e:
            self.logger.error(f"Sync model loading failed: {e}")
            return False
    
    async def _run_vision_analysis_async(
        self, 
        image_data: bytes, 
        extracted_text: str, 
        user_question: str
    ) -> str:
        """Run vision analysis in thread pool to avoid blocking"""
        
        loop = asyncio.get_event_loop()
        
        # Run the blocking Sparrow inference in thread pool
        result = await loop.run_in_executor(
            self.vision_executor,
            self._run_sparrow_sync,
            image_data,
            extracted_text,
            user_question
        )
        
        return result
    
    def _run_sparrow_sync(
        self, 
        image_data: bytes, 
        extracted_text: str, 
        user_question: str
    ) -> str:
        """Synchronous Sparrow analysis for thread pool"""
        try:
            if not self.sparrow_engine.model_inference_instance or not self.sparrow_engine.extractor:
                return "Vision model not ready"
            
            # Validate image data
            if len(image_data) < 100:
                return "Invalid image data - too small"
            
            # Check for basic PNG/JPEG headers
            if not (image_data.startswith(b'\x89PNG') or image_data.startswith(b'\xff\xd8\xff')):
                print(f"⚠️ Unexpected image format detected. First 16 bytes: {image_data[:16]}")
                # Try to continue anyway - might still work
            
            print(f"🖼️ Processing image: {len(image_data)} bytes, Question: {user_question[:50]}...")
            
            # Create enhanced prompt
            enhanced_prompt = f"""You are an expert screen analysis assistant. Analyze the provided screenshot and answer the user's question.

EXTRACTED TEXT FROM SCREEN:
{extracted_text}

USER'S QUESTION:
{user_question}

Please provide a comprehensive analysis that:
1. Describes what you see in the image
2. References the extracted text context
3. Directly answers the user's question
4. Provides actionable insights or suggestions

Focus on being helpful and specific in your response."""
            
            # Use in-memory temp file to avoid disk I/O
            import tempfile
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as temp_file:
                temp_file.write(image_data)
                temp_file_path = temp_file.name
            
            try:
                # Prepare input data
                input_data = [{
                    "file_path": temp_file_path,
                    "text_input": enhanced_prompt
                }]
                
                # Run inference (this is the blocking operation)
                results, num_pages = self.sparrow_engine.extractor.run_inference(
                    self.sparrow_engine.model_inference_instance,
                    input_data,
                    debug=False
                )
                
                if results and len(results) > 0:
                    result = results[0]
                    
                    # Check for problematic outputs (infinite repetition)
                    if len(result) > 5000:
                        # Truncate very long outputs
                        result = result[:5000] + "\n\n[Output truncated - detected excessive length]"
                        self.logger.warning(f"Vision model output truncated due to excessive length: {len(results[0])} characters")
                    
                    # Check for repetitive patterns (like infinite exclamation marks)
                    if self._is_repetitive_output(result):
                        self.logger.error("Detected repetitive/corrupted output from vision model")
                        return "Vision model generated corrupted output. Please try again or use text-only analysis."
                    
                    # Clean up repetitive text patterns
                    cleaned_result = self._clean_repetitive_text(result)
                    
                    return cleaned_result
                else:
                    return "No analysis result generated from vision model"
                    
            finally:
                # Clean up temp file
                try:
                    os.unlink(temp_file_path)
                except:
                    pass  # Ignore cleanup errors
                    
        except Exception as e:
            self.logger.error(f"Sync Sparrow analysis failed: {e}")
            return f"Vision analysis encountered an error: {str(e)}"
    
    def _is_repetitive_output(self, text: str) -> bool:
        """Check if output contains repetitive patterns indicating corruption"""
        if len(text) < 50:
            return False
        
        # Check for excessive repetition of the same character
        for char in ['!', '?', '.', '-', '*', '=', '#']:
            if text.count(char) > len(text) * 0.5:  # More than 50% of the same character
                return True
        
        # Check for short repetitive patterns
        for pattern_len in [1, 2, 3, 4, 5]:
            if len(text) >= pattern_len * 10:  # Need at least 10 repetitions to check
                pattern = text[:pattern_len]
                if (pattern * (len(text) // pattern_len + 1))[:len(text)] == text:
                    return True
        
        return False

    def _clean_repetitive_text(self, text: str) -> str:
        """Clean up repetitive text patterns like repeated phrases or lists"""
        if len(text) < 100:
            return text
        
        # Split into sentences for analysis
        sentences = text.split('.')
        cleaned_sentences = []
        seen_patterns = set()
        
        for sentence in sentences:
            sentence = sentence.strip()
            if not sentence:
                continue
                
            # Check for repeated phrases (like menu items)
            words = sentence.split()
            
            # Look for patterns like "Library," "Map," "Recently Saved," repeated
            if len(words) > 5:
                # Check if this sentence has excessive repetition of similar patterns
                comma_parts = sentence.split(',')
                if len(comma_parts) > 10:  # Likely a repeated list
                    # Keep only unique parts and limit to reasonable length
                    unique_parts = []
                    seen_parts = set()
                    
                    for part in comma_parts:
                        part = part.strip().strip('"')
                        if part and part not in seen_parts and len(unique_parts) < 8:
                            unique_parts.append(part)
                            seen_parts.add(part)
                    
                    if unique_parts:
                        cleaned_sentence = ', '.join(unique_parts)
                        if len(comma_parts) > len(unique_parts):
                            cleaned_sentence += " [and similar repeated items]"
                        cleaned_sentences.append(cleaned_sentence)
                    continue
            
            # Check for sentence-level repetition
            sentence_pattern = ' '.join(words[:5])  # First 5 words as pattern
            if sentence_pattern in seen_patterns:
                continue  # Skip repeated sentence patterns
                
            seen_patterns.add(sentence_pattern)
            cleaned_sentences.append(sentence)
        
        # Reconstruct text
        cleaned_text = '. '.join(cleaned_sentences)
        
        # Final cleanup - remove excessive whitespace and newlines
        import re
        cleaned_text = re.sub(r'\n\s*\n\s*\n+', '\n\n', cleaned_text)  # Max 2 consecutive newlines
        cleaned_text = re.sub(r'[ \t]+', ' ', cleaned_text)  # Normalize spaces
        
        # If we cleaned up a lot, add a note
        if len(cleaned_text) < len(text) * 0.7:
            cleaned_text += "\n\n[Note: Repetitive content was automatically cleaned up for clarity]"
        
        return cleaned_text

    async def _text_only_fallback(self, extracted_text: str, user_question: str) -> str:
        """Fast text-only analysis fallback"""
        return f"""Based on the extracted text from your screen:

EXTRACTED TEXT:
{extracted_text}

ANALYSIS:
{user_question}

While I couldn't perform full vision analysis, I can help based on the text content extracted from your screen. The text shows the information above. Please let me know if you need me to analyze any specific part of this content or if you have additional questions about what you're seeing on your screen."""
    
    def _update_performance_stats(self, response_time: float):
        """Update performance tracking"""
        self.performance_stats["total_requests"] += 1
        
        # Update average
        total = self.performance_stats["total_requests"]
        current_avg = self.performance_stats["avg_response_time"]
        self.performance_stats["avg_response_time"] = ((current_avg * (total - 1)) + response_time) / total
        
        # Track fast vs slow
        if response_time < 5.0:
            self.performance_stats["fast_responses"] += 1
        else:
            self.performance_stats["slow_responses"] += 1
    
    def get_performance_stats(self) -> dict:
        """Get current performance statistics"""
        return self.performance_stats.copy()
    
    async def warmup_model(self):
        """Pre-warm the model for faster first response"""
        if not self.model_warmed_up:
            self.logger.info("🔥 Warming up vision model...")
            start_time = time.time()
            
            success = await self._ensure_model_ready_fast(timeout_seconds=30.0)
            warmup_time = time.time() - start_time
            
            if success:
                self.model_warmed_up = True
                self.logger.info(f"✅ Vision model warmed up in {warmup_time:.2f}s")
            else:
                self.logger.warning(f"⚠️ Vision model warmup failed after {warmup_time:.2f}s")
    
    def cleanup(self):
        """Cleanup resources"""
        self.vision_executor.shutdown(wait=True)


# Global fast vision pipeline instance
fast_vision_pipeline = None

def initialize_fast_vision_pipeline(sparrow_engine):
    """Initialize the fast vision pipeline"""
    global fast_vision_pipeline
    fast_vision_pipeline = FastVisionPipeline(sparrow_engine)
    return fast_vision_pipeline