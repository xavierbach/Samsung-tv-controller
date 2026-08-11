# Samsung TV Super Controller

Control every Samsung TV in your house with natural language.

```
you> turn everything off
All three TVs are now off.

you> put netflix on the living room tv and mute the bedroom one
Netflix is starting on the living room TV, and the bedroom TV is muted.
```

Under the hood it pairs two things:

- **[samsungtvws](https://github.com/xchwarze/samsung-tv-ws-api)** — talks to
  Samsung Tizen TVs (2016+) directly over their local WebSocket API: power,
  volume, key presses, launching apps, opening URLs. No cloud, no SmartThings
  account.
- **Claude API tool use** — a small agent that turns whatever you type into the
  right sequence of TV commands across one or many TVs.

## Setup

```bash
cd samsung-tv-controller
pip install -e .
export ANTHROPIC_API_KEY=sk-ant-...   # for the natural-language layer
```

### 1. Find your TVs

TVs must be on the same network. With the TVs on:

```bash
tvctl discover --save
```

Or add one manually (find the IP in the TV's network settings):

```bash
tvctl add living-room 192.168.1.40 --mac AA:BB:CC:DD:EE:FF
```

The `--mac` is optional but recommended — it enables wake-on-LAN so "turn on
the living room tv" works even when the TV is fully asleep. (Also enable
*Power On with Mobile* / *IP Remote* in the TV's settings.)

### 2. Pair

The first command you send to each TV pops up an **Allow?** prompt on its
screen. Accept it once; the token is cached locally after that.

```bash
tvctl list          # shows each TV and whether it's on
```

### 3. Talk to your TVs

```bash
tvctl chat                                    # interactive session
tvctl do "switch the living room tv to hdmi 2"  # one-shot
tvctl do "volume up a lot on the bedroom tv"
tvctl do "open youtube everywhere"
```

## What it can do

| You say | What happens |
|---|---|
| "turn off all the tvs" | power off every configured TV |
| "netflix on the living room tv" | launches the Netflix app |
| "mute everything" | KEY_MUTE to every TV |
| "louder" / "volume up a lot" | repeated KEY_VOLUP presses |
| "switch to hdmi 1" | input switching |
| "open reddit.com on the bedroom tv" | TV web browser |
| "which tvs are on?" | live power status |

Anything the Samsung remote can do via key codes, the agent can do — it knows
the full `KEY_*` vocabulary.

## Configuration

Lives in `~/.config/samsung-tv-controller/tvs.yaml`:

```yaml
tvs:
  living-room:
    host: 192.168.1.40
    mac: "AA:BB:CC:DD:EE:FF"
  bedroom:
    host: 192.168.1.41
```

Environment variables:

- `ANTHROPIC_API_KEY` — required for `chat` / `do`
- `TVCTL_MODEL` — Claude model to use (default `claude-opus-5`)
- `TVCTL_CONFIG_DIR` — override the config location

## Notes & limitations

- Works with Samsung **Tizen** TVs (roughly 2016 and newer). Older TVs use a
  different protocol and port 8001 without TLS (`--port 8001`).
- Volume is relative (key presses) — Samsung's WebSocket API has no absolute
  "set volume to 30". Say "volume up a lot" rather than "volume 30".
- Power off is a toggle key; the controller checks power state first so it
  never accidentally toggles a TV the wrong way.
- `discover`, `list`, `add` work without an API key — only the natural-language
  commands call Claude.
