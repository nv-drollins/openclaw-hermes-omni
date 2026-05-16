#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=openclaw-env.sh
. "$SCRIPT_DIR/openclaw-env.sh"

PROFILE="${OPENCLAW_PROFILE:-openclaw-hermes-omni}"
MODEL_REF="${OPENCLAW_MODEL_REF:-ollama/${OPENCLAW_OLLAMA_MODEL:-gemma4:latest}}"
SESSION="${OPENCLAW_SMOKE_SESSION:-hermes-omni-smoke}"
LOG_FILE="$ROOT/logs/openclaw-smoke.json"
ERR_LOG="$ROOT/logs/openclaw-smoke.stderr.log"

mkdir -p "$ROOT/logs"
openclaw_require_cli

openclaw --profile "$PROFILE" agent \
  --local \
  --session-id "$SESSION" \
  --model "$MODEL_REF" \
  --timeout "${OPENCLAW_AGENT_TIMEOUT:-300}" \
  --message "Use the jargon-lookup skill to look up FP8 in the context of machine learning. Answer in two short sentences." \
  --json > "$LOG_FILE" 2>"$ERR_LOG"

python3 - "$LOG_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
text = "\n".join(p.get("text", "") for p in data.get("payloads", [])).strip()
print(text)
if "FP8" not in text.upper() and "8-bit" not in text.lower():
    raise SystemExit("OpenClaw smoke response did not mention FP8/8-bit")
PY
