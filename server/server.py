#!/usr/bin/env python3
"""FastAPI backend for the OpenClaw Hermes Omni demo.

This OpenClaw-only variant keeps the original upload-first browser demo, but
removes the NemoClaw/OpenShell sandbox dependency. Files stay on the host, local
helpers prepare media, and `omni-video-analyze.py` talks directly to the local
vLLM OpenAI-compatible endpoint.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import uuid
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

ROOT = Path(__file__).resolve().parent.parent
UPLOAD_DIR = Path(os.environ.get("UPLOAD_DIR", "/tmp/openclaw-omni-uploads"))
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR = ROOT / "logs"
LOG_DIR.mkdir(exist_ok=True)

OPENCLAW_PROFILE = os.environ.get("OPENCLAW_PROFILE", "openclaw-hermes-omni")
OPENCLAW_MODEL_REF = os.environ.get(
    "OPENCLAW_MODEL_REF",
    f"ollama/{os.environ.get('OPENCLAW_OLLAMA_MODEL', 'gemma4:latest')}",
)
CHAT_BACKEND = os.environ.get("OPENCLAW_CHAT_BACKEND", "direct").lower()
VLLM_BASE_URL = os.environ.get("VLLM_BASE_URL", "http://127.0.0.1:8000/v1")
OMNI_API_URL = os.environ.get("OMNI_API_URL", f"{VLLM_BASE_URL.rstrip('/')}/chat/completions")
OMNI_MODEL = os.environ.get(
    "OMNI_MODEL",
    "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
)
PYTHON_BIN = os.environ.get("PYTHON_BIN", "python3")
ANALYZER = ROOT / "scripts" / "omni-video-analyze.py"
LOOKUP = ROOT / "scripts" / "lookup-jargon.py"

app = FastAPI(title="OpenClaw Hermes Omni Backend")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class UploadResponse(BaseModel):
    sandbox_path: str
    size_bytes: int
    original_name: str
    kind: str = "video"
    pages: int | None = None


class ChatRequest(BaseModel):
    prompt: str
    video_path: str | None = None
    session_id: str | None = None
    new_session: bool = False


def _sse(event: dict) -> bytes:
    return f"data: {json.dumps(event)}\n\n".encode()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_host_path(path: str) -> Path:
    p = Path(path).expanduser().resolve()
    allowed = [UPLOAD_DIR.resolve(), Path("/tmp").resolve()]
    if not any(str(p).startswith(str(root)) for root in allowed):
        raise HTTPException(400, "path not allowed")
    return p


async def _run_command(
    *cmd: str,
    env: dict[str, str] | None = None,
    timeout: int | None = None,
) -> tuple[int, str]:
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        env=env,
        cwd=str(ROOT),
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        out, _ = await proc.communicate()
        return 124, out.decode(errors="ignore") + "\n[timeout]"
    return proc.returncode, out.decode(errors="ignore")


async def _probe_duration_seconds(src: Path) -> float | None:
    rc, out = await _run_command(
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(src),
        timeout=30,
    )
    if rc != 0:
        return None
    try:
        return float(out.strip())
    except ValueError:
        return None


async def _handle_pdf_upload(raw_path: Path, uid: str, original_name: str) -> UploadResponse:
    out_dir = UPLOAD_DIR / f"upload-{uid}.pdf-pages"
    out_dir.mkdir(parents=True, exist_ok=True)

    rc, out = await _run_command(
        "pdftoppm",
        "-r",
        "110",
        "-l",
        "15",
        "-png",
        str(raw_path),
        str(out_dir / "page"),
        timeout=120,
    )
    if rc != 0:
        raise HTTPException(500, f"pdftoppm failed: {out[-500:]}")

    pages = sorted(out_dir.glob("page-*.png"))
    if not pages:
        raise HTTPException(500, "no pages rendered from PDF")

    return UploadResponse(
        sandbox_path=str(out_dir),
        size_bytes=sum(p.stat().st_size for p in pages),
        original_name=original_name,
        kind="document",
        pages=len(pages),
    )


@app.post("/api/upload", response_model=UploadResponse)
async def upload(file: UploadFile = File(...)):
    original_ext = Path(file.filename or "upload.mp4").suffix.lower() or ".mp4"
    uid = uuid.uuid4().hex[:8]
    raw_name = f"upload-{uid}{original_ext}"
    raw_path = UPLOAD_DIR / raw_name
    with raw_path.open("wb") as f:
        shutil.copyfileobj(file.file, f)

    if original_ext == ".pdf" or (file.content_type or "") == "application/pdf":
        return await _handle_pdf_upload(raw_path, uid, file.filename or raw_name)

    final_path = raw_path
    needs_transcode = original_ext in (".webm", ".ogg", ".opus", ".m4a", ".wav", ".flac", ".mka")
    if needs_transcode:
        is_audio_only = (
            (file.content_type or "").startswith("audio/")
            or original_ext in (".ogg", ".opus", ".m4a", ".wav", ".flac", ".mka", ".mp3")
        )
        if is_audio_only:
            out_path = UPLOAD_DIR / f"upload-{uid}.mp3"
            cmd = [
                "ffmpeg",
                "-nostdin",
                "-y",
                "-i",
                str(raw_path),
                "-vn",
                "-c:a",
                "libmp3lame",
                "-q:a",
                "4",
                str(out_path),
            ]
        else:
            out_path = UPLOAD_DIR / f"upload-{uid}.mp4"
            cmd = [
                "ffmpeg",
                "-nostdin",
                "-y",
                "-i",
                str(raw_path),
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-crf",
                "28",
                "-c:a",
                "aac",
                "-b:a",
                "96k",
                "-f",
                "mp4",
                "-movflags",
                "+faststart",
                str(out_path),
            ]
        rc, out = await _run_command(*cmd, timeout=600)
        if rc != 0 or not out_path.exists():
            raise HTTPException(500, f"transcode failed: {out[-500:]}")
        final_path = out_path

    is_audio_final = final_path.suffix.lower() in (".mp3", ".wav")
    size = final_path.stat().st_size

    video_inline_limit = 8 * 1024 * 1024
    longvideo_threshold_min = float(os.environ.get("LONGVIDEO_THRESHOLD_MIN", "30"))
    duration_seconds: float | None = None
    if not is_audio_final and size > video_inline_limit:
        duration_seconds = await _probe_duration_seconds(final_path)

    if (
        not is_audio_final
        and duration_seconds is not None
        and duration_seconds / 60 >= longvideo_threshold_min
    ):
        bundle = await _prepare_longvideo_bundle(final_path, uid, duration_seconds)
        return UploadResponse(
            sandbox_path=str(bundle),
            size_bytes=sum(p.stat().st_size for p in bundle.rglob("*") if p.is_file()),
            original_name=file.filename or bundle.name,
            kind="video",
        )

    if not is_audio_final and size > video_inline_limit:
        chunks = await _chunk_long_video(final_path, uid)
        return UploadResponse(
            sandbox_path=str(chunks),
            size_bytes=sum(p.stat().st_size for p in chunks.glob("*.mp4")),
            original_name=file.filename or chunks.name,
            kind="video",
        )

    return UploadResponse(
        sandbox_path=str(final_path),
        size_bytes=size,
        original_name=file.filename or final_path.name,
        kind="audio" if is_audio_final else "video",
    )


async def _prepare_longvideo_bundle(src: Path, uid: str, duration: float) -> Path:
    bundle = UPLOAD_DIR / f"upload-{uid}-longvideo"
    frames_dir = bundle / "frames"
    bundle.mkdir(exist_ok=True)
    frames_dir.mkdir(exist_ok=True)
    for old in bundle.glob("*"):
        if old.is_file():
            old.unlink()
    for old in frames_dir.glob("*"):
        old.unlink()

    audio_path = bundle / "audio.mp3"
    rc, out = await _run_command(
        "ffmpeg",
        "-nostdin",
        "-y",
        "-i",
        str(src),
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        "-c:a",
        "libmp3lame",
        "-b:a",
        "32k",
        str(audio_path),
        timeout=1800,
    )
    if rc != 0:
        raise HTTPException(500, f"audio extract failed: {out[-500:]}")

    timestamps = [duration * (i + 0.5) / 8 for i in range(8)]
    for i, ts in enumerate(timestamps):
        out_path = frames_dir / f"frame-{i:02d}-at-{int(ts)}s.jpg"
        await _run_command(
            "ffmpeg",
            "-nostdin",
            "-y",
            "-ss",
            f"{ts:.3f}",
            "-i",
            str(src),
            "-frames:v",
            "1",
            "-vf",
            "scale=854:480",
            "-q:v",
            "3",
            str(out_path),
            timeout=120,
        )

    frames = sorted(frames_dir.glob("frame-*.jpg"))
    manifest = {
        "source": str(src),
        "duration": duration,
        "audio": "audio.mp3",
        "frames": [
            {"name": f.name, "timestamp": float(f.stem.split("-at-")[1].rstrip("s"))}
            for f in frames
        ],
    }
    (bundle / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return bundle


async def _chunk_long_video(src: Path, uid: str) -> Path:
    chunks_dir = UPLOAD_DIR / f"upload-{uid}-chunks"
    chunks_dir.mkdir(exist_ok=True)
    for old in chunks_dir.glob("*"):
        old.unlink()

    rc, out = await _run_command(
        "ffmpeg",
        "-nostdin",
        "-y",
        "-i",
        str(src),
        "-vf",
        "scale=854:480,fps=24",
        "-c:v",
        "libx264",
        "-crf",
        "28",
        "-preset",
        "veryfast",
        "-force_key_frames",
        "expr:gte(t,n_forced*120)",
        "-c:a",
        "aac",
        "-b:a",
        "64k",
        "-f",
        "segment",
        "-segment_time",
        "120",
        "-reset_timestamps",
        "1",
        "-segment_format",
        "mp4",
        str(chunks_dir / "chunk_%03d.mp4"),
        timeout=1800,
    )
    if rc != 0:
        raise HTTPException(500, f"chunk transcode failed: {out[-500:]}")

    manifest = {"source": str(src), "chunks": []}
    offset = 0.0
    for path in sorted(chunks_dir.glob("chunk_*.mp4")):
        dur = await _probe_duration_seconds(path) or 0.0
        manifest["chunks"].append({"name": path.name, "start": offset, "end": offset + dur})
        offset += dur
    (chunks_dir / "chunks.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return chunks_dir


def _extract_answer(output: str) -> str:
    markers = ["--- Omni Answer ---", "--- Omni Synthesis ---", "--- Omni Analysis ---"]
    for marker in markers:
        if marker in output:
            text = output.split(marker, 1)[1]
            text = re.split(r"\n\[\d+.*?(?:tokens|payload).*?\]\s*$", text, flags=re.DOTALL)[0]
            return text.strip()
    return output.strip()


def _script_env() -> dict[str, str]:
    env = os.environ.copy()
    env["OMNI_API_URL"] = OMNI_API_URL
    env["OMNI_MODEL"] = OMNI_MODEL
    return env


async def _run_analyzer(path: str, prompt: str) -> tuple[int, str, str]:
    p = _safe_host_path(path)
    cmd = [PYTHON_BIN, str(ANALYZER), str(p), prompt]
    rc, out = await _run_command(*cmd, env=_script_env(), timeout=int(os.environ.get("OMNI_ANALYZE_TIMEOUT", "900")))
    return rc, " ".join(cmd), out


def _looks_like_lookup(prompt: str) -> bool:
    text = prompt.lower()
    return any(x in text for x in ("wikipedia", "look up", "lookup", "define ", "definition of", "what is fp", "jargon"))


def _extract_lookup_terms(prompt: str) -> list[str]:
    cleaned = re.sub(r"(?i)\b(look up|lookup|define|definition of|on wikipedia|what is|what are)\b", " ", prompt)
    cleaned = re.sub(r"[?.,;:!]", " ", cleaned)
    terms = [t.strip(" '\"") for t in re.split(r"\band\b|,", cleaned) if t.strip()]
    return terms[:4] or [prompt.strip()]


async def _run_direct_text(prompt: str) -> tuple[int, str, str]:
    if _looks_like_lookup(prompt):
        terms = _extract_lookup_terms(prompt)
        cmd = [PYTHON_BIN, str(LOOKUP), *terms]
        rc, out = await _run_command(*cmd, timeout=120)
        return rc, " ".join(cmd), out

    payload = {
        "model": OMNI_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.2,
        "top_k": 1,
        "max_tokens": 1024,
        "chat_template_kwargs": {"enable_thinking": False},
    }

    def post() -> str:
        req = urllib.request.Request(
            OMNI_API_URL,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.loads(resp.read())
        msg = data["choices"][0]["message"]
        return (msg.get("content") or msg.get("reasoning_content") or "").strip()

    try:
        text = await asyncio.to_thread(post)
    except Exception as exc:
        return 1, f"POST {OMNI_API_URL}", str(exc)
    return 0, f"POST {OMNI_API_URL}", text


def _compose_openclaw_prompt(prompt: str, file_path: str | None) -> str:
    user = " ".join(prompt.split())
    if file_path:
        return (
            f"The user uploaded a file at this explicit host path: {file_path}. "
            f"Use the video-analyze skill to inspect exactly this path. "
            f"After the tool returns, answer from its Omni Analysis output. "
            f"User question: {user}"
        )
    return user


async def _run_openclaw(prompt: str, file_path: str | None, session_id: str) -> tuple[int, str, str]:
    composed = _compose_openclaw_prompt(prompt, file_path)
    cmd = [
        "openclaw",
        "--profile",
        OPENCLAW_PROFILE,
        "agent",
        "--local",
        "--session-id",
        session_id,
        "--model",
        OPENCLAW_MODEL_REF,
        "--timeout",
        os.environ.get("OPENCLAW_AGENT_TIMEOUT", "900"),
        "--message",
        composed,
        "--json",
    ]
    rc, out = await _run_command(*cmd, env=_script_env(), timeout=int(os.environ.get("OPENCLAW_AGENT_TIMEOUT", "900")) + 30)
    if rc == 0:
        try:
            data = json.loads(out)
            text = "\n".join(p.get("text", "") for p in data.get("payloads", [])).strip()
            return rc, " ".join(cmd[:6]) + " ...", text or out
        except Exception:
            pass
    return rc, " ".join(cmd[:6]) + " ...", out


def _record_session(session_id: str, prompt: str, path: str | None, backend: str, rc: int, answer: str) -> None:
    row = {
        "id": session_id,
        "ts": _now(),
        "prompt": prompt,
        "path": path,
        "backend": backend,
        "returncode": rc,
        "answer_chars": len(answer),
    }
    with (LOG_DIR / "chat-sessions.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")


@app.post("/api/chat")
async def chat(req: ChatRequest):
    session_id = req.session_id or uuid.uuid4().hex[:12]
    backend = CHAT_BACKEND

    async def generator():
        yield _sse({"type": "session", "id": session_id})
        yield _sse({"type": "status", "text": "preparing local OpenClaw Omni route"})

        started = time.monotonic()
        if backend == "openclaw":
            yield _sse({"type": "tool", "tool": "openclaw-agent"})
            rc, cmd, out = await _run_openclaw(req.prompt, req.video_path, session_id)
            answer = out.strip()
        elif req.video_path:
            yield _sse({"type": "tool", "tool": "video-analyze"})
            rc, cmd, raw = await _run_analyzer(req.video_path, req.prompt)
            answer = _extract_answer(raw)
        else:
            yield _sse({"type": "tool", "tool": "omni-text" if not _looks_like_lookup(req.prompt) else "jargon-lookup"})
            rc, cmd, raw = await _run_direct_text(req.prompt)
            answer = _extract_answer(raw)

        elapsed = f"{time.monotonic() - started:.1f}s"
        yield _sse({"type": "exec", "cmd": cmd, "duration": elapsed, "exit": rc})
        _record_session(session_id, req.prompt, req.video_path, backend, rc, answer)
        if rc != 0:
            yield _sse({"type": "error", "error": answer[-2000:] or f"command failed: {cmd}"})
        elif answer:
            yield _sse({"type": "token", "text": answer + "\n"})
        else:
            yield _sse({"type": "error", "error": "No visible answer returned."})
        yield _sse({"type": "done"})

    return StreamingResponse(
        generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.get("/api/policy/stream")
async def policy_stream():
    async def generator():
        while True:
            await asyncio.sleep(15)
            yield _sse({
                "ts": time.time(),
                "verdict": "ALLOWED",
                "severity": "INFO",
                "binary": "native-host",
                "target": "local OpenClaw/vLLM route",
            })

    return StreamingResponse(generator(), media_type="text/event-stream")


@app.get("/api/video")
async def get_video(path: str):
    p = _safe_host_path(path)
    if p.is_dir():
        raise HTTPException(400, "path is a directory")
    if not p.exists():
        raise HTTPException(404, "file not found")
    return FileResponse(p, media_type="video/mp4")


@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "profile": OPENCLAW_PROFILE,
        "chat_backend": CHAT_BACKEND,
        "vllm_base_url": VLLM_BASE_URL,
        "omni_model": OMNI_MODEL,
        "upload_dir": str(UPLOAD_DIR),
    }


@app.get("/api/memory/summary")
async def memory_summary(limit: int = 25):
    path = LOG_DIR / "chat-sessions.jsonl"
    rows = []
    if path.exists():
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    rows.sort(key=lambda r: r.get("ts", ""), reverse=True)
    recent = [
        {
            "id": r.get("id", ""),
            "started": r.get("ts"),
            "updated": r.get("ts"),
            "model": OMNI_MODEL,
            "turns": 1,
            "total_messages": 2,
            "tool_calls": 1,
            "tools": [r.get("backend", "direct")],
            "first_prompt": (r.get("prompt") or "")[:200],
            "last_prompt": (r.get("prompt") or "")[:200],
            "attachment_count": 1 if r.get("path") else 0,
        }
        for r in rows[:limit]
    ]
    tools: dict[str, int] = {}
    for r in rows:
        tools[r.get("backend", "direct")] = tools.get(r.get("backend", "direct"), 0) + 1
    return {
        "stats": {
            "total_sessions": len(rows),
            "total_turns": len(rows),
            "total_tool_calls": len(rows),
            "total_attachments": sum(1 for r in rows if r.get("path")),
            "oldest": min((r.get("ts") for r in rows), default=None),
        },
        "top_tools": [{"name": k, "count": v} for k, v in sorted(tools.items(), key=lambda kv: kv[1], reverse=True)],
        "recent": recent,
    }


@app.post("/api/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    ext = Path(file.filename or "rec.webm").suffix.lower() or ".webm"
    uid = uuid.uuid4().hex[:8]
    raw_path = UPLOAD_DIR / f"voice-{uid}{ext}"
    with raw_path.open("wb") as f:
        shutil.copyfileobj(file.file, f)

    out_path = UPLOAD_DIR / f"voice-{uid}.mp3"
    rc, out = await _run_command(
        "ffmpeg",
        "-nostdin",
        "-y",
        "-i",
        str(raw_path),
        "-vn",
        "-c:a",
        "libmp3lame",
        "-q:a",
        "4",
        str(out_path),
        timeout=180,
    )
    if rc != 0 or not out_path.exists():
        raise HTTPException(500, f"transcode failed: {out[-500:]}")

    rc, _, raw = await _run_analyzer(
        str(out_path),
        "Transcribe this audio exactly. Output only the spoken words, no commentary or description.",
    )
    if rc != 0:
        raise HTTPException(500, raw[-1000:])
    return {"text": _extract_answer(raw)}


@app.get("/api/policy/rules")
async def policy_rules():
    return {
        "google_allowed": True,
        "block_count": 0,
        "hosts": [
            {
                "block": "native_local",
                "host": "127.0.0.1",
                "port": 8000,
                "rules": ["local vLLM OpenAI API"],
                "binaries": ["python3", "curl"],
                "is_demo_toggle": False,
            },
            {
                "block": "native_web",
                "host": "en.wikipedia.org",
                "port": 443,
                "rules": ["jargon lookup"],
                "binaries": ["python3"],
                "is_demo_toggle": False,
            },
            {
                "block": "native_web",
                "host": "api.dictionaryapi.dev",
                "port": 443,
                "rules": ["dictionary fallback"],
                "binaries": ["python3"],
                "is_demo_toggle": False,
            },
        ],
    }


class ToggleRequest(BaseModel):
    key: str
    enabled: bool


class GoogleToggleRequest(BaseModel):
    enabled: bool


DEMO_TOGGLES = {
    "nvidia_web": {"name": "nvidia.com", "hosts": ["nvidia.com", "www.nvidia.com"]},
    "google": {"name": "Google", "hosts": ["google.com", "www.google.com"]},
    "openai": {"name": "OpenAI", "hosts": ["openai.com", "chatgpt.com"]},
    "stackoverflow": {"name": "Stack Overflow", "hosts": ["stackoverflow.com"]},
    "reddit": {"name": "Reddit", "hosts": ["reddit.com", "www.reddit.com"]},
    "youtube": {"name": "YouTube", "hosts": ["youtube.com", "www.youtube.com"]},
}


@app.get("/api/policy/toggles")
async def list_toggles():
    return {
        "toggles": [
            {"key": key, "name": data["name"], "hosts": data["hosts"], "enabled": True}
            for key, data in DEMO_TOGGLES.items()
        ]
    }


@app.post("/api/policy/google")
async def policy_google(req: GoogleToggleRequest):
    return {"ok": True, "google_allowed": True, "block_count": 0, "native_only": True}


@app.post("/api/policy/toggle")
async def set_toggle(req: ToggleRequest):
    return {"ok": True, "key": req.key, "enabled": True, "native_only": True}


RED_TEAM_TARGETS = [
    ("nvidia.com", "https://www.nvidia.com"),
    ("Google", "https://google.com"),
    ("OpenAI", "https://openai.com"),
    ("npm registry", "https://registry.npmjs.org"),
    ("Wikipedia", "https://en.wikipedia.org/api/rest_v1/page/summary/NVIDIA"),
]


@app.post("/api/red-team")
async def red_team():
    async def gen():
        yield _sse({"type": "start", "count": len(RED_TEAM_TARGETS)})
        for name, url in RED_TEAM_TARGETS:
            yield _sse({"type": "running", "name": name, "url": url})
            t0 = time.monotonic()
            rc, out = await _run_command(
                "curl",
                "-sS",
                "-o",
                "/dev/null",
                "-w",
                "%{http_code}",
                "--max-time",
                "5",
                url,
                timeout=8,
            )
            http = out.strip() if rc == 0 else "000"
            yield _sse({
                "type": "result",
                "name": name,
                "url": url,
                "http_code": http,
                "blocked": http in ("000", "403"),
                "duration_ms": int((time.monotonic() - t0) * 1000),
            })
        yield _sse({"type": "done"})

    return StreamingResponse(gen(), media_type="text/event-stream")


UI_DIST = ROOT / "ui" / "dist"
if UI_DIST.is_dir():
    app.mount("/", StaticFiles(directory=str(UI_DIST), html=True), name="ui")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8765, log_level="info")
