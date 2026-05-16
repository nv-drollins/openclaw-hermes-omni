#!/usr/bin/env bash
# Restart the local Hermes Omni demo.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)

"$ROOT/stop.sh"
"$ROOT/start.sh"
