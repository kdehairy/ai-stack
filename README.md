# My AI Stack

## Architecture Overview

This is a Docker-based AI stack providing:
- llama.cpp inference server with AMD GPU support
- SearXNG web search mcp
- OpenWebUI interface
- Embedding service with Qdrant vector store and MCP server
- System monitoring with Prometheus metrics for both the machine and inference

## Run

### Start inference server, searxng & openWebUI
use systemd unit ai-stack.service

### Start embedding service
use systemd unit ai-embedding-stack.service

### Check service health
- llama: http://localhost:8080/health
- searxng: http://localhost:8080/healthz
- openwebui: http://localhost:8080/health
- llama-embedding: http://localhost:8080/health
- qdrant: http://localhost:6333/collections
- qdrant-mcp: http://localhost:3000/mcp

## Environment Variables (.env)

Critical variables for configuration:
- `LLAMA_MODEL_PATH` - Models directory (mounted as volume)
- `LLAMA_VERSION` - llama.cpp git branch
- `LLAMA_GPU_LAYERS` - GPU layers to offload (default 99)
- `LLAMA_CTX` - Context window size (default 131072)
- `LLAMA_REASONER_PORT` - Inference server port (default 8082)
- `OPENWEBUI_HOST` - WebUI port (default 3000)
- `SEARXNG_PORT` - Search proxy port (default 8888)

## GPU Configuration

It is specifically written for AMD ROCm with RX 7900 XTX. The start script finds GPU via:
1. `lspci` for PCIe bus ID
2. `rocm-smi --showbus` for ROCm device index

## Models

The main inference uses Qwen3-30B-A3B or GLM-4.7-Flash models in GGUF format.
Embedding uses Qwen3-Embedding-0.6B model.

## Services Overview

- **llama** (port 8082): Main inference server with GLM-4.7-Flash model
- **searxng** (port 8888): Web search proxy
- **openwebui** (port 3000): Chat interface with OpenAI-compatible API
- **llama-embedding** (port 8080): Embedding server for vector operations
- **qdrant** (port 6333): Vector database
- **qdrant-mcp** (port 3001): MCP server for code embedding

## Important Constraints

- Requires AMD ROCm installed at /opt/rocm (check with rocm-smi)
