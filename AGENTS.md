# Agent Notes

This is an OpenClaw-only conversion of the Hermes Omni demo.

- Do not add NemoClaw or OpenShell setup steps.
- The web UI defaults to `OPENCLAW_CHAT_BACKEND=direct` for media responsiveness.
- Keep `OPENCLAW_CHAT_BACKEND=openclaw` working for skill-routing smoke tests.
- Uploaded files should remain on the host under `/tmp/openclaw-omni-uploads`.
- The OpenClaw profile name is `openclaw-hermes-omni`.
- The dashboard port is `18792`.
- The vLLM Omni endpoint is `http://127.0.0.1:8000/v1`.

When updating setup docs, include clean-host prerequisites and avoid assuming passwordless sudo.
