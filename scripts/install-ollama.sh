#!/usr/bin/env bash
set -euo pipefail

OLLAMA_VERSION="${OLLAMA_VERSION:-0.22.1}"

installed_version() {
  if ! command -v ollama >/dev/null 2>&1; then
    return 1
  fi
  ollama --version 2>/dev/null | awk '{print $NF}' | sed 's/^v//'
}

current="$(installed_version || true)"
if [ "$current" = "$OLLAMA_VERSION" ] && systemctl list-unit-files ollama.service >/dev/null 2>&1; then
  echo "Ollama $OLLAMA_VERSION already installed"
else
  echo "Installing Ollama $OLLAMA_VERSION"
  ARCH="$(case "$(uname -m)" in aarch64|arm64) echo arm64 ;; x86_64|amd64) echo amd64 ;; *) uname -m ;; esac)"
  TARBALL="/tmp/ollama-linux-${ARCH}.tar.zst"

  curl -fL --show-error -o "$TARBALL" \
    "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-${ARCH}.tar.zst"

  sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama 2>/dev/null || true
  sudo usermod -a -G video,render ollama 2>/dev/null || true
  sudo tar --zstd -xf "$TARBALL" -C /usr/local
  sudo chmod -R a+rX /usr/local/lib/ollama

  sudo tee /etc/systemd/system/ollama.service >/dev/null <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="OLLAMA_HOST=127.0.0.1:11434"

[Install]
WantedBy=default.target
EOF
fi

sudo systemctl daemon-reload
sudo systemctl enable --now ollama
sudo systemctl restart ollama

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:11434 >/dev/null 2>&1; then
    echo "Ollama is running at http://127.0.0.1:11434"
    exit 0
  fi
  sleep 1
done

echo "Ollama did not become ready; check: sudo journalctl -u ollama -n 100" >&2
exit 1
