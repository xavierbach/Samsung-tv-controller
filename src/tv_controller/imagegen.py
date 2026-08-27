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

# Bias the model toward decor-quality art and away from the captions and
# signatures it likes to add. Deliberately NO mention of TVs or hanging —
# told the art was "for a Frame TV", the model sometimes painted the TV
# itself, bezel, stand and all, around the artwork.
FRAME_PROMPT = (
    "Create a single gallery-quality piece of art that fills the entire "
    "image, edge to edge. Output only the artwork itself: no text, captions, "
    "watermarks, or signatures, and no borders, mats, picture frames, "
    "screens, or room mockups around it. The artwork: {prompt}"
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


# The Frame's panel. Anything much smaller gets auto-matted by the TV — a
# bezel around the art — instead of filling the screen edge to edge.
FRAME_SIZE = (3840, 2160)


def _call(body: dict) -> dict:
    request = Request(
        API_URL.format(model=MODEL),
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": _api_key()},
        method="POST",
    )
    try:
        with urlopen(request, timeout=90, context=_SSL_CONTEXT) as resp:
            return json.loads(resp.read())
    except HTTPError as exc:
        detail = ""
        try:
            detail = json.loads(exc.read()).get("error", {}).get("message", "")
        except Exception:
            pass
        raise RuntimeError(
            f"Gemini rejected the request ({exc.code}): {detail or exc.reason}"
        ) from exc


def _frame_ready(data: bytes) -> tuple[bytes, str]:
    """Center-crop to 16:9 if needed and resize to the Frame's exact 4K
    canvas, so the TV fills the screen instead of matting a small image."""
    from io import BytesIO

    from PIL import Image

    img = Image.open(BytesIO(data)).convert("RGB")
    w, h = img.size
    target = FRAME_SIZE[0] / FRAME_SIZE[1]
    if w / h > target:
        crop_w = round(h * target)
        x = (w - crop_w) // 2
        img = img.crop((x, 0, x + crop_w, h))
    elif w / h < target:
        crop_h = round(w / target)
        y = (h - crop_h) // 2
        img = img.crop((0, y, w, y + crop_h))
    if img.size != FRAME_SIZE:
        img = img.resize(FRAME_SIZE, Image.LANCZOS)
    out = BytesIO()
    img.save(out, "JPEG", quality=92)
    return out.getvalue(), "image/jpeg"


def generate(
    prompt: str,
    reference: bytes | None = None,
    reference_mime: str = "image/jpeg",
) -> tuple[bytes, str]:
    """Generate one artwork image at the Frame's full 3840x2160.
    Returns (image bytes, mime type)."""
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
            # 2K gives the 4K upscale below a sharper source than the 1K
            # default.
            "imageConfig": {"aspectRatio": "16:9", "imageSize": "2K"},
        },
    }
    try:
        payload = _call(body)
    except RuntimeError as exc:
        # Some model versions don't take imageSize — drop it and retry once.
        if "imagesize" not in str(exc).lower().replace("_", ""):
            raise
        del body["generationConfig"]["imageConfig"]["imageSize"]
        payload = _call(body)

    candidates = payload.get("candidates") or []
    out_parts = (candidates[0].get("content") or {}).get("parts") or [] if candidates else []
    for part in out_parts:
        inline = part.get("inlineData") or part.get("inline_data") or {}
        if inline.get("data"):
            return _frame_ready(base64.b64decode(inline["data"]))
    # No image came back — surface whatever the model said instead (usually
    # a safety explanation), so the user knows to rephrase.
    text = " ".join(p.get("text", "") for p in out_parts).strip()
    raise RuntimeError(text or "the model returned no image — try rephrasing the prompt")
