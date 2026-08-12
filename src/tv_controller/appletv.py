"""Apple TV control via pyatv.

An Apple TV attached to a Samsung TV is the precision instrument: deep-link
straight into content (YouTube URLs, tv.apple.com episodes, app links) and
HDMI-CEC turns the TV on and switches input automatically.

pyatv is async; the agent's tools are sync, so every public function here
runs its own event loop. Pairing credentials persist in the config dir.
"""

from __future__ import annotations

import asyncio

from .config import ATV_CREDENTIALS_FILE, CONFIG_DIR

# Remote-control commands the agent may send, mapped to pyatv RemoteControl methods
COMMANDS = [
    "play", "pause", "play_pause", "stop", "menu", "home",
    "select", "up", "down", "left", "right",
    "skip_forward", "skip_backward", "volume_up", "volume_down",
]


def _require_pyatv():
    try:
        import pyatv  # noqa: F401
    except ImportError as exc:
        raise RuntimeError(
            "pyatv is not installed — run: pip install 'samsung-tv-controller[appletv]'"
        ) from exc


async def _storage(loop):
    from pyatv.storage.file_storage import FileStorage

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    storage = FileStorage(str(ATV_CREDENTIALS_FILE), loop)
    await storage.load()
    return storage


async def _connect(host: str):
    import pyatv

    loop = asyncio.get_running_loop()
    storage = await _storage(loop)
    confs = await pyatv.scan(loop, hosts=[host], timeout=5, storage=storage)
    if not confs:
        raise RuntimeError(f"no Apple TV found at {host} — is it plugged in and awake?")
    return await pyatv.connect(confs[0], loop, storage=storage)


def _run(coro):
    return asyncio.run(coro)


async def _wake(atv) -> None:
    """Turn the Apple TV on and wait until it's actually awake — a deep link
    sent while the box is still asleep is silently dropped."""
    from pyatv.const import PowerState

    await atv.power.turn_on()
    for _ in range(20):
        if atv.power.power_state == PowerState.On:
            await asyncio.sleep(1)  # let the UI come up before deep-linking
            return
        await asyncio.sleep(0.5)


# -- public sync API ----------------------------------------------------------

def scan() -> list[dict]:
    """Find Apple TVs on the network."""
    _require_pyatv()

    async def go():
        import pyatv

        loop = asyncio.get_running_loop()
        confs = await pyatv.scan(loop, timeout=5)
        return [
            {"name": c.name, "host": str(c.address), "model": str(c.device_info.model_str)}
            for c in confs
        ]

    return _run(go())


def pair(host: str) -> None:
    """Interactive pairing (shows a PIN on the TV). Run once per Apple TV."""
    _require_pyatv()

    async def go():
        import pyatv
        from pyatv.const import Protocol

        loop = asyncio.get_running_loop()
        storage = await _storage(loop)
        confs = await pyatv.scan(loop, hosts=[host], timeout=5, storage=storage)
        if not confs:
            raise RuntimeError(f"no Apple TV found at {host}")
        conf = confs[0]
        for protocol in (Protocol.Companion, Protocol.AirPlay):
            pairing = await pyatv.pair(conf, protocol, loop, storage=storage)
            await pairing.begin()
            if pairing.device_provides_pin:
                pin = input(f"Enter the PIN shown on the TV ({protocol.name}): ")
                pairing.pin(pin)
            await pairing.finish()
            await pairing.close()
        await storage.save()
        print(f"Paired with {conf.name} ({host}).")

    _run(go())


def play_url(host: str, url: str) -> str:
    """Deep-link into content: opens the URL on the Apple TV (which turns the
    TV on via HDMI-CEC). Works with YouTube watch URLs, tv.apple.com links,
    and any app's universal links."""
    _require_pyatv()

    async def go():
        atv = await _connect(host)
        try:
            await _wake(atv)
            await atv.apps.launch_app(url)  # accepts bundle IDs and URLs
            return f"playing {url}"
        finally:
            atv.close()

    return _run(go())


def launch_app(host: str, bundle_id: str) -> str:
    """Launch an app by tvOS bundle ID (e.g. com.google.ios.youtube)."""
    _require_pyatv()

    async def go():
        atv = await _connect(host)
        try:
            await _wake(atv)
            await atv.apps.launch_app(bundle_id)
            return f"launched {bundle_id}"
        finally:
            atv.close()

    return _run(go())


def remote(host: str, command: str) -> str:
    """Send a remote-control command (see COMMANDS)."""
    _require_pyatv()
    if command not in COMMANDS:
        raise ValueError(f"unknown command '{command}' — use one of: {', '.join(COMMANDS)}")

    async def go():
        atv = await _connect(host)
        try:
            await getattr(atv.remote_control, command)()
            return f"sent {command}"
        finally:
            atv.close()

    return _run(go())


def now_playing(host: str) -> dict:
    """What's currently playing on the Apple TV."""
    _require_pyatv()

    async def go():
        atv = await _connect(host)
        try:
            playing = await atv.metadata.playing()
            return {
                "state": str(playing.device_state),
                "title": playing.title,
                "app": atv.metadata.app.name if atv.metadata.app else None,
            }
        finally:
            atv.close()

    return _run(go())


def play_iview_latest(host: str, show_slug: str) -> str:
    """Play the latest episode of an ABC iview show via the iview:// scheme.

    Scrapes the show page for episode IDs (the tvOS iview app registers the
    iview:// scheme but not universal links), launches the newest, and clicks
    through iview's profile picker if it appears.
    """
    import re
    import ssl
    import time
    from urllib.request import Request, urlopen

    import certifi  # some Python installs (e.g. Homebrew) ship no CA bundle

    req = Request(
        f"https://iview.abc.net.au/show/{show_slug}",
        headers={"User-Agent": "Mozilla/5.0"},
    )
    ctx = ssl.create_default_context(cafile=certifi.where())
    html = urlopen(req, timeout=10, context=ctx).read().decode(errors="replace")
    vids = re.findall(r"/video/([A-Za-z]{2}\d{4}V\d+S\d{2})", html)
    if not vids:
        vids = re.findall(r"/video/([A-Za-z0-9]{8,})", html)
    if not vids:
        raise RuntimeError(f"no episodes found for iview show '{show_slug}'")

    def episode_number(v: str) -> int:
        m = re.search(r"V(\d+)S", v)
        return int(m.group(1)) if m else -1

    latest = max(dict.fromkeys(vids), key=episode_number)
    play_url(host, f"iview://video/{latest}")

    # The deep link lands on the episode page with Play focused, but iview may
    # first interpose its profile selector — a select dismisses each in turn.
    for _ in range(3):
        time.sleep(5)
        st = now_playing(host)
        if st.get("state") == "DeviceState.Playing":
            return f"playing '{st.get('title')}' ({latest}) in ABC iview"
        remote(host, "select")
    time.sleep(5)
    st = now_playing(host)
    if st.get("state") == "DeviceState.Playing":
        return f"playing '{st.get('title')}' ({latest}) in ABC iview"
    return (
        f"opened episode {latest} in ABC iview but playback isn't confirmed "
        f"(state={st.get('state')}) — the TV may be showing a sign-in or error screen"
    )


def power(host: str, state: str) -> str:
    """Turn the Apple TV (and via CEC, the attached TV) on or off."""
    _require_pyatv()

    async def go():
        atv = await _connect(host)
        try:
            if state == "on":
                await atv.power.turn_on()
            else:
                await atv.power.turn_off()
            return f"apple tv {state}"
        finally:
            atv.close()

    return _run(go())
