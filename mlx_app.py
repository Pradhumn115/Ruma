from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from MLXEngine import MLXLLM
import json
import asyncio
import uvicorn

current_streaming_task: asyncio.Task | None = None

app = FastAPI()

# Load the MLX model
mlx_engine = MLXLLM()
llm = mlx_engine.load_model()  # Load the model



# Data model for the /chat endpoint
class ChatRequest(BaseModel):
    input: str


@app.get("/")
def read_root():
    return {"message": "Welcome To Suri Ai, Experience the Power of Offline Personal Assistant"}


@app.post("/chat")
async def chat_endpoint(request: ChatRequest):
    global current_streaming_task
    user_message = request.input
    print(user_message)
    
    if current_streaming_task and not current_streaming_task.done():
        current_streaming_task.cancel()
        try:
            await current_streaming_task
        except asyncio.CancelledError:
            print("Previous streaming task cancelled")
    # llm_response = ""
    # for chunk in llm.stream(user_message):
    #     print(chunk.content, end="", flush=True)
    #     llm_response += chunk.content
    #     llm_response = llm_response.removeprefix("<|eot_id|>").removesuffix("<|eot_id|>")
    
    # async def generate():
    #     for chunk in llm.stream(user_message):
    #         print(chunk.content, end="", flush=True)
    #         json_chunk = json.dumps({"content": chunk.content})
    #         yield f"data: {json_chunk}\n\n"
    
    # Create a new streaming task
    
    async def generate_sse():
        try:
            for chunk in llm.stream(user_message):  # blocking generator
                json_chunk = json.dumps({"content": chunk.content})
                yield f"data: {json_chunk}\n\n"
                await asyncio.sleep(0)  # allow cancellation
        except asyncio.CancelledError:
            print("Streaming cancelled")
            raise

    # Assign the generator directly, no create_task
    current_streaming_task = asyncio.create_task(asyncio.sleep(0))  # dummy task to hold state
     
            

    
    # Simulated response logic
    # response_message = f"You said: {user_message}"

    return StreamingResponse(generate_sse(), media_type="text/event-stream")


if __name__ == "__main__":
    
    uvicorn.run(app, host="127.0.0.1", port=8000)