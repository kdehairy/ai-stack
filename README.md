# AI Stack

Complete Docker-based AI infrastructure for local LLM inference, search, chat interface, and vector embeddings with AMD GPU acceleration.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Client Layer                           │
│                   (Web Browser / API)                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      Nginx Reverse Proxy                    │
│  - model.cloud.home: llama inference (port 80)              │
│  - embedding.cloud.home: vector embeddings (port 80)        │
│  - websearch.cloud.home: searxng search (port 80)           │
│  - darwish.cloud.home: openwebui chat (port 80)             │
└────────────────────────┬────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
┌──────────────┐  ┌───────────────┐  ┌────────────────┐
│  llama.cpp   │  │  llama-embed  │  │   searxng      │
│  inference   │  │  embedding    │  │   search       │
│  (GPU:99%)   │  │  (GPU:offload)│  │  (internal)    │
│  port:8080   │  │  port:8080    │  │  port:8080     │
└──────┬───────┘  └──────┬────────┘  └───────┬────────┘
       │                 │                   │
       ▼                 ▼                   │
┌────────────────────────────────────────────────┐
│                Docker Compose Services         │
│  - llama: main inference (ports 127.0.0.1:8082)│
│  - llama-embedding: vectors (127.0.0.1:8081)   │
│  - searxng: local search proxy (127.0.0.1:8888)│
│  - openwebui: chat UI (127.0.0.1:3000)         │
│  - qdrant: vector DB (127.0.0.1:6333)          │
│  - qdrant-mcp: code indexing (127.0.0.1:3001)  │
└────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                      Nftables Firewall                       │
│  - LAN-only access: 192.168.50.0/24, 10.6.0.0/24             │
│  - SSH: port 22 only from LAN                                │
│  - HTTP: port 80, 443 only from anywhere                     │
│  - Monitoring: ports 5000 (AMD metrics), 9100 (node-exporter)│
└──────────────────────────────────────────────────────────────┘
```

### Component Relationships

- **llama → openwebui**: OpenWebUI calls llama for chat completion via OpenAI-compatible API
- **openwebui → searxng**: Web search integration fetches from searxng locally
- **llama-embedding → qdrant**: Embedding service generates vectors, stored in Qdrant
- **qdrant-mcp**: Indexes code and git history using both embedding service and Qdrant
- **nginx**: Reverse proxies traffic from domain-based URLs to localhost service ports
- **AMD GPU**: Shared across llama (99 layers) and llama-embedding (0 layers for inference, GPU for compute)

## What This Provides

- **Local LLM Inference**: GLM-4.7-Flash model on AMD RX 7900 XTX (99% GPU offload)
- **Chat Interface**: OpenWebUI with web search, chat history, and streaming responses
- **Vector Embeddings**: Qwen3-Embedding-4B for code/document search
- **Code Intelligence**: MCP server for semantic code search and git history analysis
- **Web Search**: Private SearXNG instance (no external queries logged)
- **Monitoring**: GPU metrics, token throughput, and system health (Grafana dashboard)
- **Docker Compose**: Single-command startup with health checks and auto-restart

## Quick Start

### Start all services

```bash
./start-llama.sh --remove-orphans
```

The script detects your RX 7900 XTX via `lspci` and `rocm-smi`, then starts all services.

### Access the UI

Open a browser to:
- Chat interface: `http://localhost/` (mapped via nginx to openwebui)
- Or: `http://darwish.cloud.home`

### Check service health

```bash
# Inference service
curl http://localhost/8082/health

# Embedding vectors
curl http://localhost/8081/health

# Web search
curl http://localhost/8888/healthz

# Chat interface
curl http://localhost/3000/health

# Vector database
curl http://localhost/6333/collections

# MCP server
curl http://localhost/3001/mcp
```

## Configuration

Edit `.env` to customize ports and paths:
- `LLAMA_PORT=8082`, `EMBEDDING_PORT=8081` (host ports)
- `DEFAULT_MODEL=Baloza-v3.0` (router mode loads multiple models from `models.ini`)
- `ROCR_VISIBLE_DEVICES` auto-detected on first run

## Models

- **Main inference**: GLM-4.7-Flash (UD-Q4_K_XL), 65536 context
- **Router mode**: Alternates between Baloza-v3.0 and ninni-v0.1 (VL model)
- **Embedding**: Qwen3-Embedding-4B, 2560 dimensions

## Requirements

- AMD ROCm 6.4+ installed at `/opt/rocm`
- RX 7900 XTX GPU
- Docker and Docker Compose
- Model files in `/data/models/llamacpp`
- Model files are automatically mounted as read-only volumes

## Key Files

- `docker-compose.yml` - Service definitions
- `start-llama.sh` - GPU detection and startup script
- `.env` - Environment configuration
- `nginx-configs/` - Reverse proxy configurations
- `nftables.conf` - Firewall rules
- `models.ini` - Model settings for router mode
- `ai-stack-dashboard.json` - Grafana monitoring panel

## System Monitoring

GPU metrics (VRAM, temperature, power) and inference stats are available via Prometheus. Import `ai-stack-dashboard.json` to Grafana for visual monitoring.
