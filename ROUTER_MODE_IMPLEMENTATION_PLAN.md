# llama.cpp Router Mode Implementation Plan

## Overview
This document outlines the plan to migrate the current llama.cpp service from single-model loading to router mode with models.ini configuration file for dynamic model management.

## Current Status
- **Service**: llama service (port 8082)
- **Model**: GLM-4.7-Flash-UD-Q4_K_XL.gguf
- **Command**: `llama-server --model /data/models/llamacpp/GLM-4.7-Flash/GLM-4.7-Flash-UD-Q4_K_XL.gguf`
- **Available Models**:
  - GLM-4.7-Flash (port 8082, currently active)
  - qwen3-30b-a3b
  - qwen3-coder-30b-a3b
  - qwen-embedding/Qwen3-Embedding-4B-Q4_K_M.gguf
  - qwen3-embedding-0.6b-q8_0/Qwen3-Embedding-0.6B-Q8_0.gguf

## Router Mode Overview
Router mode allows llama-server to act as a model dispatcher that can load and unload multiple models dynamically without restarting the service. Each model is defined in a configuration file (models.ini) and can be selected via the API by setting the `"model"` field.

## Key Requirements

### 1. models.ini Configuration File
- Must be placed in a dedicated Docker volume for separation of concerns
- Format: INI-style configuration
- Each section defines a model with specific parameters
- Section name becomes the model ID for API requests

### 2. Docker Volume for Configuration
- Create a new Docker volume named `llama-router-config`
- Mount to container at `/data/models/llamacpp/models.ini`
- Separate from model files volume to avoid any conflicts

### 3. Dockerfile Updates
- Ensure llama-server binary supports router mode flags
- Verify --models-preset and --models-dir flags are available
- Confirm build includes all necessary router mode support

### 4. docker-compose.yml Updates
- Remove `--model` parameter from command
- Add `--models-preset /data/models/llamacpp/models.ini`
- Keep all other parameters (GPU layers, context size, sampling parameters)
- Update health check to work with router mode
- Add volume mount for models.ini

### 5. Environment Variables
- Add models.ini path reference
- Keep existing model paths for backward compatibility

## Implementation Steps

### Step 1: Create models.ini Configuration
**Docker Volume**: `llama-router-config`

Create the models.ini file in a local directory first, then use docker volume mount:

**File**: `/home/kdehairy/git_tree/ai-stack/models.ini`

```ini
[glm4]
model = /data/models/llamacpp/GLM-4.7-Flash/GLM-4.7-Flash-UD-Q4_K_XL.gguf
ctx-size = 65536
n-gpu-layers = 99
threads = 8
temp = 1.0
min-p = 0.01
top-p = 0.95
top-k = 20
flash-attn = on
fit = on
split-mode = none
jinja = on
seed = 3407

[qwen3-30b-a3b]
model = /data/models/llamacpp/qwen3-30b-a3b/Qwen3-30B-A3B-Q4_K_M.gguf
ctx-size = 65536
n-gpu-layers = 99
threads = 8
temp = 1.0
min-p = 0.01
top-p = 0.95
top-k = 20
flash-attn = on
fit = on
split-mode = none
jinja = on
seed = 3407

[qwen3-coder-30b-a3b]
model = /data/models/llamacpp/qwen3-coder-30b-a3b/Qwen3-Coder-30B-A3B-Q4_K_M.gguf
ctx-size = 8192
n-gpu-layers = 99
threads = 8
temp = 0.0
min-p = 0.01
top-p = 0.95
top-k = 20
flash-attn = on
fit = on
split-mode = none
jinja = on
seed = 3407

[embedding]
model = /data/models/llamacpp/qwen-embedding/Qwen3-Embedding-4B-Q4_K_M.gguf
embedding = on
pooling = last
ubatch-size = 8192
n-gpu-layers = 0
ctx-size = 2048
```

**Notes**:
- Model paths must match the actual directory structure in the models volume
- Parameters should match current configuration values
- Each section name (e.g., `glm4`, `qwen3-30b-a3b`) becomes the model ID
- Can create separate sections for embedding if needed

### Step 2: Verify Dockerfile Support
**File**: `/home/kdehairy/git_tree/ai-stack/Dockerfile`

Current state:
```dockerfile
RUN cmake -B build \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS=gfx1100 \
    -DGGML_HIP_ROCWMMA_FATTN=ON \
    -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --config Release -j$(nproc) \
             --target llama-server llama-cli llama-bench
```

Expected behavior:
- Router mode support is included in llama-server binary from recent builds
- Check version: `llama-server --version`
- Verify --models-preset flag exists: `llama-server --help | grep models`

**Action**: Build with current master branch and verify router mode support.

### Step 3: Update docker-compose.yml
**File**: `/home/kdehairy/git_tree/ai-stack/docker-compose.yml`

**Changes to llama service**:

