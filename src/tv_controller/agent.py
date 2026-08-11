"""Natural-language layer: Claude decides which TV commands to run.

Tools span two devices per room: the Samsung TV itself (power, volume, keys,
Tizen apps) and, when configured, an Apple TV (content deep links, precise
playback control). A web_search server tool lets the model resolve "the
latest ABC News" into a concrete playable URL at request time.
"""

from __future__ import annotations

import json
import os

import anthropic
from anthropic import beta_tool

from .tv import KEY_CODES, TVManager

MODEL = os.environ.get("TVCTL_MODEL", "claude-opus-5")
MAX_HISTORY = 40  # message entries kept across turns
MAX_PAUSE_RESTARTS = 4

# The tool functions need access to the TV fleet; the runner calls them
# without extra arguments, so we keep the manager at module scope.
_manager: TVManager | None = None


def _mgr() -> TVManager:
    assert _manager is not None, "agent not initialised — call TVAgent()"
    return _manager


def _atv_host(tv_name: str) -> str:
    tv = _mgr().get(tv_name)
    if not tv.cfg.apple_tv:
        raise RuntimeError(
            f"'{tv.name}' has no Apple TV configured — fall back to the Samsung tools "
            "(launch_app / send_key) for this TV"
        )
    return tv.cfg.apple_tv


# -- Samsung TV tools ---------------------------------------------------------

@beta_tool
def list_tvs() -> str:
    """List every configured TV: name, IP, current power state, and whether it
    has an Apple TV attached (Apple TV rooms support content deep links)."""
    out = []
    for tv in _mgr().tvs.values():
        s = tv.status()
        s["apple_tv"] = bool(tv.cfg.apple_tv)
        out.append(s)
    return json.dumps(out)


@beta_tool
def power(tv_name: str, state: str) -> str:
    """Turn a Samsung TV on or off. For rooms with an Apple TV, prefer
    play_content / apple_tv_remote for turning on — HDMI-CEC is more reliable.

    Args:
        tv_name: Name of the TV, or "all" for every TV in the house.
        state: Either "on" or "off".
    """
    results = {}
    for tv in _mgr().resolve(tv_name):
        try:
            results[tv.name] = tv.power_on() if state == "on" else tv.power_off()
        except Exception as exc:
            results[tv.name] = f"error: {exc}"
    return json.dumps(results)


@beta_tool
def send_key(tv_name: str, key: str, repeat: int = 1) -> str:
    """Send a remote-control key press to a Samsung TV. Use this for volume,
    mute, channel, navigation, and switching inputs (KEY_HDMI1 etc.).

    Args:
        tv_name: Name of the TV, or "all" for every TV.
        key: A Samsung key code such as KEY_VOLUP, KEY_MUTE, KEY_HDMI1.
        repeat: How many times to press the key (e.g. 5 for "volume up a lot").
    """
    if key not in KEY_CODES and not key.startswith("KEY_"):
        return f"'{key}' is not a key code — use one of: {', '.join(KEY_CODES)}"
    results = {}
    for tv in _mgr().resolve(tv_name):
        try:
            tv.send_key(key, repeat=repeat)
            results[tv.name] = f"sent {key} x{repeat}"
        except Exception as exc:
            results[tv.name] = f"error: {exc}"
    return json.dumps(results)


@beta_tool
def launch_app(tv_name: str, app: str) -> str:
    """Launch a streaming app on the Samsung TV itself (Tizen). Use this only
    for TVs without an Apple TV; it opens the app but cannot pick content.

    Args:
        tv_name: Name of the TV, or "all" for every TV.
        app: App name (e.g. "netflix") or a numeric Tizen app ID.
    """
    results = {}
    for tv in _mgr().resolve(tv_name):
        try:
            results[tv.name] = tv.launch_app(app)
        except Exception as exc:
            results[tv.name] = f"error: {exc}"
    return json.dumps(results)


@beta_tool
def list_apps(tv_name: str) -> str:
    """List the apps installed on a Samsung TV (name and app ID). The TV must be on.

    Args:
        tv_name: Name of the TV.
    """
    try:
        return json.dumps(_mgr().get(tv_name).list_apps())
    except Exception as exc:
        return f"error: {exc}"


# -- Apple TV tools -----------------------------------------------------------

@beta_tool
def play_content(tv_name: str, url: str) -> str:
    """Play specific content on a room's Apple TV by deep link. This is THE way
    to play an exact video, episode, or live stream: the Apple TV turns the TV
    on via HDMI-CEC, switches input, opens the link, and playback starts.
    Works with YouTube watch URLs, tv.apple.com episode links, and other apps'
    universal links. Use web_search first to find the exact URL if needed.

    Args:
        tv_name: Name of the TV whose Apple TV should play the content.
        url: The content URL, e.g. https://www.youtube.com/watch?v=...
    """
    try:
        from . import appletv

        return appletv.play_url(_atv_host(tv_name), url)
    except Exception as exc:
        return f"error: {exc}"


