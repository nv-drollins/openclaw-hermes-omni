# OpenClaw Hermes Omni Demo

This repo packages the Hermes Omni browser demo as a native OpenClaw project for a DGX Spark-class Ubuntu host.

- OpenClaw runs locally with profile `openclaw-hermes-omni`.
- Nemotron Omni runs locally through a vLLM Docker container on the GPU.
- The browser UI runs on port `8765`.
- Uploaded video, audio, images, and PDFs stay on the host under `/tmp/openclaw-omni-uploads`.

The tested multimodal model is:

```text
nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-NVFP4
```

The runtime model id is:

```text
nvidia/nemotron-3-nano-omni-30b-a3b-reasoning
```

## Before You Start

This demo requires a Hugging Face token and a large local checkpoint download.

- Hugging Face token required: set `HF_TOKEN` before downloading.
- Model access may be gated: accept the model terms for
  `nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-NVFP4` if the download is
  denied.
- Download size: about 22 GB for the local Omni checkpoint.
- Destination: `$HOME/models/nemotron-3-nano-omni-nvfp4`.

Download the model before the first full start:

```bash
export HF_TOKEN="hf_..."
bash scripts/download-model.sh
```

## First Deploy

Run these commands on the Spark or target Ubuntu host:

```bash
git clone https://github.com/nv-drollins/openclaw-hermes-omni.git
cd openclaw-hermes-omni
chmod +x install.sh start.sh stop.sh restart.sh scripts/*.sh
```

Install host prerequisites and launch the first run:

```bash
./install.sh
```

The installer prompts for sudo when needed. Passwordless sudo is not required,
but first-time setup must run from an interactive terminal or SSH session with a
TTY.

On a clean Spark, the installer also configures Docker for the local vLLM model
container:

- installs Docker Engine if missing
- adds the local user to the `docker` group
- runs Docker commands through `newgrp docker` for the current install when
  group membership has not refreshed yet
- installs NVIDIA Container Toolkit
- runs `sudo nvidia-ctk runtime configure --runtime=docker`
- restarts Docker
- verifies `docker run --rm --gpus all ubuntu nvidia-smi`

After the first install, open a new terminal or run:

```bash
newgrp docker
```

That lets normal Docker commands work without `sudo` in your interactive shell.
If you already manage Docker/NVIDIA Container Toolkit yourself, skip this repo's
Docker setup with:

```bash
HERMES_SKIP_DOCKER_SETUP=1 ./install.sh
```

## Hugging Face Model

The start script expects the local Omni checkpoint at:

```text
$HOME/models/nemotron-3-nano-omni-nvfp4
```

Download it with:

```bash
export HF_TOKEN="hf_..."
bash scripts/download-model.sh
```

If the download fails with an authorization or gated-model error, accept the model terms on Hugging Face for `nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning-NVFP4`, then retry with `HF_TOKEN` exported.

The helper creates its own Hugging Face CLI virtualenv at `$HOME/.local/share/hf-download-venv`, so a clean host does not need a global `hf` command installed first.

## Start

Start everything:

```bash
./start.sh
```

Open the UI:

```text
http://<spark-ip>:8765
```

The script starts or reuses:

- OpenClaw profile `openclaw-hermes-omni`
- OpenClaw dashboard on loopback port `18792`
- Ollama orchestrator model `gemma4:latest`
- vLLM Omni container on port `8000`
- FastAPI/React demo server on port `8765`

## Stop

Stop the web app, gateway, and vLLM model container:

```bash
./stop.sh
```

Keep the Omni model container warm and stop only the UI/gateway:

```bash
STOP_MODEL=false ./stop.sh
```

## Restart

Restart everything:

```bash
./restart.sh
```

Restart only the browser UI while keeping the model warm:

```bash
STOP_MODEL=false ./stop.sh
START_MODEL=false ./start.sh
```

## Smoke Tests

Check vLLM:

```bash
curl http://localhost:8000/v1/models
```

Check the UI backend:

```bash
curl http://localhost:8765/api/health
```

Run a generated-video Omni test:

```bash
bash scripts/run-omni-smoke.sh
```

Run a native OpenClaw skill-routing test:

```bash
bash scripts/run-openclaw-smoke.sh
```

## Demo Flow

For a short walkthrough:

1. Upload an image and ask: `Describe this image.`
2. Upload a PDF and ask: `Summarize the document and list the key facts.`
3. Upload a video and ask: `Describe what happens in this clip.`
4. Ask: `Can this host reach nvidia.com?`

The web UI also renders PDF pages and chunks larger video uploads before sending them to Omni.

## Useful Options

```bash
PORT=8766 ./start.sh                  # use a different web port
START_WEB=false ./start.sh            # start only local model services
START_GATEWAY=false ./start.sh        # skip the OpenClaw dashboard
STOP_MODEL=false ./stop.sh            # leave vLLM running
OPENCLAW_CHAT_BACKEND=openclaw ./start.sh
OPENCLAW_OLLAMA_CONTEXT_WINDOW=4096 ./start.sh
```

By default the web UI uses the direct local backend for responsiveness. The OpenClaw profile and skills are still installed and can be tested through `scripts/run-openclaw-smoke.sh` or by setting `OPENCLAW_CHAT_BACKEND=openclaw`.

## Notes

- This repo does not require NemoClaw or OpenShell.
- Docker/NVIDIA Container Toolkit are required because the Omni model is served by vLLM in a GPU container.
- The Docker/NVIDIA setup follows Docker's non-root-user flow (`docker` group plus `newgrp docker`) and NVIDIA's Docker runtime configuration flow (`nvidia-ctk runtime configure --runtime=docker`).
- The `gemma4:latest` Ollama model is used as the OpenClaw orchestrator because it stays responsive while the Omni vLLM container is loaded. The profile caps the orchestrator context at 8192 tokens by default to avoid starving the Omni container. Override with `OPENCLAW_OLLAMA_MODEL=...` or `OPENCLAW_OLLAMA_CONTEXT_WINDOW=...` if you want to test another local Ollama setup.
- The first vLLM startup can take several minutes and uses most of the Spark GPU memory.
