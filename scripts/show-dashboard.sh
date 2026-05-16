#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=openclaw-env.sh
. "$SCRIPT_DIR/openclaw-env.sh"

PROFILE="${OPENCLAW_PROFILE:-openclaw-hermes-omni}"
PORT="${OPENCLAW_GATEWAY_PORT:-18792}"
BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
SHOW_TOKEN=1

usage() {
  cat <<EOF
Usage: $0 [--show-token] [--no-token]

Prints the native OpenClaw dashboard URL. By default it also prints the local
gateway token needed to sign in.

Options:
  --show-token  Print the dashboard token. Accepted for compatibility.
  --no-token    Do not print the token.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --show-token) SHOW_TOKEN=1 ;;
    --no-token) SHOW_TOKEN=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

openclaw_require_cli

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

read_config_value() {
  local config_path="$1"
  local dotted_path="$2"

  python3 - "$config_path" "$dotted_path" <<'PY'
import json
import sys

config_path, dotted_path = sys.argv[1:3]
try:
    with open(config_path, encoding="utf-8") as f:
        value = json.load(f)
    for part in dotted_path.split("."):
        value = value[part]
except Exception:
    sys.exit(0)
if value is None:
    sys.exit(0)
print(value)
PY
}

CONFIG_FILE="${OPENCLAW_CONFIG_FILE:-$HOME/.openclaw-${PROFILE}/openclaw.json}"
TOKEN=""
CONFIG_PORT=""
CONFIG_BIND=""
if [ -n "$CONFIG_FILE" ]; then
  CONFIG_FILE="$(expand_path "$CONFIG_FILE")"
  TOKEN="$(read_config_value "$CONFIG_FILE" "gateway.auth.token")"
  CONFIG_PORT="$(read_config_value "$CONFIG_FILE" "gateway.port")"
  CONFIG_BIND="$(read_config_value "$CONFIG_FILE" "gateway.bind")"
fi

if [ -z "$TOKEN" ] || [ "$TOKEN" = "__OPENCLAW_REDACTED__" ]; then
  TOKEN=""
fi

if [ -n "$CONFIG_PORT" ]; then
  PORT="$CONFIG_PORT"
fi
if [ -n "$CONFIG_BIND" ]; then
  BIND="$CONFIG_BIND"
fi

if [ "$BIND" = "loopback" ]; then
  URL="http://127.0.0.1:${PORT}/"
else
  HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  URL="http://${HOST_IP:-127.0.0.1}:${PORT}/"
fi

echo "Dashboard URL:"
echo "$URL"

if [ "$SHOW_TOKEN" -eq 1 ] && [ -n "$TOKEN" ]; then
  echo
  echo "Dashboard token:"
  if [ "$TOKEN" = "__OPENCLAW_REDACTED__" ]; then
    echo "Token is redacted in the OpenClaw config. Repair it with:"
    echo "  ./scripts/setup-openclaw.sh"
    echo "  ./scripts/stop-demo.sh && ./scripts/start-demo.sh --no-install"
  else
    echo "$TOKEN"
  fi
fi

if [ "$BIND" = "loopback" ]; then
  echo
  echo "If your browser is on another machine, tunnel it first:"
  echo "  ssh -N -L ${PORT}:127.0.0.1:${PORT} <user>@<spark-ip>"
fi
