#!/usr/bin/env bash
set -euo pipefail

MODEL="${OPENCLAW_OLLAMA_MODEL:-gemma4:latest}"

if ! command -v ollama >/dev/null 2>&1; then
  echo "Missing ollama. Run ./scripts/install-host-prereqs.sh first." >&2
  exit 1
fi

if ! curl -fsS http://127.0.0.1:11434 >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl restart ollama || true
  fi
fi

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:11434 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS http://127.0.0.1:11434 >/dev/null 2>&1; then
  echo "Ollama is not responding on http://127.0.0.1:11434" >&2
  exit 1
fi

if ollama list | awk 'NR > 1 {print $1}' | grep -Fxq "$MODEL"; then
  echo "Ollama model already present: $MODEL"
else
  echo "Pulling Ollama model: $MODEL"
  ollama pull "$MODEL"
fi
