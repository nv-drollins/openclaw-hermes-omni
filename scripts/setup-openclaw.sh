#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve-demo-root.sh
. "$SCRIPT_DIR/resolve-demo-root.sh"
ROOT="$(resolve_demo_root "$SCRIPT_DIR")"
# shellcheck source=openclaw-env.sh
. "$SCRIPT_DIR/openclaw-env.sh"

PROFILE="${OPENCLAW_PROFILE:-openclaw-hermes-omni}"
OLLAMA_MODEL="${OPENCLAW_OLLAMA_MODEL:-gemma4:latest}"
MODEL_REF="${OPENCLAW_MODEL_REF:-ollama/${OLLAMA_MODEL}}"
PORT="${OPENCLAW_GATEWAY_PORT:-18792}"
BIND="${OPENCLAW_GATEWAY_BIND:-loopback}"
SETUP_LOG="$ROOT/logs/setup-openclaw.log"
OLLAMA_CONTEXT_WINDOW="${OPENCLAW_OLLAMA_CONTEXT_WINDOW:-8192}"
OLLAMA_MAX_TOKENS="${OPENCLAW_OLLAMA_MAX_TOKENS:-2048}"

mkdir -p "$ROOT/logs"
openclaw_require_cli
: > "$SETUP_LOG"

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

  [ -f "$config_path" ] || return 0
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

write_gateway_token() {
  local config_path="$1"
  local token="$2"

  python3 - "$config_path" "$token" <<'PY'
import json
import sys

config_path, token = sys.argv[1:3]
with open(config_path, encoding="utf-8") as f:
    data = json.load(f)
gateway = data.setdefault("gateway", {})
auth = gateway.setdefault("auth", {})
auth["mode"] = "token"
auth["token"] = token
with open(config_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

patch_ollama_model_limits() {
  local config_path="$1"
  local model_id="$2"
  local context_window="$3"
  local max_tokens="$4"

  python3 - "$config_path" "$model_id" "$context_window" "$max_tokens" <<'PY'
import json
import sys

config_path, model_id, context_window, max_tokens = sys.argv[1:5]
context_window = int(context_window)
max_tokens = int(max_tokens)

with open(config_path, encoding="utf-8") as f:
    data = json.load(f)

providers = data.setdefault("models", {}).setdefault("providers", {})
ollama = providers.setdefault("ollama", {})
models = ollama.setdefault("models", [])
for model in models:
    if model.get("id") == model_id or model.get("name") == model_id:
        model["contextWindow"] = context_window
        model["maxTokens"] = max_tokens
        break

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

generate_token() {
  python3 - <<'PY'
import secrets
print(secrets.token_hex(24))
PY
}

CONFIG_FILE_RAW="$(openclaw --profile "$PROFILE" config file 2>>"$SETUP_LOG" || true)"
CONFIG_FILE=""
EXISTING_TOKEN=""
if [ -n "$CONFIG_FILE_RAW" ]; then
  CONFIG_FILE="$(expand_path "$CONFIG_FILE_RAW")"
  EXISTING_TOKEN="$(read_config_value "$CONFIG_FILE" "gateway.auth.token")"
fi
if [ "$EXISTING_TOKEN" = "__OPENCLAW_REDACTED__" ]; then
  EXISTING_TOKEN=""
fi
GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$EXISTING_TOKEN}"
if [ -z "$GATEWAY_TOKEN" ]; then
  GATEWAY_TOKEN="$(generate_token)"
fi

echo "Configuring native OpenClaw profile '$PROFILE'"
openclaw --profile "$PROFILE" onboard \
  --non-interactive \
  --accept-risk \
  --mode local \
  --workspace "$ROOT" \
  --auth-choice ollama \
  --gateway-port "$PORT" \
  --gateway-bind "$BIND" \
  --gateway-auth token \
  --gateway-token "$GATEWAY_TOKEN" \
  --skip-bootstrap \
  --skip-channels \
  --skip-daemon \
  --skip-health \
  --skip-search \
  --skip-skills \
  --skip-ui \
  --no-install-daemon \
  --json >>"$SETUP_LOG" 2>&1

openclaw --profile "$PROFILE" models set "$MODEL_REF" >>"$SETUP_LOG" 2>&1
openclaw --profile "$PROFILE" config set agents.defaults.skills '["video-analyze","jargon-lookup"]' --strict-json >>"$SETUP_LOG" 2>&1
openclaw --profile "$PROFILE" config set agents.defaults.timeoutSeconds 900 --strict-json >>"$SETUP_LOG" 2>&1
CONFIG_FILE_RAW="$(openclaw --profile "$PROFILE" config file 2>>"$SETUP_LOG")"
CONFIG_FILE="$(expand_path "$CONFIG_FILE_RAW")"
write_gateway_token "$CONFIG_FILE" "$GATEWAY_TOKEN"
patch_ollama_model_limits "$CONFIG_FILE" "$OLLAMA_MODEL" "$OLLAMA_CONTEXT_WINDOW" "$OLLAMA_MAX_TOKENS"
openclaw --profile "$PROFILE" config validate >>"$SETUP_LOG" 2>&1

echo "OpenClaw profile '$PROFILE' is configured with model '$MODEL_REF'"
echo "OpenClaw profile '$PROFILE' is restricted to the video-analyze and jargon-lookup skills"
echo "OpenClaw Ollama limits for '$OLLAMA_MODEL': context=$OLLAMA_CONTEXT_WINDOW max_tokens=$OLLAMA_MAX_TOKENS"
