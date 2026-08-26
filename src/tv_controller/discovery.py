"""Discover Samsung TVs on the local network via SSDP (UPnP)."""

from __future__ import annotations

import re
import socket
from dataclasses import dataclass
from urllib.request import urlopen

SSDP_ADDR = ("239.255.255.250", 1900)
SSDP_MX = 2
# Samsung Tizen TVs answer to this search target
SEARCH_TARGETS = [
    "urn:samsung.com:device:RemoteControlReceiver:1",
    "urn:schemas-upnp-org:device:MediaRenderer:1",
]


@dataclass
class DiscoveredTV:
    host: str
    friendly_name: str
    model: str | None = None
    mac: str | None = None  # for wake-on-LAN; the TV reports it itself


def _ssdp_search(st: str, timeout: float = 3.0) -> set[str]:
    """Return the set of responder IPs for one SSDP search target."""
    msg = "\r\n".join(
        [
            "M-SEARCH * HTTP/1.1",
            f"HOST: {SSDP_ADDR[0]}:{SSDP_ADDR[1]}",
            'MAN: "ssdp:discover"',
            f"MX: {SSDP_MX}",
            f"ST: {st}",
            "",
            "",
        ]
    ).encode()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    hosts: set[str] = set()
    try:
        sock.sendto(msg, SSDP_ADDR)
        while True:
            try:
                data, addr = sock.recvfrom(65507)
            except socket.timeout:
                break
            if b"Samsung" in data or b"samsung" in data:
                hosts.add(addr[0])
    finally:
        sock.close()
    return hosts


def _device_info(host: str) -> DiscoveredTV:
    """Query the TV's REST API for its name and model."""
    try:
        import json

        with urlopen(f"http://{host}:8001/api/v2/", timeout=3) as resp:
            info = json.loads(resp.read())
        device = info.get("device", {})
        name = device.get("name") or f"samsung-tv-{host}"
        # Strip the "[TV] " prefix Samsung puts on names
        name = re.sub(r"^\[TV\]\s*", "", name)
        return DiscoveredTV(
            host=host,
            friendly_name=name,
            model=device.get("modelName"),
            mac=device.get("wifiMac"),
        )
    except Exception:
        return DiscoveredTV(host=host, friendly_name=f"samsung-tv-{host}")


def discover(timeout: float = 3.0) -> list[DiscoveredTV]:
    """Scan the LAN and return all Samsung TVs found."""
    hosts: set[str] = set()
    for st in SEARCH_TARGETS:
        hosts |= _ssdp_search(st, timeout=timeout)
    return [_device_info(h) for h in sorted(hosts)]
