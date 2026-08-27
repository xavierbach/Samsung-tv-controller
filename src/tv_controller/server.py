"""The house brain: HTTP server that every device talks to.

Runs on an always-on machine (e.g. a MacBook Pro) on the home network.
The iPhone/iPad app, HomePod shortcuts, and anything else POST natural
language here; simple commands take the deterministic fast path (~200ms),
everything else goes through the Claude agent.

    tvctl serve --host 0.0.0.0 --port 8765

Endpoints:
    POST /command       {"text": "mute the bedroom tv", "room": "dining-room"?}
    POST /artwork       multipart: tv=<name>, image=<jpeg/png> — Frame TV Art Mode
    POST /generate-art  multipart: prompt=<text>, image=<reference photo>? —
                        AI-generated 16:9 artwork, returned base64 for preview
    POST /artwork-from-library  {"tv": ..., "id": ...} — hang a library item
    GET  /library       every artwork ever generated or cropped (metadata)
    GET  /library/{id}/image   full-size JPEG        /library/{id}/thumb
    DELETE /library/{id}       remove from the library (not from TVs)
    POST /discover  scan the LAN for Samsung TVs, merge into the config
    POST /authorize {"tv": "office-frame"} — pop that TV's Allow prompt
    GET  /status    power state (art mode, approval) of every TV
    GET  /health    liveness probe
"""

from __future__ import annotations

import base64
import logging
import threading
from concurrent.futures import ThreadPoolExecutor

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

from .fastpath import try_fast_path
from .tv import TVManager

app = FastAPI(title="Samsung TV super controller", version="0.2.0")

log = logging.getLogger("tvctl.server")

_lock = threading.Lock()
_manager: TVManager | None = None
_agent = None


def _get_manager() -> TVManager:
    global _manager
    if _manager is None:
        _manager = TVManager()
    return _manager


def _get_agent():
    global _agent
    if _agent is None:
        from .agent import TVAgent

        _agent = TVAgent(_get_manager())
    return _agent


class Command(BaseModel):
    text: str
    room: str | None = None  # optional hint, e.g. from a per-room shortcut
    source: str | None = None  # "iphone" | "ipad" | "homepod" | ...


class Reply(BaseModel):
    reply: str
    fast_path: bool


@app.post("/command", response_model=Reply)
def command(cmd: Command) -> Reply:
    text = cmd.text.strip()
    if cmd.room:
        # A room hint disambiguates: "turn it off" from the dining shortcut
        # becomes "turn it off (dining-room tv)"
        text = f"{text} ({cmd.room} tv)"

    manager = _get_manager()

    # TVs and agent history are not concurrency-safe, so commands run one at
    # a time — but a request must never queue forever behind a slow agent
    # turn: better to say we're busy than to look dead.
    if not _lock.acquire(timeout=15):
        return Reply(
            reply="Still working on an earlier command — try again in a moment.",
            fast_path=True,
        )
    try:
        fast = try_fast_path(manager, text)
        if fast is not None:
            return Reply(reply=fast, fast_path=True)
        try:
            reply = _get_agent().ask(text)
        except Exception as exc:
            log.exception("agent failed on %r", text)
            reply = f"Sorry, that didn't work: {exc}"
    finally:
        _lock.release()
    return Reply(reply=reply, fast_path=False)


def _hang(tv_name: str, data: bytes, file_type: str, library_id: str) -> str:
    """Upload to the TV, remember where it hangs, prune that TV's old ones.
    Caller holds the command lock."""
    from . import library

    tv = _get_manager().get(tv_name)
    reply, content_id = tv.set_artwork(data, file_type=file_type)
    library.record_hang(library_id, tv, content_id)
    return reply


@app.post("/artwork", response_model=Reply)
def artwork(tv: str = Form(...), image: UploadFile = File(...)) -> Reply:
    from . import library

    data = image.file.read()
    file_type = "png" if (image.content_type or "").endswith("png") else "jpg"

    # Uploading to the Frame takes a while; same one-at-a-time rule as /command.
    if not _lock.acquire(timeout=15):
        return Reply(
            reply="Still working on an earlier command — try again in a moment.",
            fast_path=True,
        )
    try:
        try:
            library_id = library.add(data, kind="photo")
            reply = _hang(tv, data, file_type, library_id)
        except Exception as exc:
            log.exception("artwork upload failed for %r", tv)
            reply = f"Couldn't set the artwork: {exc}"
    finally:
        _lock.release()
    return Reply(reply=reply, fast_path=True)


class ArtReply(BaseModel):
    reply: str
    fast_path: bool = True
    image_b64: str | None = None  # base64 image on success, absent on failure
    mime: str | None = None
    library_id: str | None = None  # saved in the artwork library under this id


