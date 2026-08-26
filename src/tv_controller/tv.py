"""Wrapper around samsungtvws for controlling one or many Samsung TVs."""

from __future__ import annotations

import json
import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeoutError
from urllib.request import Request, urlopen

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

# Candidate app IDs for common Tizen apps, tried in order against the TV's
# REST API. IDs differ across firmware generations (newer first).
WELL_KNOWN_APPS = {
    "netflix": ["3201907018807", "11101200001"],
    "youtube": ["111299001912"],
    "prime video": ["3201910019365", "3201512006785"],
    "disney+": ["3201901017640"],
    "spotify": ["3201606009684"],
    "plex": ["3201512006963"],
    "apple tv": ["3201807016597"],
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
            # The timeout also bounds the first-connect approval: the TV shows
            # an Allow prompt and only sends the auth token once the user
            # accepts. 8s wasn't enough to find the remote — the connection
            # died un-tokened and every later command prompted again.
            self._remote = SamsungTVWS(
                host=self.cfg.host,
                port=self.cfg.port,
                token_file=str(self.cfg.token_file),
                name="samsung-tv-controller",
                timeout=30,
            )
        return self._remote

    # -- state ---------------------------------------------------------------

    def _device_info(self) -> dict:
        if self.cfg.host is None:
            return {}
        try:
            with urlopen(f"http://{self.cfg.host}:8001/api/v2/", timeout=2) as resp:
                info = json.loads(resp.read())
            return info.get("device") or {}
        except Exception:
            return {}

    def is_on(self) -> bool:
        device = self._device_info()
        return bool(device) and device.get("PowerState", "on") == "on"

    def status(self) -> dict:
        if self.cfg.host is None:
            return {"name": self.name, "host": "-", "power": "via apple tv", "art_mode": False}
        device = self._device_info()
        on = bool(device) and device.get("PowerState", "on") == "on"
        return {
            "name": self.name,
            "host": self.cfg.host,
            "power": "on" if on else "off",
            # Frame TVs advertise Art Mode support in their device info
            "art_mode": device.get("FrameTVSupport") == "true",
        }

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
        # Newer Frame firmware never answers the websocket app-list request,
        # leaving recv blocked past the library's own timeout — so the call
        # runs in a worker thread we can abandon.
        remote = self._connect()
        pool = ThreadPoolExecutor(max_workers=1)
        future = pool.submit(remote.app_list)
        pool.shutdown(wait=False)
        try:
            apps = future.result(timeout=8) or []
        except FutureTimeoutError:
            self._remote = None  # the abandoned thread still owns that socket
            raise TimeoutError(
                "the TV never answered the app list request (newer Samsung "
                "firmware often doesn't) — use a well-known app name instead"
            ) from None
        return [{"name": a.get("name"), "app_id": a.get("appId")} for a in apps]

    def _app_exists(self, app_id: str) -> bool:
        try:
            url = f"http://{self.cfg.host}:8001/api/v2/applications/{app_id}"
            with urlopen(url, timeout=3) as resp:
                return json.loads(resp.read()).get("id") == app_id
        except Exception:
            return False

    def launch_app(self, app: str) -> str:
        wanted = app.lower().strip()
        candidates = [app] if app.isdigit() else WELL_KNOWN_APPS.get(wanted, [])
        app_id = next((c for c in candidates if self._app_exists(c)), None)
        if app_id is None and not app.isdigit():
            try:
                for entry in self.list_apps():
                    if wanted in (entry["name"] or "").lower():
                        app_id = entry["app_id"]
                        break
            except Exception:
                pass
        if app_id is None:
            return f"unknown app '{app}' — try list_apps to see what's installed"
        req = Request(
            f"http://{self.cfg.host}:8001/api/v2/applications/{app_id}",
            method="POST",
        )
        with urlopen(req, timeout=8):
            pass
        return f"launched {app} ({app_id})"

    def open_url(self, url: str) -> str:
        self._connect().open_browser(url)
        return f"opened {url} in the TV browser"

    def set_artwork(self, image: bytes, file_type: str = "jpg") -> str:
        """Upload an image to a Frame TV and show it in Art Mode."""
        if self.cfg.host is None:
            raise RuntimeError(f"'{self.name}' has no Samsung TV to hang artwork on")
        # A sleeping Frame won't answer device info or accept the upload
        # socket, so wake it before judging anything.
        device = self._device_info()
        if not device or device.get("PowerState", "on") != "on":
            self.power_on()
            for _ in range(20):
                device = self._device_info()
                if device and device.get("PowerState", "on") == "on":
                    break
                time.sleep(0.5)
        if not device:
            raise RuntimeError(f"'{self.name}' isn't answering — is it plugged in?")
        if device.get("FrameTVSupport") != "true":
            raise RuntimeError(
                f"'{self.name}' is not a Frame TV — it can't display Art Mode artwork"
            )
        art = self._connect().art()
        try:
            content_id = art.upload(image, file_type=file_type, matte="none")
            art.select_image(content_id)
        finally:
            art.close()
        return f"the artwork is up on the {self.name} TV"


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
