#!/usr/bin/env bash

openclaw_source_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    nvm use 22 >/dev/null 2>&1 || true
  fi
}

openclaw_node_major() {
  node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0
}

openclaw_require_node22() {
  openclaw_source_nvm
  if [ "$(openclaw_node_major)" -lt 22 ]; then
    echo "Node.js 22+ is required. Run ./scripts/install-host-prereqs.sh first." >&2
    return 1
  fi
}

openclaw_require_cli() {
  openclaw_require_node22
  if ! command -v openclaw >/dev/null 2>&1; then
    echo "OpenClaw CLI is required. Run ./scripts/install-host-prereqs.sh first." >&2
    return 1
  fi
}