@app.post("/generate-art", response_model=ArtReply)
def generate_art(
    prompt: str = Form(...),
    image: UploadFile | None = File(default=None),
) -> ArtReply:
    """Generate 16:9 AI artwork from a text prompt (plus an optional reference
    photo). Returns the image for in-app preview; hanging it on a TV goes
    through the existing POST /artwork. Generation touches no TV sockets, so
    it deliberately runs OUTSIDE the command lock — a 20s render must never
    block "mute the tv"."""
    from . import imagegen

    from . import library

    reference = image.file.read() if image is not None else None
    reference_mime = (image.content_type or "image/jpeg") if image is not None else "image/jpeg"
    try:
        data, mime = imagegen.generate(prompt, reference, reference_mime)
    except Exception as exc:
        log.exception("art generation failed for %r", prompt)
        return ArtReply(reply=f"Couldn't create the artwork: {exc}")
    library_id = library.add(data, kind="generated", prompt=prompt)
    return ArtReply(
        reply="Here's your artwork.",
        image_b64=base64.b64encode(data).decode(),
        mime=mime,
        library_id=library_id,
    )


class HangCmd(BaseModel):
    tv: str
    id: str


@app.post("/artwork-from-library", response_model=Reply)
def artwork_from_library(cmd: HangCmd) -> Reply:
    """Hang an already-saved library artwork on a TV — no re-upload from the
    phone needed."""
    from . import library

    data = library.get_image(cmd.id)
    if data is None:
        return Reply(reply="That artwork isn't in the library any more.", fast_path=True)
    if not _lock.acquire(timeout=15):
        return Reply(
            reply="Still working on an earlier command — try again in a moment.",
            fast_path=True,
        )
    try:
        try:
            reply = _hang(cmd.tv, data, "jpg", cmd.id)
        except Exception as exc:
            log.exception("library hang failed for %r on %r", cmd.id, cmd.tv)
            reply = f"Couldn't set the artwork: {exc}"
    finally:
        _lock.release()
    return Reply(reply=reply, fast_path=True)


@app.get("/library")
def library_items() -> list[dict]:
    from . import library

    return library.items()


@app.get("/library/{item_id}/image")
def library_image(item_id: str) -> FileResponse:
    from . import library

    path = library.image_path(item_id)
    if path is None:
        raise HTTPException(status_code=404)
    return FileResponse(path, media_type="image/jpeg")


@app.get("/library/{item_id}/thumb")
def library_thumb(item_id: str) -> FileResponse:
    from . import library

    path = library.image_path(item_id, thumb=True)
    if path is None:
        raise HTTPException(status_code=404)
    return FileResponse(path, media_type="image/jpeg")


@app.delete("/library/{item_id}", response_model=Reply)
def library_delete(item_id: str) -> Reply:
    from . import library

    if library.remove(item_id):
        return Reply(reply="Removed from the library.", fast_path=True)
    return Reply(reply="That artwork wasn't in the library.", fast_path=True)


class AuthorizeCmd(BaseModel):
    tv: str


@app.post("/discover", response_model=Reply)
def discover_tvs() -> Reply:
    """Scan the LAN for Samsung TVs and merge them into the config."""
    if not _lock.acquire(timeout=15):
        return Reply(
            reply="Still working on an earlier command — try again in a moment.",
            fast_path=True,
        )
    try:
        try:
            reply = _get_manager().discover_and_save()
        except Exception as exc:
            log.exception("discover failed")
            reply = f"Scan failed: {exc}"
    finally:
        _lock.release()
    return Reply(reply=reply, fast_path=True)


@app.post("/authorize", response_model=Reply)
def authorize(cmd: AuthorizeCmd) -> Reply:
    """Pop the Allow prompt on one TV and wait for the user to accept it."""
    if not _lock.acquire(timeout=15):
        return Reply(
            reply="Still working on an earlier command — try again in a moment.",
            fast_path=True,
        )
    try:
        try:
            reply = _get_manager().get(cmd.tv).authorize()
        except Exception as exc:
            log.exception("authorize failed for %r", cmd.tv)
            reply = f"Couldn't approve: {exc}"
    finally:
        _lock.release()
    return Reply(reply=reply, fast_path=True)


@app.get("/status")
def status() -> list[dict]:
    manager = _get_manager()

    # Each TV's status is an independent network probe (and, for Frames, an
    # Art Mode query) — run them concurrently so the slowest TV, not the sum
    # of all of them, bounds the response time.
    def one(tv) -> dict:
        s = tv.status()
        s["apple_tv"] = bool(tv.cfg.apple_tv)
        return s

    tvs = list(manager.tvs.values())
    with ThreadPoolExecutor(max_workers=max(1, len(tvs))) as pool:
        return list(pool.map(one, tvs))


@app.get("/health")
def health() -> dict:
    return {"ok": True}


def serve(host: str = "0.0.0.0", port: int = 8765) -> None:
    import uvicorn

    uvicorn.run(app, host=host, port=port, log_level="info")
