"""Wrapper around samsungtvws for controlling one or many Samsung TVs."""

from __future__ import annotations

import json
import time
from urllib.request import urlopen

from samsungtvws import SamsungTVWS
from wakeonlan import send_magic_packet

from .config import Config, TVConfig

# Common remote key codes the model can send. Any KEY_* code the TV supports
# also works; this list is what we advertise in the tool description.
KEY_CODES = [
    "KEY_POWER", "KEY_VOLUP", "KEY_VOLDOWN", "KEY_MUTE",
    "KEY_CHUP", "KEY_CHDOWN", "KEY_HOME", "KEY_MENU", "KEY_SOURCE",
    "KEY_GUIDE", "KEY_RETURN", "KEY_EXIT", "KEY_ENTER",
    "KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT",
    "KEY_0", "KEY_1", "KEY_2", "KEY_3", "KEY_4",
    "KEY_5", "KEY_6", "KEY_7", "KEY_8", "KEY_9",
    "KEY_PLAY", "KEY_PAUSE", "KEY_STOP", "KEY_REWIND", "KEY_FF",
    "KEY_HDMI", "KEY_HDMI1", "KEY_HDMI2", "KEY_HDMI3", "KEY_HDMI4",
    "KEY_NETFLIX", "KEY_AMAZON",
]

# App IDs for common Tizen apps (fallbacks when app_list() is unavailable)
WELL_KNOWN_APPS = {
    "netflix": "11101200001",
    "youtube": "111299001912",
    "prime video": "3201512006785",
    "disney+": "3201901017640",
    "spotify": "3201606009684",
    "plex": "3201512006963",
    "apple tv": "3201807016597",
}


class TV:
    """One Samsung TV, controlled over its local WebSocket API."""

    def __init__(self, cfg: TVConfig):
        self.cfg = cfg
        self._remote: SamsungTVWS | None = None

    @property
    def name(self) -> str:
        return self.cfg.name

    def _connect(self) -> SamsungTVWS:
        if self.cfg.host is None:
            raise RuntimeError(
                f"'{self.name}' has no Samsung TV (Apple TV-only room) — "
                "use the Apple TV tools instead"
            )
        if self._remote is None:
            self._remote = SamsungTVWS(
                host=self.cfg.host,
                port=self.cfg.port,
                token_file=str(self.cfg.token_file),
                name="samsung-tv-controller",
                timeout=8,
            )
        return self._remote

    # -- state ---------------------------------------------------------------

    def is_on(self) -> bool:
        if self.cfg.host is None:
            return False
        try:
            with urlopen(f"http://{self.cfg.host}:8001/api/v2/", timeout=2) as resp:
                info = json.loads(resp.read())
            return info.get("device", {}).get("PowerState", "on") == "on"
        except Exception:
            return False

    def status(self) -> dict:
        if self.cfg.host is None:
            return {"name": self.name, "host": "-", "power": "via apple tv"}
        on = self.is_on()
        return {"name": self.name, "host": self.cfg.host, "power": "on" if on else "off"}

    # -- actions -------------------------------------------------------------

    def send_key(self, key: str, repeat: int = 1) -> None:
        remote = self._connect()
        for _ in range(repeat):
            remote.send_key(key)
            time.sleep(0.15)

    def power_on(self) -> str:
        if self.is_on():
            return "already on"
        if self.cfg.mac:
            send_magic_packet(self.cfg.mac)
            return "sent wake-on-LAN packet"
        # No MAC configured: KEY_POWER only works if the TV's network stack is awake
        try:
            self.send_key("KEY_POWER")
            return "sent KEY_POWER (configure the TV's MAC for reliable wake)"
        except Exception as exc:
            return f"could not wake TV (no MAC configured for wake-on-LAN): {exc}"

    def power_off(self) -> str:
        if not self.is_on():
            return "already off"
        self.send_key("KEY_POWER")
        self._remote = None  # connection drops when the TV sleeps
        return "powered off"

    def list_apps(self) -> list[dict]:
        apps = self._connect().app_list() or []
        return [{"name": a.get("name"), "app_id": a.get("appId")} for a in apps]

    def launch_app(self, app: str) -> str:
        app_id = app if app.isdigit() else None
        if app_id is None:
            wanted = app.lower().strip()
            try:
                for entry in self.list_apps():
                    if wanted in (entry["name"] or "").lower():
                        app_id = entry["app_id"]
                        break
            except Exception:
                pass
            if app_id is None:
                app_id = WELL_KNOWN_APPS.get(wanted)
        if app_id is None:
            return f"unknown app '{app}' — try list_apps to see what's installed"
        self._connect().rest_app_run(app_id)
        return f"launched {app} ({app_id})"

    def open_url(self, url: str) -> str:
        self._connect().open_browser(url)
        return f"opened {url} in the TV browser"


class TVManager:
    """All the TVs in the house, keyed by name."""

    def __init__(self, config: Config | None = None):
        self.config = config or Config.load()
        self.tvs = {name: TV(cfg) for name, cfg in self.config.tvs.items()}

    @staticmethod
    def _norm(name: str) -> str:
        return "".join(c for c in name.lower() if c.isalnum())

    def get(self, name: str) -> TV:
        key = self._norm(name)
        by_norm = {self._norm(n): tv for n, tv in self.tvs.items()}
        if key in by_norm:
            return by_norm[key]
        # forgiving lookup: substring match on the normalized name
        matches = [tv for n, tv in by_norm.items() if key in n or n in key]
        if len(matches) == 1:
            return matches[0]
        known = ", ".join(self.tvs) or "(none configured)"
        raise KeyError(f"no TV named '{name}' — known TVs: {known}")

    def resolve(self, name: str) -> list[TV]:
        """Resolve a TV name, with 'all' meaning every TV."""
        if name.lower().strip() in ("all", "*", "everything", "every tv"):
            return list(self.tvs.values())
        return [self.get(name)]
