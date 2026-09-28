# AI Stack

Self-hosted AI infrastructure for a single GPU box: local LLM inference, a chat UI, private web
search, vector/code search, and GPU observability — reachable from the LAN over plain HTTP domain
names, each service its own systemd-managed Docker container.

## Overview

The intent is a private, LAN-only alternative to hosted AI products, built entirely from
containers a single Makefile can stand up or tear down. Nginx (bare-metal on the host) is the only
component with a LAN-facing listener; it reverse-proxies domain names to loopback ports, so every
container stays bound to `127.0.0.1` regardless of what's exposed.

What it sets up:

| Service | Purpose | Domain (default) |
| --- | --- | --- |
| llama | GLM-4.7-Flash / Qwen3-VL inference, GPU-accelerated | `model.cloud.home` |
| llama-embedding | Qwen3-Embedding-4B for vector/code search | `embedding.cloud.home` |
| openwebui | Chat UI (talks to llama + searxng) | `darwish.cloud.home` |
| searxng | Private metasearch engine | `websearch.cloud.home` |
| one-search-mcp | Web-search MCP tool, backed by searxng | `onesearch.cloud.home` |
| qdrant + qdrant-mcp | Vector DB + semantic code/git search MCP server | *(internal only)* |
| grafana-mcp | Grafana/Prometheus/Loki/Incident MCP server | `grafana-mcp.cloud.home` |
| node-exporter, amd-device-metrics | Host + GPU metrics for Prometheus/Grafana | *(internal only)* |

Every domain and port above is a `Kconfig` default, not fixed (`make menuconfig` to change them).
For how these pieces talk to each other, the full port table, and troubleshooting, see `AGENTS.md`.

## Pre-assumptions

These are baked into the repo, not configurable:

- **AMD GPU(s) supported by ROCm 7.0** — the llama image is compiled only for the `gfx`
  architectures in the `LLAMA_GPU_TARGETS` Kconfig option (auto-detected from `rocminfo` by
  `make menuconfig`); after a GPU swap, rerun `make menuconfig` and `make build-llama`
- **Arch Linux host** — `nginx`/`syslog-ng` are pacman packages; the Makefile deploys into their
  Arch conventions (`/etc/nginx/servers/`, `/etc/logrotate.d/`, `syslog-ng@default.service`)
- **nginx and syslog-ng run bare-metal on the host**, not in Docker — this repo configures them,
  it doesn't install them
- **LAN-only, single host** — `nftables.conf` blocks WAN traffic; no vhost terminates TLS

## Install

### Prerequisites

- Docker
- AMD ROCm 7.0+ at `/opt/rocm`; `rocminfo` recommended (`make menuconfig` uses it to list
  GPUs as checkboxes; without it, type UUIDs into the manual field)
- `python-kconfiglib` (`make menuconfig`)
- nginx and syslog-ng installed (not yet configured)
- Model files present under `/data/models/llamacpp` (see `services/llama/models.ini` for the
  expected layout)

### Instructions

```bash
make menuconfig    # as your normal user: curses menu -> .config
sudo make config   # .config -> /etc/ai-stack/ai-stack.conf; creates data dirs; adds
                    # SYSTEM_USER to the docker/video/render groups
make build          # builds the 3 locally-built images (llama, qdrant-mcp, one-search-mcp)
sudo make install  # creates the ai-stack Docker network; renders and installs a systemd
                    # unit per service (does not enable/start them)
sudo make install-nginx install-syslog-ng install-logrotate  # host-level configs
sudo make firewall  # optional: renders and applies nftables.conf
sudo make start-all
```

`make help` lists every target, including `install-<name>`/`uninstall-<name>` for a single
service, `build-<name>` for a single image, and `stop-all`/`restart-all`/`uninstall`.

### Helpful commands

List GPU UUIDs (what `make menuconfig` offers as checkboxes in the llama menu — a UUID is stable
across reboots, unlike a device index):

```bash
rocminfo | grep -E 'Marketing Name|Uuid'
```

Check service health (bypasses nginx):

```bash
curl http://127.0.0.1:8082/health      # llama inference
curl http://127.0.0.1:8081/health      # embedding vectors
curl http://127.0.0.1:8888/healthz     # searxng search
curl http://127.0.0.1:3000/health      # openwebui chat UI
curl http://127.0.0.1:6333/collections # qdrant vector DB
curl http://127.0.0.1:3001/mcp         # qdrant-mcp server
curl http://127.0.0.1:3002/status      # one-search-mcp
curl http://127.0.0.1:3003/mcp         # grafana-mcp (streamable-http; no dedicated health path)
```

Or via nginx, once `*.cloud.home` resolves on your LAN: `curl http://model.cloud.home/health`
(plain `http://<host-ip>/` with no matching `Host` header hits nginx's catch-all and returns
`444`).

Manage one service at a time with `systemctl`/`journalctl`, e.g. `sudo systemctl restart
openwebui`. See `AGENTS.md` for the full Key Files reference, development workflow, and
troubleshooting guide.
