"""Deterministic fast path for reflex commands.

Simple, unambiguous requests ("mute", "turn off the bedroom tv", "volume up")
skip the model entirely and execute in ~200ms. Anything this module isn't
sure about returns None and falls through to the Claude agent.

Rules of the lane: only match when both the ACTION and the TARGET are
unambiguous. When in doubt, stay out — a wrong guess here is worse than a
two-second wait.
"""

from __future__ import annotations

import json
import re

from .tv import TVManager

_ALL = r"(?:all(?: the)?(?: tvs?)?|every\s*(?:thing|where|tv)?|the house)"


def _find_target(manager: TVManager, text: str) -> list | None:
    """Resolve which TV(s) the text refers to. None = ambiguous, bail out."""
    if re.search(_ALL, text):
        return list(manager.tvs.values())
    named = [
        tv for name, tv in manager.tvs.items()
        if re.search(re.escape(name.replace("-", " ")), text.replace("-", " "))
    ]
    if len(named) == 1:
        return named
    if not named and len(manager.tvs) == 1:
        return list(manager.tvs.values())  # one TV in the house: no ambiguity
    return None


_PATTERNS: list[tuple[str, str, int]] = [
    # (regex, key code, repeat)
    (r"\b(?:un)?mute\b", "KEY_MUTE", 1),
    (r"\b(volume up a lot|much louder|way louder)\b", "KEY_VOLUP", 8),
    (r"\b(volume up|louder|turn it up)\b", "KEY_VOLUP", 3),
    (r"\b(volume down a lot|much quieter|way quieter)\b", "KEY_VOLDOWN", 8),
    (r"\b(volume down|quieter|softer|turn it down)\b", "KEY_VOLDOWN", 3),
    (r"\bpause\b", "KEY_PAUSE", 1),
    (r"\b(play|resume|unpause)\b", "KEY_PLAY", 1),
    (r"\bchannel up\b", "KEY_CHUP", 1),
    (r"\bchannel down\b", "KEY_CHDOWN", 1),
]


def try_fast_path(manager: TVManager, text: str) -> str | None:
    """Execute the command directly if it's a simple, unambiguous one.

    Returns a short reply string on success, or None to fall through
    to the agent.
    """
    t = text.lower().strip().rstrip(".!")

    targets = _find_target(manager, t)
    if targets is None:
        return None
    # Apple TV-only rooms (no Samsung) need the agent's Apple TV tools
    if any(tv.cfg.host is None for tv in targets):
        return None

    # power on/off
    m = re.search(r"\b(?:turn|power|switch)\s+(on|off)\b|\b(on|off)\b\s*$", t)
    if m and re.search(r"\b(turn|power|switch|shut)\b", t):
        state = m.group(1) or m.group(2)
        results = {}
        for tv in targets:
            try:
                results[tv.name] = tv.power_on() if state == "on" else tv.power_off()
            except Exception as exc:
                results[tv.name] = f"error: {exc}"
        return _summarize(state, results)

    for pattern, key, repeat in _PATTERNS:
        if re.search(pattern, t):
            results = {}
            for tv in targets:
                try:
                    tv.send_key(key, repeat=repeat)
                    results[tv.name] = "ok"
                except Exception as exc:
                    results[tv.name] = f"error: {exc}"
            return _summarize(key.replace("KEY_", "").lower(), results)

    return None


def _summarize(action: str, results: dict) -> str:
    errors = {k: v for k, v in results.items() if str(v).startswith("error")}
    if not errors:
        names = ", ".join(results)
        return f"Done — {action} on {names}."
    return f"{action}: " + json.dumps(results)
