"""The artwork library: everything ever generated or cropped for the Frames.

Full-size JPEGs and small thumbnails live in ~/.config/samsung-tv-controller/
library/, indexed by index.json. Each item records how it was made (an AI
prompt or a photo crop) and where it has hung, including the content_id the
TV assigned — which lets us prune OUR old uploads from a TV without ever
touching Samsung's store art or anything added by other means.
"""

from __future__ import annotations

import io
import json
import os
import threading
import time
import uuid

from PIL import Image

from .config import CONFIG_DIR

LIBRARY_DIR = CONFIG_DIR / "library"
INDEX_FILE = LIBRARY_DIR / "index.json"
THUMB_SIZE = (480, 270)

# How many of our uploads to keep on any one TV. The Frame's internal
# storage is finite, and the library on disk is the real archive anyway.
KEEP_PER_TV = 10

_lock = threading.Lock()


def _load() -> dict:
    try:
        return json.loads(INDEX_FILE.read_text())
    except (OSError, ValueError):
        return {"items": []}


def _save(index: dict) -> None:
    LIBRARY_DIR.mkdir(parents=True, exist_ok=True)
    tmp = INDEX_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(index, indent=1))
    os.replace(tmp, INDEX_FILE)


def add(data: bytes, kind: str, prompt: str | None = None) -> str:
    """Store one image (full size + thumbnail); returns its library id."""
    item_id = uuid.uuid4().hex[:12]
    LIBRARY_DIR.mkdir(parents=True, exist_ok=True)

    img = Image.open(io.BytesIO(data)).convert("RGB")
    full = io.BytesIO()
    img.save(full, "JPEG", quality=92)
    (LIBRARY_DIR / f"{item_id}.jpg").write_bytes(full.getvalue())
    img.thumbnail(THUMB_SIZE)
    thumb = io.BytesIO()
    img.save(thumb, "JPEG", quality=80)
    (LIBRARY_DIR / f"{item_id}.thumb.jpg").write_bytes(thumb.getvalue())

    with _lock:
        index = _load()
        index["items"].append({
            "id": item_id,
            "kind": kind,  # "generated" | "photo"
            "prompt": prompt,
            "created": time.time(),
            "hung": [],  # [{tv, content_id, at}]
        })
        _save(index)
    return item_id


def items() -> list[dict]:
    """Library metadata, newest first (no image bytes)."""
    with _lock:
        index = _load()
    out = []
    for item in sorted(index["items"], key=lambda i: i["created"], reverse=True):
        out.append({
            "id": item["id"],
            "kind": item["kind"],
            "prompt": item.get("prompt"),
            "created": item["created"],
            "hung_on": [h["tv"] for h in item.get("hung", [])],
        })
    return out


def image_path(item_id: str, thumb: bool = False):
    path = LIBRARY_DIR / (f"{item_id}.thumb.jpg" if thumb else f"{item_id}.jpg")
    return path if path.exists() else None


def get_image(item_id: str) -> bytes | None:
    path = image_path(item_id)
    return path.read_bytes() if path else None


def remove(item_id: str) -> bool:
    """Delete an item from the library (not from any TV it hangs on)."""
    with _lock:
        index = _load()
        before = len(index["items"])
        index["items"] = [i for i in index["items"] if i["id"] != item_id]
        if len(index["items"]) == before:
            return False
        _save(index)
    for suffix in (".jpg", ".thumb.jpg"):
        try:
            (LIBRARY_DIR / f"{item_id}{suffix}").unlink()
        except OSError:
            pass
    return True


def record_hang(item_id: str, tv, content_id: str) -> None:
    """Note that an item now hangs on a TV, then prune that TV back to the
    most recent KEEP_PER_TV of OUR uploads. Only content_ids we recorded are
    ever deleted, so store art and outside uploads are untouchable."""
    now = time.time()
    with _lock:
        index = _load()
        for item in index["items"]:
            if item["id"] == item_id:
                item.setdefault("hung", []).append(
                    {"tv": tv.name, "content_id": content_id, "at": now}
                )
                break
        hangs = sorted(
            (
                (h, item)
                for item in index["items"]
                for h in item.get("hung", [])
                if h["tv"] == tv.name
            ),
            key=lambda pair: pair[0]["at"],
        )
        stale = hangs[:-KEEP_PER_TV] if len(hangs) > KEEP_PER_TV else []
        # Drop the records now — if the TV delete fails (already removed by
        # hand, TV asleep), the record would otherwise pin dead entries.
        for h, item in stale:
            item["hung"].remove(h)
        _save(index)
    if stale:
        try:
            tv.delete_artworks([h["content_id"] for h, _ in stale])
        except Exception:
            pass  # nothing user-visible: the new artwork is already up
