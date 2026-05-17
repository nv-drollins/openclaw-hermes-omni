#!/usr/bin/env bash
# Stop the OpenClaw-only Hermes Omni demo.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
PORT="${PORT:-8765}"
STOP_MODEL="${STOP_MODEL:-true}"
STOP_GATEWAY="${STOP_GATEWAY:-true}"
VLLM_CONTAINER="${VLLM_CONTAINER:-vllm-nemotron-omni}"
RUN_DIR="${RUN_DIR:-$ROOT/.run}"

select_docker_mode() {
    if docker ps >/dev/null 2>&1; then
        DOCKER_MODE="direct"
        return 0
    fi

    if command -v newgrp >/dev/null 2>&1 && getent group docker 2>/dev/null | tr ':,' '  ' | tr ' ' '\n' | grep -qx "${USER:-}"; then
        DOCKER_MODE="newgrp"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        DOCKER_MODE="sudo"
        return 0
    fi

    return 1
}

docker_cmd() {
    local cmd
    case "${DOCKER_MODE:-}" in
        direct)
            docker "$@"
            ;;
        newgrp)
            printf -v cmd '%q ' docker "$@"
            newgrp docker <<EOF
$cmd
EOF
            ;;
        sudo)
            sudo docker "$@"
            ;;
        *)
            select_docker_mode
            docker_cmd "$@"
            ;;
    esac
}

stop_web() {
    local pids=""
    if [[ -f "$RUN_DIR/web.pid" ]]; then
        local pid
        pid=$(cat "$RUN_DIR/web.pid")
        if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
            pids="$pid"
        fi
    fi
    if command -v lsof >/dev/null 2>&1; then
        local port_pids
        port_pids=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
        if [[ -n "$port_pids" ]]; then
            pids="${pids}${pids:+ }${port_pids}"
        fi
    fi
    pids=$(tr ' ' '\n' <<<"$pids" | awk 'NF && !seen[$0]++' | xargs echo || true)
    if [[ -z "$pids" ]]; then
        echo "No web process found on port $PORT"
    else
        echo "Stopping web process(es): $pids"
        kill $pids 2>/dev/null || true
        sleep 2
        for pid in $pids; do
            if kill -0 "$pid" >/dev/null 2>&1; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi
    rm -f "$RUN_DIR/web.pid"
}

stop_gateway() {
    if [[ "$STOP_GATEWAY" != "true" ]]; then
        echo "STOP_GATEWAY=false; leaving OpenClaw gateway running."
        return 0
    fi
    if [[ -f "$ROOT/logs/openclaw-gateway.pid" ]]; then
        local pid
        pid=$(cat "$ROOT/logs/openclaw-gateway.pid")
        if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
            echo "Stopping OpenClaw gateway pid $pid"
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$ROOT/logs/openclaw-gateway.pid"
    fi
}

stop_model() {
    if [[ "$STOP_MODEL" != "true" ]]; then
        echo "STOP_MODEL=false; leaving vLLM running."
        return 0
    fi
    if command -v docker >/dev/null 2>&1 && select_docker_mode && docker_cmd ps -a --format '{{.Names}}' | grep -qx "$VLLM_CONTAINER"; then
        echo "Stopping local vLLM container: $VLLM_CONTAINER"
        docker_cmd stop "$VLLM_CONTAINER" >/dev/null 2>&1 || true
    else
        echo "No vLLM container found: $VLLM_CONTAINER"
    fi
}

stop_web
stop_gateway
stop_model
echo "Stopped."