Current command:
```yaml
command: >
  --model /data/models/llamacpp/${LLAMA_REASONER_MODEL_FILE}
  --host 0.0.0.0
  --port 8080
  --metrics
  --n-gpu-layers ${LLAMA_GPU_LAYERS}
  -fa 1
  --split-mode none
  --fit on
  --flash-attn on
  --parallel 1
  --jinja
  --ctx-size ${LLAMA_CTX}
  --seed 3407
  --temp 1.0
  --min-p 0.01
  --top-p 0.95
  --top-k 20
  --repeat-penalty 1.0
```

New command:
```yaml
command: >
  --host 0.0.0.0
  --port 8080
  --models-preset /data/models/llamacpp/models.ini
  --metrics
  --n-gpu-layers ${LLAMA_GPU_LAYERS}
  -fa 1
  --split-mode none
  --fit on
  --flash-attn on
  --parallel 1
  --jinja
  --ctx-size ${LLAMA_CTX}
  --seed 3407
  --temp 1.0
  --min-p 0.01
  --top-p 0.95
  --top-k 20
  --repeat-penalty 1.0
```

**Volumes section update**:
```yaml
volumes:
  - ${LLAMA_MODEL_PATH}:/data/models/llamacpp:ro
  - llama-router-config:/data/models/llamacpp:ro
```

**Environment variables to add**:
```yaml
environment:
  - ROCR_VISIBLE_DEVICES=${GPU_DEVICE_IDX}
  - LLAMA_MODELS_PRESET=/data/models/llamacpp/models.ini
```

**Volumes definition**:
```yaml
volumes:
  openwebui-data:
    driver: local
  qdrant_storage:
    driver: local
  llama-router-config:
    driver: local
```

### Step 4: Update .env File
**File**: `/home/kdehairy/git_tree/ai-stack/.env`

Add model configuration reference:
```bash
# Router mode configuration
ROUTER_MODE_ENABLED=true
DEFAULT_MODEL=glm4
```

### Step 5: Test Router Mode Implementation

#### 5.1 Test Service Startup
```bash
# Stop existing service
docker compose down

# Start with router mode
./start-llama.sh

# Check service logs
docker logs -f ai-stack-llama-1
```

Expected output:
- Router mode detection
- Models loaded from models.ini
- Server listening on port 8082

#### 5.2 Test Model Listing
```bash
# List available models
curl http://localhost:8082/v1/models | jq '.data[].id'

# Expected output:
# "glm4"
# "qwen3-30b-a3b"
# "qwen3-coder-30b-a3b"
```

#### 5.3 Test Model Switching
```bash
# Test GLM-4.7 Flash model
curl http://localhost:8082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm4",
    "messages": [{"role": "user", "content": "Say hello"}]
  }'

# Test Qwen3-30B-A3B model
curl http://localhost:8082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-30b-a3b",
    "messages": [{"role": "user", "content": "Say hello"}]
  }'

# Test Qwen3-Coder-30B-A3B model
curl http://localhost:8082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-coder-30b-a3b",
    "messages": [{"role": "user", "content": "Write a Python hello world"}]
  }'
```

#### 5.4 Verify GPU Utilization
```bash
# Monitor GPU usage during model switch
rocm-smi

# Check that GPU usage changes when switching between models
```

#### 5.5 Test OpenWebUI Integration
- Verify OpenWebUI can see and use different models
- Test chat with different model selections
- Check for any routing errors

### Step 6: Documentation Updates

**File**: `AGENTS.md` (this file)
- Add section about router mode configuration
- Document models.ini format
- Explain how to add new models
- List available models and their IDs

**File**: `README.md`
- Update model selection instructions
- Document how to switch models via API
- Add router mode benefits

**File**: `models.ini` (this file)
- Comprehensive router mode guide
- Usage examples
- Troubleshooting tips

## Limitations and Considerations

### Known Limitations
1. **Single Model in Memory**: Only one model is loaded in VRAM at a time
2. **Reload Latency**: Model switching triggers a reload (3-10 seconds for 7B models)
3. **No Auto-Preloading**: No automatic model warming based on usage patterns
4. **Config Stability**: INI format may change between llama.cpp versions

### Recommendations
1. **Group Requests by Model**: To minimize reload overhead
2. **Keep Common Model Loaded**: Maintain frequently used models in memory
3. **Monitor GPU Usage**: Watch for model switch timing
4. **Test Before Production**: Validate with realistic workloads

## Security Considerations
1. **Access Control**: Ensure models.ini file permissions are restricted
2. **Model Paths**: Verify model file paths are correct and accessible
3. **Port Security**: Maintain current firewall rules
4. **API Key**: Keep OpenWebUI API key secure

## Rollback Plan
If router mode causes issues:
1. Revert docker-compose.yml changes
2. Restore previous command with --model parameter
3. Update models.ini (if created)
4. Rebuild Docker image if needed

## References
- [llama.cpp Router Mode Documentation](https://www.glukhov.org/llm-hosting/llama-cpp/llama-server-router-mode/)
- [llama.cpp Preset Documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/preset.md)
- [llama.cpp Server Documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [Hugging Face Model Management Blog](https://huggingface.co/blog/ggml-org/model-management-in-llamacpp)
