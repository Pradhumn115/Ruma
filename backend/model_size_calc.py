from huggingface_hub import hf_hub_url
import requests
import humanize
from concurrent.futures import ThreadPoolExecutor, as_completed

def fetch_file_info(model_id, file, type_hint="mlx"):
    url = hf_hub_url(repo_id=model_id, filename=file)
    try:
        response = requests.head(url, allow_redirects=True, timeout=10)
        size = int(response.headers.get("Content-Length", 0))
    except Exception as e:
        print(f"Failed to get size for {file}: {e}")
        size = 0
    size_human = humanize.naturalsize(size, binary=False)
    
    if type_hint == "gguf":
        name = file.split(".gguf")[0].split("-")[-1]
        filename = file
    else:
        name = file
        filename = file
    print(name,size,size_human,filename)
    return name, size, size_human, filename

def process_model_files(model, model_type, files):
    model_size = {}
    model_filenames = {}
    total_size = 0
    gguf_files = [f for f in files if f.endswith(".gguf")]
    if not gguf_files:
        model_type="mlx"

    with ThreadPoolExecutor(max_workers=10) as executor:
        if model_type == "mlx":
            futures = [executor.submit(fetch_file_info, model.id, file, "mlx") for file in files]
            
            for future in as_completed(futures):
                name, size, size_human, _ = future.result()
                total_size += size
                print(f"{name}: {size_human}")
            print(f"\nTotal MLX model size: {humanize.naturalsize(total_size, binary=False)}")
            
            try:
                model_quant = str(model.config["quantization_config"]["bits"]) + "bit"
            
            except:
                model_quant = "N"
            
            model_size = {model_quant:str(total_size)}
        
        else:  # GGUF
            futures = [executor.submit(fetch_file_info, model.id, file, "gguf") for file in gguf_files]
            for future in as_completed(futures):
                name, size, size_human, filename = future.result()
                model_size[name] = str(size)
                model_filenames[filename] = str(size)
                print(f"{name}: {size_human}")
    
    print(model_size, model_filenames)
    
    return model_size, model_filenames
