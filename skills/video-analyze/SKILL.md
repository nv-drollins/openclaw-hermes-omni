---
name: video-analyze
description: Analyze video files, audio files, images, PDF-rendered page directories, pre-chunked video directories, or long-video bundles using the local Nemotron Omni vLLM endpoint.
version: 4.0.0
metadata:
  openclaw:
    requires:
      bins: ["python3", "ffmpeg", "ffprobe"]
---

# Video Analysis With Local Nemotron Omni

Analyze videos, audio, images, and documents using the host-side helper:

```bash
python3 scripts/omni-video-analyze.py <path> "<question>"
```

Use the path exactly as provided by the user or web UI. In this OpenClaw-only
demo, uploads live on the host, usually under `/tmp/openclaw-omni-uploads`.
Use host paths only. The web UI has already placed uploads where the helper can
read them.

## Inputs

| Input | What happens |
|---|---|
| `*.mp4 / .mov / .webm` | One Omni call with the full video |
| `*.mp3 / .wav / .m4a` | One Omni call with audio |
| `*.png / .jpg / .webp` | One Omni call with the image |
| Directory of PNGs, usually `*.pdf-pages/` | Multi-image document analysis, batched when needed |
| Directory of MP4 chunks, usually `*-chunks/` | Per-chunk Omni call plus final synthesis |
| Long-video bundle, usually `*-longvideo/` | Audio transcript plus sampled frames |

## Usage

```bash
python3 scripts/omni-video-analyze.py /tmp/openclaw-omni-uploads/upload-abc123.mp4 \
  "What is happening in this clip?"
```

For follow-up questions, rerun the script with the same path and the new
question. Do not answer from memory when the user asks about a file.

The helper uses:

```text
OMNI_API_URL=http://127.0.0.1:8000/v1/chat/completions
```

unless overridden in the environment.
