"""The house brain: HTTP server that every device talks to.

Runs on an always-on machine (e.g. a MacBook Pro) on the home network.
The iPhone/iPad app, HomePod shortcuts, and anything else POST natural
language here; simple commands take the deterministic fast path (~200ms),
everything else goes through the Claude agent.

    tvctl serve --host 0.0.0.0 --port 8765

Endpoints:
    POST /command   {"text": "mute the bedroom tv", "room": "dining-room"?}
    GET  /status    power state of every TV
    GET  /health    liveness probe
"""

from __future__ import annotations

import threading

from fastapi import FastAPI
from pydantic import BaseModel

from .fastpath import try_fast_path
from .tv import TVManager

app = FastAPI(title="Samsung TV super controller", version="0.2.0")

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

    with _lock:  # TVs and agent history are not concurrency-safe
        fast = try_fast_path(manager, text)
        if fast is not None:
            return Reply(reply=fast, fast_path=True)
        reply = _get_agent().ask(text)
    return Reply(reply=reply, fast_path=False)


@app.get("/status")
def status() -> list[dict]:
    manager = _get_manager()
    out = []
    for tv in manager.tvs.values():
        s = tv.status()
        s["apple_tv"] = bool(tv.cfg.apple_tv)
        out.append(s)
    return out


@app.get("/health")
def health() -> dict:
    return {"ok": True}


def serve(host: str = "0.0.0.0", port: int = 8765) -> None:
    import uvicorn

    uvicorn.run(app, host=host, port=port, log_level="info")
