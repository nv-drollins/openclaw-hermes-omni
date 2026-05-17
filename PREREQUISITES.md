# Prerequisites

Tracked for clean DGX Spark / Ubuntu installs.

## Host Packages

- `bash`
- `ca-certificates`
- `curl`
- `ffmpeg` and `ffprobe`
- `git`
- `lsof`
- `poppler-utils` for `pdftoppm`
- `python3`, `python3-venv`, `python3-pip`
- `sudo`
- `zstd`

Installed by:

```bash
bash scripts/install-host-prereqs.sh
```

## Runtime Tools

- Node.js 22 and npm, installed through nvm if missing.
- OpenClaw CLI, installed through npm if missing.
- Ollama 0.22.1 or newer enough to serve `gemma4:latest`.
- Docker Engine.
- NVIDIA Container Toolkit configured for Docker GPU containers.
- Local user in the `docker` group for non-root Docker commands.

Docker/GPU container support is installed automatically by `./install.sh` when
missing. You can also run it directly:

```bash
bash scripts/install-docker-nvidia-toolkit.sh
```

That helper adds the current user to the `docker` group, uses `newgrp docker`
for Docker checks during the current run when needed, configures Docker with
`sudo nvidia-ctk runtime configure --runtime=docker`, restarts Docker, and runs
a GPU container check. Open a new terminal or run `newgrp docker` after the
first install so your interactive shell sees the new Docker group membership.

## Models

- Ollama: `gemma4:latest`
- vLLM checkpoint: `nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-NVFP4`
  - Requires a Hugging Face token.
  - May require accepting model terms on Hugging Face before download.
  - Downloads about 22 GB into `$HOME/models/nemotron-3-nano-omni-nvfp4`.

The Hugging Face model may be gated. Export `HF_TOKEN` before running:

```bash
export HF_TOKEN="hf_..."
bash scripts/download-model.sh
```

## Ports

- `8000`: local vLLM OpenAI-compatible endpoint.
- `8765`: browser UI and FastAPI backend.
- `18792`: OpenClaw dashboard on loopback by default.
