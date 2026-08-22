# Samsung TV Super Controller

Control every TV in your house with natural language — from an iPhone, an
iPad, or any HomePod in the house.

```
"I want to watch ABC News in the dining room"
   → dining room TV turns on, ABC News live stream starts playing

"mute everything"        → ~200ms, no model call
"pause the bedroom"      → Apple TV pause
```

## Architecture

```
iPhone/iPad app ─┐  hold-to-talk, on-device speech
HomePods ────────┼─▶  Mac server (the brain)  ─▶  Samsung TVs   (power, volume, keys)
Siri Shortcut ───┘    fast path + Claude agent ─▶  Apple TVs     (content deep links)
                      + web search                 ─ HDMI-CEC turns the TV on
```

- **Mac server** (`tvctl serve`): every device POSTs natural language here.
  Reflex commands ("mute", "turn off the bedroom tv") match a deterministic
  fast path and execute in ~200ms; everything else goes through a Claude
  tool-use agent that can **web-search for the exact content** ("the latest
  ABC News" → a live-stream URL) and deep-link it.
- **Samsung TVs** via [samsungtvws](https://github.com/xchwarze/samsung-tv-ws-api):
  local WebSocket control — power, volume, key presses, Tizen apps. No cloud.
- **Apple TVs** (optional, per room) via [pyatv](https://pyatv.dev): the
  precision layer. Deep links play exact videos/episodes/streams, and
  HDMI-CEC turns the Samsung on and switches input automatically.
- **iPhone/iPad app** (`ios/`): SwiftUI hold-to-talk with on-device speech
  recognition — transcript is ready the instant you release. Also sets any
  photo as **Frame TV artwork**: pick an image, it's smart-cropped to 16:9
  on-device (Vision saliency keeps the subject in frame), you pick the TV,
  and it appears in Art Mode.
- **HomePods** (`docs/HOMEPOD.md`): a Siri Shortcut relays free-form voice
  commands from any room.

## Setup

### 1. The server (on an always-on Mac)

```bash
git clone https://github.com/xavierbach/samsung-tv-controller
cd samsung-tv-controller
pip install -e ".[appletv]"
export ANTHROPIC_API_KEY=sk-ant-...

tvctl discover --save        # find the Samsung TVs (accept the prompt on each)
tvctl list                   # check they respond
tvctl serve                  # run it in the foreground first to test
```

Try it from another machine on the network:

```bash
curl -X POST http://<mac>.local:8765/command \
  -H 'Content-Type: application/json' \
  -d '{"text": "which tvs are on?"}'
```

Then install it permanently:

```bash
./scripts/install-macos-server.sh    # launchd: starts at login, restarts on crash
```

Give the TVs and Apple TVs **DHCP reservations** in your router — discovery
flakiness is the #1 source of un-magic.

### 2. Apple TVs (as they arrive)

Plug into the Samsung, then from the Mac:

```bash
tvctl atv-scan                          # find it on the network
tvctl atv-pair dining-room 192.168.1.50 # PIN appears on the TV; links it to that room
```

In tvOS Settings enable **HDMI-CEC** (Settings → Remotes and Devices →
Control TVs and Receivers) so playing content turns the Samsung on. Assign
the Apple TV to its room in the Home app for native Siri control.

### 3. iPhone / iPad app

See [`ios/README.md`](ios/README.md) — one-time Xcode setup, then sideload.

### 4. HomePods

See [`docs/HOMEPOD.md`](docs/HOMEPOD.md) — a five-action Siri Shortcut.

## CLI reference

| Command | What it does |
|---|---|
| `tvctl discover --save` | SSDP scan for Samsung TVs, save to config |
| `tvctl add <name> <ip> --mac <mac>` | add a TV manually (MAC enables wake-on-LAN) |
| `tvctl list` | TVs, power state, linked Apple TVs |
| `tvctl serve` | run the home server (port 8765) |
| `tvctl atv-scan` / `tvctl atv-pair` | find and pair Apple TVs |
| `tvctl chat` / `tvctl do "..."` | talk to the TVs from the terminal |

## Configuration

`~/.config/samsung-tv-controller/tvs.yaml`:

```yaml
tvs:
  dining-room:
    host: 192.168.1.40
    mac: "AA:BB:CC:DD:EE:FF"     # wake-on-LAN
    apple_tv: 192.168.1.50       # the Apple TV plugged into this TV
  bedroom:
    host: 192.168.1.41
```

Environment variables: `ANTHROPIC_API_KEY` (required for the agent),
`TVCTL_MODEL` (default `claude-opus-5`), `TVCTL_CONFIG_DIR`.

## What's reliable vs. app-dependent

- **Reliable:** power, volume, inputs, launching apps, playing exact YouTube
  videos/live streams and other universal-link content via Apple TV,
  play/pause/skip.
- **App-dependent:** deep-linking *inside* apps that don't expose content
  URLs (some streaming apps only open to their home screen). News and sports
  route beautifully through official YouTube live streams; the agent does
  this automatically.

## Notes

- Samsung Tizen TVs, roughly 2016+. Older models: `--port 8001`.
- Volume is relative key presses (Samsung's local API has no absolute set).
- The server binds to your LAN only; nothing is exposed to the internet.
  For control away from home, put the Mac and phone on a Tailscale tailnet —
  no config changes needed.

## License

MIT
