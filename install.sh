#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${MODEL_DIR:-$HOME/models/nemotron-3-nano-omni-nvfp4}"

ensure_omni_model() {
    if [[ "${HERMES_SKIP_MODEL_DOWNLOAD:-0}" == "1" ]]; then
        echo "[model] Skipping Omni checkpoint download because HERMES_SKIP_MODEL_DOWNLOAD=1"
        return 0
    fi

    if [[ -f "$MODEL_DIR/config.json" ]]; then
        echo "[model] Omni checkpoint already present: $MODEL_DIR"
        return 0
    fi

    echo
    echo "[model] Omni checkpoint is not present at: $MODEL_DIR"
    echo "[model] This is about a 22 GB Hugging Face download."

    if [[ -z "${HF_TOKEN:-}" ]]; then
        cat >&2 <<EOF

HF_TOKEN is not set.

Before running ./install.sh, accept the model terms on Hugging Face if needed,
then export your token:

  export HF_TOKEN="hf_..."
  ./install.sh

Or download the model explicitly:

  export HF_TOKEN="hf_..."
  bash scripts/download-model.sh

EOF
        exit 1
    fi

    echo "[model] HF_TOKEN is set. Downloading the Omni checkpoint now."
    MODEL_DIR="$MODEL_DIR" bash "$ROOT/scripts/download-model.sh"
}

"$ROOT/scripts/install-host-prereqs.sh"
ensure_omni_model
"$ROOT/start.sh" "$@"
