"""
Simple LLM Query Module
=======================

Clean, simple LLM query function that can be called from smart_memory_system.py
"""

def simple_query_llm(prompt: str) -> str:
    """Simple LLM query with clean stop mechanism"""
    try:
        from simple_background_control import should_stop_processing
        
        # Early check - don't even start if UI is active
        if should_stop_processing():
            print("⏹️ Skipping LLM query - UI is active")
            return ""
        
        from llm_provider import get_llm_provider
        llm_provider = get_llm_provider()
        llm = llm_provider.get_llm()
        
        if not llm:
            print("⚠️ LLM not available")
            return ""
        
        # Simple streaming with stop checks
        response = ""
        chunk_count = 0
        
        try:
            for chunk in llm.stream(prompt):
                # Check every 5 chunks
                if chunk_count % 5 == 0 and should_stop_processing():
                    print("⏹️ Stopping LLM query - UI became active")
                    break
                
                if hasattr(chunk, 'content'):
                    content = chunk.content
                else:
                    content = str(chunk)
                
                response += content
                chunk_count += 1
                
                # Simple limits
                if len(response) > 3000:
                    print("⚠️ Response length limit reached")
                    break
                
                if chunk_count > 200:
                    print("⚠️ Chunk limit reached")
                    break
            
            # Final check
            if should_stop_processing():
                print("⏹️ LLM query stopped - UI is active")
                return ""
            
            return response.strip()
            
        except Exception as e:
            print(f"❌ LLM streaming failed: {e}")
            return ""
    
    except Exception as e:
        print(f"❌ LLM query failed: {e}")
        return ""