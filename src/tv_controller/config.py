"""Configuration for the household's TVs.

TVs are stored in ~/.config/samsung-tv-controller/tvs.yaml:

    tvs:
      living-room:
        host: 192.168.1.40
        mac: "AA:BB:CC:DD:EE:FF"   # optional, needed for wake-on-LAN power on
        apple_tv: 192.168.1.50     # optional, Apple TV attached to this TV
      bedroom:
        host: 192.168.1.41

Auth tokens issued by each TV (after you accept the on-screen prompt the
first time) are cached next to the config as <name>.token. Apple TV pairing
credentials live in appletv.credentials in the same directory.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml

CONFIG_DIR = Path(
    os.environ.get("TVCTL_CONFIG_DIR", Path.home() / ".config" / "samsung-tv-controller")
)
CONFIG_FILE = CONFIG_DIR / "tvs.yaml"
ATV_CREDENTIALS_FILE = CONFIG_DIR / "appletv.credentials"


@dataclass
class TVConfig:
    name: str
    host: str | None = None  # None = Apple TV-only room (non-Samsung TV, CEC-driven)
    mac: str | None = None
    port: int = 8002  # 8002 = wss (2018+ Tizen TVs); use 8001 for older models
    apple_tv: str | None = None  # IP of the Apple TV plugged into this TV

    @property
    def token_file(self) -> Path:
        return CONFIG_DIR / f"{self.name}.token"


@dataclass
class Config:
    tvs: dict[str, TVConfig] = field(default_factory=dict)

    @classmethod
    def load(cls) -> "Config":
        if not CONFIG_FILE.exists():
            return cls()
        raw = yaml.safe_load(CONFIG_FILE.read_text()) or {}
        tvs = {}
        for name, entry in (raw.get("tvs") or {}).items():
            tvs[name] = TVConfig(
                name=name,
                host=entry.get("host"),
                mac=entry.get("mac"),
                port=int(entry.get("port", 8002)),
                apple_tv=entry.get("apple_tv"),
            )
        return cls(tvs=tvs)

    def save(self) -> None:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        data = {
            "tvs": {
                tv.name: {
                    k: v
                    for k, v in {
                        "host": tv.host,
                        "mac": tv.mac,
                        "port": tv.port if tv.port != 8002 else None,
                        "apple_tv": tv.apple_tv,
                    }.items()
                    if v is not None
                }
                for tv in self.tvs.values()
            }
        }
        CONFIG_FILE.write_text(yaml.safe_dump(data, sort_keys=False))

    def add(self, tv: TVConfig) -> None:
        self.tvs[tv.name] = tv
