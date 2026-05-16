#!/usr/bin/env bash
# Start the OpenClaw-only Hermes Omni demo.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
PORT="${PORT:-8765}"
HOST="${HOST:-0.0.0.0}"
START_WEB="${START_WEB:-true}"
START_MODEL="${START_MODEL:-true}"
START_GATEWAY="${START_GATEWAY:-true}"

VLLM_CONTAINER="${VLLM_CONTAINER:-vllm-nemotron-omni}"
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:v0.20.0}"
VLLM_PORT="${VLLM_PORT:-8000}"
MODEL_ID="${MODEL_ID:-nvidia/nemotron-3-nano-omni-30b-a3b-reasoning}"
MODEL_DIR="${MODEL_DIR:-$HOME/models/nemotron-3-nano-omni-nvfp4}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-65536}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.75}"
RUN_DIR="${RUN_DIR:-$ROOT/.run}"

mkdir -p "$RUN_DIR"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

wait_for_vllm() {
    echo "Waiting for local vLLM on port $VLLM_PORT..."
    for _ in $(seq 1 120); do
        if curl -fsS "http://127.0.0.1:${VLLM_PORT}/v1/models" >/dev/null 2>&1; then
            echo "vLLM is ready: http://127.0.0.1:${VLLM_PORT}/v1"
            return 0
        fi
        sleep 5
    done
    echo "Timed out waiting for vLLM. Check logs with:" >&2
    echo "  docker logs --tail 200 $VLLM_CONTAINER" >&2
    exit 1
}

start_vllm() {
    require_cmd docker
    require_cmd curl

    if curl -fsS "http://127.0.0.1:${VLLM_PORT}/v1/models" >/dev/null 2>&1; then
        echo "vLLM is already running on port $VLLM_PORT"
        return 0
    fi

    if [[ ! -f "$MODEL_DIR/config.json" ]]; then
        echo "Model directory is missing or incomplete: $MODEL_DIR" >&2
        echo "Download it first with:" >&2
        echo "  export HF_TOKEN=\"hf_...\"   # if the model is gated" >&2
        echo "  bash scripts/download-model.sh" >&2
        exit 1
    fi

    if docker ps -a --format '{{.Names}}' | grep -qx "$VLLM_CONTAINER"; then
        echo "Removing stale vLLM container: $VLLM_CONTAINER"
        docker rm -f "$VLLM_CONTAINER" >/dev/null
    fi

    echo "Starting local Nemotron Omni vLLM container..."
    docker run -d \
        --gpus all \
        --ipc=host \
        -p "${VLLM_PORT}:8000" \
        --shm-size=16g \
        --name "$VLLM_CONTAINER" \
        -v "${MODEL_DIR}:/model:ro" \
        --entrypoint /bin/bash \
        "$VLLM_IMAGE" \
        -lc "
            set -euo pipefail
            pip install 'vllm[audio]'
            exec vllm serve /model \
                --served-model-name '$MODEL_ID' \
                --host 0.0.0.0 \
                --port 8000 \
                --max-num-seqs 4 \
                --max-model-len '$MAX_MODEL_LEN' \
                --trust-remote-code \
                --gpu-memory-utilization '$GPU_MEMORY_UTILIZATION' \
                --limit-mm-per-prompt '{\"video\":1,\"image\":8,\"audio\":1}' \
                --media-io-kwargs '{\"video\":{\"fps\":2,\"num_frames\":256}}' \
                --allowed-local-media-path=/ \
                --enable-prefix-caching \
                --max-num-batched-tokens '$MAX_MODEL_LEN' \
                --reasoning-parser nemotron_v3 \
                --enable-auto-tool-choice \
                --tool-call-parser qwen3_coder
        " >/dev/null

    wait_for_vllm
}

start_web() {
    require_cmd lsof

    if lsof -iTCP:"$PORT" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
        echo "Web demo is already listening on port $PORT"
        return 0
    fi

    echo "Starting web demo on http://0.0.0.0:${PORT} ..."
    (
        cd "$ROOT"
        env PORT="$PORT" HOST="$HOST" VLLM_BASE_URL="http://127.0.0.1:${VLLM_PORT}/v1" bash scripts/start.sh
    ) >"$RUN_DIR/web.log" 2>&1 &
    echo "$!" > "$RUN_DIR/web.pid"

    for _ in $(seq 1 90); do
        if curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
            echo "Web demo is ready: http://$(hostname -I 2>/dev/null | awk '{print $1}'):${PORT}"
            echo "Log: $RUN_DIR/web.log"
            return 0
        fi
        sleep 2
    done

    echo "Timed out waiting for the web demo. Last log lines:" >&2
    tail -n 100 "$RUN_DIR/web.log" >&2 || true
    exit 1
}

"$ROOT/scripts/setup-openclaw.sh"
"$ROOT/scripts/ensure-model.sh"

if [[ "$START_GATEWAY" == "true" ]]; then
    "$ROOT/scripts/start-openclaw-gateway.sh"
fi

if [[ "$START_MODEL" == "true" ]]; then
    start_vllm
else
    echo "START_MODEL=false; leaving vLLM start/check to the user."
fi

if [[ "$START_WEB" == "true" ]]; then
    start_web
else
    echo "START_WEB=false; leaving web demo stopped."
fi

echo
echo "OpenClaw dashboard:"
"$ROOT/scripts/show-dashboard.sh" --no-token || true
