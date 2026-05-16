#!/usr/bin/env bash
# Build and run the OpenClaw Hermes Omni web UI on one port.
set -euo pipefail

[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"

PORT="${PORT:-8765}"
HOST="${HOST:-0.0.0.0}"
HERE=$(cd "$(dirname "$0")/.." && pwd)
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-$HERE/.venv}"
OPENCLAW_PROFILE="${OPENCLAW_PROFILE:-openclaw-hermes-omni}"
VLLM_BASE_URL="${VLLM_BASE_URL:-http://127.0.0.1:8000/v1}"
OPENCLAW_CHAT_BACKEND="${OPENCLAW_CHAT_BACKEND:-direct}"

echo "-> profile: $OPENCLAW_PROFILE"
echo "-> backend: $OPENCLAW_CHAT_BACKEND"
echo "-> url:     http://localhost:$PORT"
echo

missing=()
for cmd in ffmpeg ffprobe pdftoppm lsof "$PYTHON_BIN" npm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing+=("$cmd")
    fi
done
if (( ${#missing[@]} > 0 )); then
    echo "Missing host command(s): ${missing[*]}" >&2
    echo "Run: bash scripts/install-host-prereqs.sh" >&2
    exit 1
fi

if [[ ! -d "$HERE/ui/node_modules" ]]; then
    echo "-> installing UI dependencies"
    (cd "$HERE/ui" && npm install --silent)
fi

if [[ ! -d "$HERE/ui/dist" ]] || [[ "$HERE/ui/src" -nt "$HERE/ui/dist" ]]; then
    echo "-> building UI"
    (cd "$HERE/ui" && npm run build)
fi
echo "UI built at $HERE/ui/dist"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "-> creating Python virtualenv at $VENV_DIR"
    if ! "$PYTHON_BIN" -m venv "$VENV_DIR"; then
        echo "Failed to create virtualenv. On Ubuntu/Debian install python3-venv." >&2
        exit 1
    fi
fi

PYTHON="$VENV_DIR/bin/python"
if ! "$PYTHON" -c "import fastapi, uvicorn, yaml, multipart" 2>/dev/null; then
    echo "-> installing server dependencies into $VENV_DIR"
    "$PYTHON" -m pip install --quiet -r "$HERE/server/requirements.txt"
fi
echo "server deps ready ($PYTHON)"

if lsof -iTCP:"$PORT" -sTCP:LISTEN -P -n 2>/dev/null | grep -q LISTEN; then
    echo "Port $PORT already in use. Stop the other process or set PORT=<other>." >&2
    exit 1
fi

echo
echo "-> launching server"
echo "  open http://localhost:$PORT in your browser"
echo "  Ctrl-C to stop"
echo

cd "$HERE/server"
exec env \
    OPENCLAW_PROFILE="$OPENCLAW_PROFILE" \
    OPENCLAW_CHAT_BACKEND="$OPENCLAW_CHAT_BACKEND" \
    VLLM_BASE_URL="$VLLM_BASE_URL" \
    "$PYTHON" -m uvicorn server:app --host "$HOST" --port "$PORT"
