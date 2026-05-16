---
name: jargon-lookup
description: Look up technical terms on Wikipedia first, with Free Dictionary as a fallback. Use when the user asks for definitions, acronyms, or jargon explanations.
version: 2.0.0
metadata:
  openclaw:
    requires:
      bins: ["python3"]
---

# Jargon Lookup

Use the host-side lookup helper:

```bash
python3 scripts/lookup-jargon.py "term" --context "optional domain"
```

Examples:

```bash
python3 scripts/lookup-jargon.py "FP8" --context "machine learning"
python3 scripts/lookup-jargon.py "transformer" --context "deep learning"
```

This OpenClaw-only version runs on the host and reports direct host
connectivity errors.
