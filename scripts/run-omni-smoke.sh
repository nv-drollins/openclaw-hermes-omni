#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${UPLOAD_DIR:-/tmp/openclaw-omni-uploads}"
mkdir -p "$OUT_DIR" "$ROOT/logs"

SMOKE_VIDEO="$OUT_DIR/smoke-test-pattern.mp4"

if ! curl -fsS "${VLLM_BASE_URL:-http://127.0.0.1:8000/v1}/models" >/dev/null 2>&1; then
    echo "Local vLLM is not responding. Run ./start.sh first, or START_WEB=false ./start.sh to start only the model." >&2
    exit 1
fi

ffmpeg -nostdin -y \
  -f lavfi -i "testsrc=duration=8:size=320x240:rate=15" \
  -f lavfi -i "sine=frequency=440:duration=8" \
  -c:v libx264 -pix_fmt yuv420p -shortest "$SMOKE_VIDEO" \
  >/dev/null 2>&1

OMNI_API_URL="${OMNI_API_URL:-http://127.0.0.1:8000/v1/chat/completions}" \
OMNI_MODEL="${OMNI_MODEL:-nvidia/nemotron-3-nano-omni-30b-a3b-reasoning}" \
python3 "$ROOT/scripts/omni-video-analyze.py" \
  "$SMOKE_VIDEO" \
  "Briefly describe the video and audio. Mention the test pattern and tone if present." \
  | tee "$ROOT/logs/omni-smoke.log"