@beta_tool
def apple_tv_remote(tv_name: str, command: str) -> str:
    """Send a playback/navigation command to a room's Apple TV: play, pause,
    play_pause, stop, menu, home, select, up, down, left, right,
    skip_forward, skip_backward, volume_up, volume_down.

    Args:
        tv_name: Name of the TV whose Apple TV should receive the command.
        command: One of the commands listed above.
    """
    try:
        from . import appletv

        return appletv.remote(_atv_host(tv_name), command)
    except Exception as exc:
        return f"error: {exc}"


@beta_tool
def now_playing(tv_name: str) -> str:
    """Check what's currently playing on a room's Apple TV (state, title, app).

    Args:
        tv_name: Name of the TV.
    """
    try:
        from . import appletv

        return json.dumps(appletv.now_playing(_atv_host(tv_name)))
    except Exception as exc:
        return f"error: {exc}"


TOOLS = [
    list_tvs, power, send_key, launch_app, list_apps,
    play_content, apple_tv_remote, now_playing,
    # Server-side web search: resolves "the latest ABC News" into a playable URL
    {"type": "web_search_20260209", "name": "web_search", "max_uses": 5},
]

SYSTEM_PROMPT = """\
You are the voice-controlled brain for the TVs in the user's house. Requests
arrive from a phone, an iPad, or a HomePod; your text reply may be spoken
aloud, so keep it to one short sentence.

The user is in Australia: "ABC" means the Australian Broadcasting Corporation
(not the US network). Prefer tv.apple.com/au links and ABC iview content.

Known content shortcuts (use these directly, no web_search needed):
- ABC News Victoria nightly 7pm bulletin: call play_content with
  https://tv.apple.com/au/show/abc-news-vic/umc.cmc.snbqs2tgfo1ijch40le29nuc
  (the TV app opens the show with the latest episode featured), then call
  apple_tv_remote with "select" to start playback.
- ABC News (Australia) 24/7 stream: web_search for the official ABC News
  Australia YouTube live stream and play_content its URL.
For other nightly shows, the same pattern works: find the tv.apple.com show
page, open it, then "select" plays the latest episode.

Routing rules:
- To play SPECIFIC content ("watch ABC News", "put on the F1 highlights"):
  if the room has an Apple TV, use web_search to find a concrete playable
  URL — prefer official YouTube live streams or channels for news/sports,
  tv.apple.com links for shows — then call play_content. This turns the TV
  on automatically; do not call power first.
- On TVs without an Apple TV, the best you can do is launch_app (opens the
  app; cannot pick the episode). Say so briefly.
- Volume and mute always go through the Samsung tools (send_key), never the
  Apple TV.
- Pause/play/skip on Apple TV rooms go through apple_tv_remote.
- "Turn off" goes through power (Samsung), which really turns the screen off.
- If the user doesn't name a room and more than one TV exists, call list_tvs
  and ask which one — unless the request clearly targets all of them.
- If something fails, say what failed in plain words and what you did instead.

Never narrate tool calls; just do the work and confirm the outcome in one
sentence.
"""


class TVAgent:
    """Conversational agent driving the household's TVs."""

    def __init__(self, manager: TVManager | None = None):
        global _manager
        _manager = manager or TVManager()
        self.client = anthropic.Anthropic()
        self.messages: list = []

    def _trim(self) -> None:
        """Cap history, cutting only at plain user-text boundaries so
        tool_use/tool_result pairs are never split."""
        if len(self.messages) <= MAX_HISTORY:
            return
        for i in range(1, len(self.messages)):
            m = self.messages[i]
            if m.get("role") == "user" and isinstance(m.get("content"), str):
                if len(self.messages) - i <= MAX_HISTORY:
                    del self.messages[:i]
                    return

    def ask(self, user_input: str) -> str:
        """Send one user request through the tool-use loop; returns the reply."""
        self.messages.append({"role": "user", "content": user_input})
        self._trim()

        last = None
        restarts = 0
        while True:
            runner = self.client.beta.messages.tool_runner(
                model=MODEL,
                max_tokens=2048,
                system=SYSTEM_PROMPT,
                tools=TOOLS,
                messages=self.messages,
            )
            for message in runner:
                last = message
                # Mirror the runner's history so conversation carries across turns
                self.messages.append({"role": "assistant", "content": message.content})
                tool_response = runner.generate_tool_call_response()
                if tool_response is not None:
                    self.messages.append(tool_response)
            # Server tools (web_search) can pause the turn; the runner exits on
            # pause, so restart it with the paused turn in history to resume.
            if last is None or last.stop_reason != "pause_turn":
                break
            restarts += 1
            if restarts > MAX_PAUSE_RESTARTS:
                break

        if last is None:
            return "(no response)"
        reply = "".join(b.text for b in last.content if b.type == "text")
        return reply or "(done)"
