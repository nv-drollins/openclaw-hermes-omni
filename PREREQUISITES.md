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

Docker/GPU container support can be installed with:

```bash
bash scripts/install-docker-nvidia-toolkit.sh
```

## Models

- Ollama: `gemma4:latest`
- vLLM checkpoint: `nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-NVFP4`

The Hugging Face model may be gated. Export `HF_TOKEN` before running:

```bash
bash scripts/download-model.sh
```

## Ports

- `8000`: local vLLM OpenAI-compatible endpoint.
- `8765`: browser UI and FastAPI backend.
- `18792`: OpenClaw dashboard on loopback by default.
