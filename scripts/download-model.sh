#!/usr/bin/env bash
# Download the local Nemotron Omni checkpoint without requiring a global hf CLI.
set -euo pipefail

MODEL_REPO="${MODEL_REPO:-nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-NVFP4}"
MODEL_DIR="${MODEL_DIR:-$HOME/models/nemotron-3-nano-omni-nvfp4}"
HF_VENV="${HF_VENV:-$HOME/.local/share/hf-download-venv}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "Missing $PYTHON_BIN. Install Python 3 first." >&2
    exit 1
fi

mkdir -p "$(dirname "$HF_VENV")" "$MODEL_DIR"

if [[ ! -x "$HF_VENV/bin/python" ]]; then
    echo "Creating Hugging Face download virtualenv: $HF_VENV"
    if ! "$PYTHON_BIN" -m venv "$HF_VENV"; then
        echo "Failed to create virtualenv. On Ubuntu/Debian install python3-venv:" >&2
        echo "  sudo apt-get update && sudo apt-get install -y python3-venv" >&2
        exit 1
    fi
fi

echo "Installing/updating Hugging Face CLI in $HF_VENV"
"$HF_VENV/bin/python" -m pip install -U pip 'huggingface_hub[hf_xet]'

if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "HF_TOKEN is not set. If the model is gated, accept the model terms and export HF_TOKEN before retrying." >&2
fi

echo "Downloading $MODEL_REPO"
echo "Target: $MODEL_DIR"
"$HF_VENV/bin/hf" download "$MODEL_REPO" --local-dir "$MODEL_DIR" "$@"

if [[ ! -f "$MODEL_DIR/config.json" ]]; then
    echo "Download finished, but $MODEL_DIR/config.json was not found." >&2
    echo "Check the Hugging Face output above for authentication, gating, or disk-space errors." >&2
    exit 1
fi

echo "Model is ready at $MODEL_DIR"
