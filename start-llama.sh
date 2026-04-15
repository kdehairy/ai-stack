#!/bin/bash
# start-llama.sh
# Dynamically finds the RX 7900 XTX ROCm device index and starts the AI stack.

set -eu

COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"

if ! command -v /opt/rocm/bin/rocm-smi &>/dev/null; then
  echo "ERROR: rocm-smi not found at /opt/rocm/bin/rocm-smi." >&2
  echo "Install it with: sudo pacman -S rocm-smi-lib" >&2
  exit 1
fi

echo "Finding discrete GPU..."

BUS_ID=$(lspci 2>/dev/null | grep -i 'RX 7900' | cut -d' ' -f1)
if [[ -z "$BUS_ID" ]]; then
	echo "ERROR: Could not find RX 7900 XTX in lspci output." >&2
	exit 1
fi

echo "Found RX 7900 XTX at PCIe bus: $BUS_ID"

GPU_DEVICE_IDX=$(/opt/rocm/bin/rocm-smi --showbus 2>/dev/null \
  | grep "$BUS_ID" \
  | tr -d '[:blank:] :' \
  | tr '[]' ':' \
  | cut -d':' -f2)

if [[ -z "$GPU_DEVICE_IDX" ]]; then
  echo "ERROR: Could not find RX 7900 XTX. Check lspci and rocm-smi output." >&2
	echo "rocm-smi output:" >&2
  exit 1
fi

echo "Found RX 7900 XTX at ROCm device index: $GPU_DEVICE_IDX"

GPU_DEVICE_IDX="$GPU_DEVICE_IDX" docker compose -f "$COMPOSE_FILE" up "$@"
