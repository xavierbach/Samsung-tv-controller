"""Natural-language layer: Claude decides which TV commands to run."""

from __future__ import annotations

import json
import os

import anthropic
from anthropic import beta_tool

from .tv import KEY_CODES, TVManager

MODEL = os.environ.get("TVCTL_MODEL", "claude-opus-5")

# The tool functions need access to the TV fleet; the runner calls them
# without extra arguments, so we keep the manager at module scope.
_manager: TVManager | None = None


def _mgr() -> TVManager:
    assert _manager is not None, "agent not initialised — call TVAgent()"
    return _manager


@beta_tool
def list_tvs() -> str:
    """List every configured TV with its name, IP address, and current power state."""
    return json.dumps([tv.status() for tv in _mgr().tvs.values()])


@beta_tool
def power(tv_name: str, state: str) -> str:
    """Turn a TV on or off. Call this when the user asks to turn a TV (or all TVs) on or off.

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
    """Send a remote-control key press to a TV. Use this for volume, channel,
    mute, navigation, playback control, and switching inputs (KEY_HDMI1 etc.).

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
    """Launch a streaming app on a TV. Call this when the user asks to open or
    watch Netflix, YouTube, Prime Video, Disney+, Spotify, Plex, Apple TV, or
    any other installed app.

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
    """List the apps installed on a TV (name and app ID). The TV must be on.

    Args:
        tv_name: Name of the TV.
    """
    try:
        return json.dumps(_mgr().get(tv_name).list_apps())
    except Exception as exc:
        return f"error: {exc}"


@beta_tool
def open_url(tv_name: str, url: str) -> str:
    """Open a web page in the TV's built-in browser.

    Args:
        tv_name: Name of the TV.
        url: Full URL to open, e.g. https://example.com.
    """
    try:
        return _mgr().get(tv_name).open_url(url)
    except Exception as exc:
        return f"error: {exc}"


TOOLS = [list_tvs, power, send_key, launch_app, list_apps, open_url]

SYSTEM_PROMPT = """\
You are a home TV controller for the Samsung TVs in the user's house.
Turn each request into the right tool calls and confirm briefly what you did.

- If the user doesn't name a TV and more than one exists, call list_tvs and ask
  which one they mean — unless the request clearly targets all of them
  ("turn everything off").
- "Louder"/"quieter" means send_key with KEY_VOLUP/KEY_VOLDOWN; scale repeat to
  the request (a little = 2, a lot = 8).
- If a command fails because the TV is off, say so and offer to turn it on.
- Keep replies to one or two sentences; the user wants their TV changed, not prose.
"""


class TVAgent:
    """Conversational agent driving the household's TVs."""

    def __init__(self, manager: TVManager | None = None):
        global _manager
        _manager = manager or TVManager()
        self.client = anthropic.Anthropic()
        self.messages: list = []

    def ask(self, user_input: str) -> str:
        """Send one user request through the tool-use loop; returns the reply."""
        self.messages.append({"role": "user", "content": user_input})
        runner = self.client.beta.messages.tool_runner(
            model=MODEL,
            max_tokens=2048,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=self.messages,
        )
        reply = ""
        for message in runner:
            # Mirror the runner's history so the conversation carries across turns
            self.messages.append({"role": "assistant", "content": message.content})
            tool_response = runner.generate_tool_call_response()
            if tool_response is not None:
                self.messages.append(tool_response)
            reply = "".join(b.text for b in message.content if b.type == "text")
        return reply or "(done)"
