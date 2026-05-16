#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve-demo-root.sh
. "$SCRIPT_DIR/resolve-demo-root.sh"
ROOT="$(resolve_demo_root "$SCRIPT_DIR")"
# shellcheck source=openclaw-env.sh
. "$SCRIPT_DIR/openclaw-env.sh"

PROFILE="${OPENCLAW_PROFILE:-openclaw-hermes-omni}"
PORT="${OPENCLAW_GATEWAY_PORT:-18792}"
BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
PID_FILE="$ROOT/logs/openclaw-gateway.pid"
LOG_FILE="$ROOT/logs/openclaw-gateway.log"

mkdir -p "$ROOT/logs"
openclaw_require_cli

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "OpenClaw gateway already running on pid $old_pid"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

if command -v lsof >/dev/null 2>&1; then
  existing="$(lsof -ti ":$PORT" 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    echo "Stopping existing process on port $PORT: $existing"
    for pid in $existing; do
      kill "$pid" 2>/dev/null || true
    done
    sleep 1
  fi
fi

echo "Starting OpenClaw gateway on port $PORT"
nohup openclaw --profile "$PROFILE" gateway run \
  --bind "$BIND" \
  --port "$PORT" \
  >"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

for _ in $(seq 1 60); do
  if openclaw --profile "$PROFILE" gateway health >/dev/null 2>&1; then
    echo "OpenClaw gateway is running"
    exit 0
  fi
  sleep 1
done

echo "OpenClaw gateway did not become healthy; see $LOG_FILE" >&2
tail -100 "$LOG_FILE" >&2 || true
exit 1
