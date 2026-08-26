"""AI artwork generation via Google's Gemini image model.

Turns a text prompt (optionally guided by a reference photo) into a 16:9
image sized for a Frame TV's Art Mode. Needs GEMINI_API_KEY — from the
environment, or from the setup-written env file next to the TV config,
same resolution order as the Anthropic key.
"""

from __future__ import annotations

import base64
import json
import os
import ssl
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import certifi

from .config import CONFIG_DIR

# macOS Pythons don't see the system trust store, so a bare urlopen fails
# TLS verification against Gemini — verify against certifi's bundle instead.
_SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())

MODEL = os.environ.get("TVCTL_IMAGE_MODEL", "gemini-2.5-flash-image")
API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

# The Frame hangs this on a wall: bias the model toward images that work as
# decor, and away from the captions and signatures it likes to add.
FRAME_PROMPT = (
    "Create a single artwork image to be displayed full-screen on a Samsung "
    "Frame TV hanging in a home — gallery-quality, edge to edge, with no "
    "text, captions, watermarks, signatures, or borders. The artwork: {prompt}"
)


def _api_key() -> str:
    key = os.environ.get("GEMINI_API_KEY")
    if key:
        return key
    env_file = CONFIG_DIR / "env"
    try:
        for line in env_file.read_text().splitlines():
            if line.startswith("GEMINI_API_KEY="):
                key = line.split("=", 1)[1].strip()
                if key:
                    return key
    except OSError:
        pass
    raise RuntimeError(
        "no Gemini API key — create one at https://aistudio.google.com/apikey, "
        f"add GEMINI_API_KEY=... to {CONFIG_DIR / 'env'}, and restart the server"
    )


def generate(
    prompt: str,
    reference: bytes | None = None,
    reference_mime: str = "image/jpeg",
) -> tuple[bytes, str]:
    """Generate one 16:9 artwork image. Returns (image bytes, mime type)."""
    parts: list[dict] = [{"text": FRAME_PROMPT.format(prompt=prompt.strip())}]
    if reference:
        parts.append({
            "inlineData": {
                "mimeType": reference_mime,
                "data": base64.b64encode(reference).decode(),
            }
        })
    body = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            # The model answers with text alongside the image; asking for
            # IMAGE alone is rejected.
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": {"aspectRatio": "16:9"},
        },
    }
    request = Request(
        API_URL.format(model=MODEL),
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": _api_key()},
        method="POST",
    )
    try:
        with urlopen(request, timeout=90, context=_SSL_CONTEXT) as resp:
            payload = json.loads(resp.read())
    except HTTPError as exc:
        detail = ""
        try:
            detail = json.loads(exc.read()).get("error", {}).get("message", "")
        except Exception:
            pass
        raise RuntimeError(
            f"Gemini rejected the request ({exc.code}): {detail or exc.reason}"
        ) from exc

    candidates = payload.get("candidates") or []
    out_parts = (candidates[0].get("content") or {}).get("parts") or [] if candidates else []
    for part in out_parts:
        inline = part.get("inlineData") or part.get("inline_data") or {}
        if inline.get("data"):
            mime = inline.get("mimeType") or inline.get("mime_type") or "image/png"
            return base64.b64decode(inline["data"]), mime
    # No image came back — surface whatever the model said instead (usually
    # a safety explanation), so the user knows to rephrase.
    text = " ".join(p.get("text", "") for p in out_parts).strip()
    raise RuntimeError(text or "the model returned no image — try rephrasing the prompt")
