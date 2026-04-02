#!/bin/bash
# start-llama.sh
# Dynamically finds the RX 7900 XTX ROCm device index and starts the AI stack.

set -euo pipefail

COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"

echo "Finding discrete GPU..."

GPU_DEVICE_IDX=$(rocm-smi --showbus 2>/dev/null \
  | grep "$(lspci | grep -i 'RX 7900' | cut -d' ' -f1)" \
  | tr -d '[:blank:] :' \
  | tr '[]' ':' \
  | cut -d':' -f2)

if [[ -z "$GPU_DEVICE_IDX" ]]; then
  echo "ERROR: Could not find RX 7900 XTX. Check lspci and rocm-smi output." >&2
  exit 1
fi

echo "Found RX 7900 XTX at ROCm device index: $GPU_DEVICE_IDX"

GPU_DEVICE_IDX="$GPU_DEVICE_IDX" docker compose -f "$COMPOSE_FILE" up "$@"
