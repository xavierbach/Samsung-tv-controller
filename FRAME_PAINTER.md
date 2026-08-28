# Frame Painter — project kickoff

A standalone, App Store-ready iOS app that turns Samsung Frame TVs into a
personal art gallery. This document is the founding brief for a **new
repository / new Claude coding project**: it defines the product, the
architecture, and — critically — everything already learned and built in the
[samsung-tv-controller](https://github.com/xavierbach/samsung-tv-controller)
project that should be carried over.

**Working name:** Frame Painter (check App Store name availability at first
App Store Connect setup; fallbacks: "Frame Painter — Art for Frame TV",
"FramePainter"). Suggested bundle id: `com.<yourname>.framepainter`.

---

## 1. Vision

Anyone with a Samsung Frame TV opens the app, it finds their TVs, and within
a minute they're hanging art:

- **Any photo** from their library, smart-cropped to the Frame's 16:9 canvas
  so faces and subjects stay in frame — no decapitated portraits.
- **AI-generated artwork** from a text description, with style presets and an
  optional reference photo.
- Everything they've ever hung lives in an in-app **library** — browse,
  re-hang on any TV, delete.

No companion server, no account required for the core photo path. The phone
talks to the TVs directly over the local network.

## 2. Where this comes from

The parent project is a home-automation system with a Mac server as the
brain. Its **hero feature** — the Art Studio (AI artwork + smart-cropped
photos hung on Frame TVs, with a library) — is what Frame Painter productizes.
The key difference:

| | samsung-tv-controller | Frame Painter |
|---|---|---|
| TV control | Mac server (Python, `samsungtvws`) | **On-device Swift**, direct WebSocket to the TV |
| Smart crop | On-device (Vision) — already Swift | Reused as-is |
| AI generation | Mac server calls Gemini | Cloud proxy or BYO key (see §7) |
| Library | Server disk (`index.json` + JPEGs) | On-device (files + SwiftData index) |
| Audience | Personal / sideloaded | **Public App Store release** |

The Python server code is the **protocol reference** for the Swift port —
it encodes a lot of hard-won knowledge about real Frame TVs (see §9).

## 3. Competitive landscape (App Store scan, August 2026)

Surveyed before writing a line of code, so Frame Painter isn't rebuilding
something that exists. Re-verify pricing/features at kickoff — this market
moves.

### Direct competitors

| App | Hangs directly on the TV? | AI generation? | Price | Signal |
|---|---|---|---|---|
| **SmartThings** (Samsung, official) | Yes | No | Free | The baseline every Frame owner already has. Photo upload is buried in a multi-tap Art Mode flow; no smart crop, no generation. Clunky enough that a whole third-party category exists. |
| [**Frame Crop – Art Mode**](https://apps.apple.com/us/app/frame-crop-art-mode/id6443996847) | **Yes** (Frame + Hisense CanvasTV) | No | $7.99 one-time | **The app to beat.** 4.7★ / ~500 ratings, actively updated. Auto + manual crop, batch of 10, custom mats, portrait-Frame support, connection diagnostics, and free art libraries (Smithsonian, Wikimedia, Unsplash, The MET, Art Institute, Cleveland). |
| [**MP Art**](https://apps.apple.com/us/app/mp-art/id6757153314) | Yes | No (AI *descriptions*/narration only) | Free + $9.99/yr | New entrant (handful of ratings). 790k+ museum artworks from 5 museums, photo filters, 21 matte styles, 15 free TV syncs then subscription. |
| [**Frame TV Pics**](https://apps.apple.com/us/app/frame-tv-pics/id6467582232) | **No** — prepares images, hands off to SmartThings | No | Free + $3.99 ad removal | 4.7★ / ~120 ratings. Mats, soft frames, signatures, "Magic Framing". Prep-only workflow is its ceiling. |
| [**Samsung Frame Art Tool**](https://apps.apple.com/us/app/samsung-frame-art-tool/id1539969966) | No — crop/resize only, upload via SmartThings/USB | No | $3.99 IAP | 3.1★, stale since 2023. Evidence that prep-only + friction gets punished in reviews. |

### Adjacent, not competing

- **Web art services** ([frametvartist.com](https://www.frametvartist.com/),
  [Art For Frame](https://artforframe.com/), Etsy sellers, NightCafe's
  ["Frame TV art" galleries](https://creator.nightcafe.studio/gallery/free-frame-tv-art)):
  sell or generate art *files* the user must then upload themselves. Proves
  people pay for Frame art; none closes the loop to the TV.
- **AI-art apps** (AI Frame, DreamFrame, etc.): generation with no Frame TV
  integration at all.
- **GitHub hacker projects**
  ([jonwomack/samsung-frame-tv-art](https://github.com/jonwomack/samsung-frame-tv-art),
  [vishwanath79/frame-ai-art](https://github.com/vishwanath79/frame-ai-art)):
  Python scripts generating AI art and pushing it to Frames — demand for
  exactly our AI path exists, currently served only to people who run Python.

### What this means for Frame Painter

1. **The open gap — and the whole positioning — is AI generation + direct
   hang in one consumer app.** Nothing on the App Store does it (as of this
   scan). The AI studio is the hero: lead the name-adjacent branding, the
   screenshots, and the first-launch experience with it, not with photo
   upload.
2. **Photo path is table stakes, not a differentiator.** Frame Crop does it
   well for $7.99. Ours must be at least as smooth (the saliency smart crop
   is our edge — nobody else auto-keeps subjects in frame) and free, which
   undercuts every paid competitor on their core feature.
3. **Monetization fits the gap:** free photo path beats Frame Crop on price;
   the AI subscription (§7) monetizes the thing nobody else sells.
4. **Roadmap table stakes to match over time** (v1.x, not v1): optional
   rendered mats (we upload `matte: "none"`; competitors' mats are popular —
   render them into the JPEG client-side), batch upload, portrait-mounted
   Frame support, and free public-domain art libraries (Smithsonian/MET
   APIs) as a third content source next to Photos and AI.
5. **Risks:** Frame Crop is one update away from bolting on AI generation,
   and Samsung could fold generation into SmartThings (their TVs already
   market "generative wallpaper"). Speed to TestFlight matters; so does
   out-executing on generation quality (the tuned prompt) and crop taste.

## 4. Product spec

### 4.1 Onboarding & TV setup

1. First launch: a short intro screen, then **Scan for TVs**.
2. Scan finds Samsung TVs on the Wi-Fi network (see §6.1). Each result shows
   the TV's friendly name (strip Samsung's `[TV] ` prefix), model, and a
   **Frame badge** when `FrameTVSupport == "true"`. Non-Frame Samsungs are
   shown greyed out with "not a Frame TV" — honest, avoids bad reviews.
3. Tapping a TV saves it to the app and starts **authentication**: the app
   opens the authenticated remote socket, the TV pops its one-time *Allow*
   prompt, the user accepts with the TV remote, and the returned token is
   stored in the **Keychain**. From then on every connection is silent.
4. TVs can be renamed, re-scanned, added manually by IP (fallback for
   networks where discovery is blocked — e.g. AP client isolation), and
   removed.

UX details that matter (learned the hard way):
- The Allow prompt needs a **generous connect timeout (~30s)** — people have
  to find the TV remote. Show "Look at your TV and press Allow" with a
  spinner, not a fast-failing request.
- A **sleeping Frame won't answer**; offer wake-on-LAN (the scan records the
  TV's Wi-Fi MAC from device info) and tell the user to make sure the TV is
  on for first-time approval.
- Recommend DHCP reservations in a troubleshooting page; changing TV IPs is
  the #1 source of "it stopped working". Better: re-resolve by scanning when
  a saved TV stops answering, and match on MAC to update the stored IP
  automatically.

### 4.2 Photo path

1. **Pick any image** (PhotosPicker; also accept share-sheet / paste later).
2. **Smart crop to 16:9**: Vision attention-based saliency places the crop
   window so the subject stays in frame (port `SmartCropper.swift`
   verbatim — it's already production Swift). Show the crop **preview** and
   let the user **drag to adjust** along the long axis (new feature: the
   saliency placement is the default, not a cage).
3. **Pick a TV** (or the only TV auto-selects), tap **Hang it** → the app
   uploads the JPEG to the Frame's Art Mode and selects it as the current
   artwork.
4. The image is saved to the in-app library automatically.

### 4.3 AI generator path (port of the Art Studio)

1. Describe the artwork in words. Style chips (from the existing app):
   *Oil painting, Watercolor, Impressionist, Japanese woodblock, Minimal
   line art, Abstract, Pop art, Photorealistic* — appended to the prompt as
   `". Style: <style lowercased>."`.
2. Optional **reference photo** to guide the generation.
3. Generate → full-screen 16:9 preview → **Hang it on a TV** or regenerate.
4. Generated pieces are saved to the library with their prompt.

Generation details to preserve (from `imagegen.py`):
- Wrap the user prompt in the tuned system prompt (`FRAME_PROMPT`): demand a
  single edge-to-edge gallery-quality piece, **no text/captions/watermarks/
  signatures, no borders/mats/picture frames/screens/room mockups**.
  **Never mention TVs or "hanging" in the prompt** — told the art was "for a
  Frame TV", the model sometimes painted the TV itself, bezel and stand
  included.
- Gemini image model (`gemini-2.5-flash-image` at time of writing),
  `responseModalities: ["TEXT", "IMAGE"]` (IMAGE alone is rejected),
  `imageConfig: {aspectRatio: "16:9", imageSize: "2K"}` — and retry once
  without `imageSize` if the model version rejects it.
- Post-process every result: center-crop to exactly 16:9 if needed and
  resize to **3840×2160** (Lanczos), JPEG quality ~92.
- When no image comes back, surface the model's text (usually a safety
  explanation) so the user knows to rephrase — don't show a generic error.

### 4.4 Library

- Grid of everything ever generated or cropped, newest first. Full-size JPEG
  + small thumbnail (~480×270) per item, plus metadata: kind
  (`generated` | `photo`), prompt (for generated), created date, and the
  hang history (which TV, when, and the `content_id` the TV assigned).
- Actions: re-hang on any TV, view full screen, share/export, delete
  (deleting from the library never deletes from a TV — separate concerns,
  as in the parent project).
- Storage: JPEGs in the app's Documents (or App Group container if a share
  extension comes later), indexed by SwiftData. iCloud sync of the library
  is a nice-to-have for v1.x, not v1.

### 4.5 TV storage management

Port the **keep-10 pruning** policy: after each successful hang, keep only
the 10 most recent of *our* uploads on that TV and delete older ones from
the TV's internal storage — **only content_ids we recorded**, so Samsung's
store art and anything uploaded by other apps is untouchable. Drop the local
hang record even if the TV-side delete fails (TV asleep, already removed by
hand) so dead entries don't pin forever. Make the limit user-configurable in
settings (5–50, default 10).

## 5. What Frame Painter is NOT (v1 scope cut)

The parent project's voice remote, natural-language agent, Apple TV
deep-linking, HomePod relay, and general TV remote control are **out of
scope**. Frame Painter does art, and does it beautifully. (A tasteful
"switch to Art Mode / back to TV" toggle per TV is in scope — it's one
KEY_POWER tap and completes the experience.)

## 6. Architecture: on-device TV control

No server. The app implements the Samsung local API natively in Swift.
The reference implementation is Python
([`samsungtvws`](https://github.com/xchwarze/samsung-tv-ws-api)) plus this
repo's `src/tv_controller/tv.py` and `discovery.py`. Structure the port as a
standalone Swift package (`FrameKit`) so it's testable and reusable.

### 6.1 Discovery

Two-tier strategy, because **iOS restricts multicast**:

1. **Bonjour first** (`NWBrowser`): Frame TVs support AirPlay 2 and
   advertise `_airplay._tcp` (and often `_googlecast._tcp`). Browsing
   specific Bonjour service types does **not** require the multicast
   entitlement. Resolve each result to an IP, then confirm it's a Samsung TV
   via the device-info endpoint below.
2. **SSDP fallback** (what the parent project uses): M-SEARCH to
   `239.255.255.250:1900` with search targets
   `urn:samsung.com:device:RemoteControlReceiver:1` and
   `urn:schemas-upnp-org:device:MediaRenderer:1`, keep responders whose
   reply contains "Samsung". **This requires the
   `com.apple.developer.networking.multicast` entitlement, granted by
   application to Apple** — apply early (developer.apple.com → entitlement
   request), it can take weeks. Ship v1 with Bonjour + manual IP if the
   grant hasn't landed.

Whatever found the host, fetch `http://<ip>:8001/api/v2/` (no auth needed)
and read `device.name` (strip `[TV] `), `device.modelName`,
`device.wifiMac` (for wake-on-LAN), `device.FrameTVSupport` ("true" for
Frames), `device.TokenAuthSupport`, and `device.PowerState`.

### 6.2 Connection & authentication

- Remote channel: `wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<base64 app name>&token=<token>`
  (self-signed cert — the URLSession/Network.framework TLS delegate must
  accept it for these local connections only; port 8001 is the legacy
  unencrypted variant for pre-2016 sets, out of scope for v1).
- First connect without a token triggers the TV's **Allow prompt**; the
  `ms.channel.connect` event delivers the token on acceptance. Persist it in
  the **Keychain** keyed by TV id (use the MAC, not the IP).
- Socket lifecycle lessons (from `tv.py`, keep these semantics):
  - TVs drop idle sockets **without a FIN you'll notice**; the first write
    to a half-dead socket "succeeds" and vanishes. Don't reuse a connection
    idle for more than ~60s — reconnect instead.
  - On `BrokenPipe`/`ConnectionReset`-class errors: reconnect and **resend**.
    On a **timeout: do NOT resend** — the key may have been delivered, and a
    double KEY_POWER toggles Art Mode twice.
- Power semantics on Frames (subtle, port exactly):
  - A Frame in Art Mode still reports `PowerState: "on"` — the art channel's
    `get_artmode` is the only way to distinguish "showing art" from
    "showing TV". Newer firmware sometimes **never answers** this request:
    run it with a hard 4s abandon-the-task timeout and treat no-answer as
    unknown (and drop the socket — the abandoned read owns it).
  - KEY_POWER **tap** toggles Art Mode ↔ TV; a **3s hold** (or discrete
    `KEY_POWEROFF`) fully powers down. Verify power-down actually happened
    by polling device info; some firmware ignores the synthetic hold.
  - Wake a sleeping Frame with a **wake-on-LAN magic packet** to its MAC,
    then poll device info (up to ~10s) before attempting any upload.

### 6.3 Art Mode upload

The art channel is a second WebSocket
(`wss://<ip>:8002/api/v2/channels/com.samsung.art-app`) speaking
`d2d_service_message` JSON envelopes; the image bytes themselves go over a
**separate raw TCP socket** the TV opens for the transfer (the
`samsungtvws` `art()` module is the line-by-line reference — port
`upload`, `select_image`, `delete`/`delete_list`, `get_artmode`).
Non-negotiable settings proven on real hardware:

- Upload **JPEG, 3840×2160 exactly, `matte: "none"`**. Anything much
  smaller than the panel gets auto-matted by the TV — a bezel around the
  art instead of edge-to-edge.
- After upload, call select on the returned `content_id` so the new piece
  actually shows; **record the content_id** in the library for pruning.
- Before uploading: wake the TV if asleep (§6.2), and hard-refuse non-Frame
  TVs with a clear message.

### 6.4 Smart crop

Port `ios/TVRemote/SmartCropper.swift` from the parent repo **unchanged** as
the starting point: normalize orientation → compute the 16:9 window →
`VNGenerateAttentionBasedSaliencyImageRequest` → union all salient boxes →
slide the window along the long axis to cover them (clamped; oversize
regions stay centered) → downscale to fit 3840×2160 → JPEG 0.9. Note the
coordinate trap it already solves: Vision rects are normalized with a
**bottom-left** origin; CGImage cropping is top-left.

New for Frame Painter: the saliency crop pre-positions an **interactive**
crop view (drag to adjust, subtle grid overlay), so the user always gets the
final say.

### 6.5 App structure (suggested)

```
FramePainter/
  FrameKit/                    # Swift package: all TV protocol code, no UI
    Discovery/    (NWBrowser + SSDP + device-info client)
    Remote/       (WebSocket remote channel, tokens, keys, WoL)
    Art/          (art channel: upload, select, delete, get_artmode)
  App/
    Onboarding/   (scan, approve, TV list)
    Studio/       (AI generation UI — port of ArtStudioSheet)
    Photos/       (picker + crop UI — port of ArtworkSheet + SmartCropper)
    Library/      (grid, detail, re-hang — port of LibrarySheet, SwiftData)
    Settings/     (TVs, keep-N pruning, AI credits/key, help)
  Server/         (only if the proxy in §7 is chosen: a tiny cloud function)
```

SwiftUI, iOS 17+, Swift 5.10+, Network.framework for sockets, Vision,
PhotosUI, SwiftData. No third-party dependencies in FrameKit if avoidable.

## 7. The AI backend decision (needs a choice early)

The parent project calls Gemini from the Mac with the owner's API key. A
public app **cannot ship an embedded API key**. Options:

1. **Recommended: tiny proxy + IAP.** A minimal cloud endpoint (Cloudflare
   Worker / Firebase Function) that holds the Gemini key, validates an App
   Store receipt / App Attest, applies per-user rate limits, and forwards
   the generation request. Monetize as a small subscription or credit pack
   ("Frame Painter Pro") to cover inference costs; photo path stays free
   forever. This is the only sustainable public-scale option.
2. **BYO key (good v1 stopgap / power-user setting):** the user pastes their
   own Gemini API key (stored in Keychain, calls go direct from the phone).
   Zero server cost, App Store-legal, but mainstream users won't do it.

Shipping both is reasonable: BYO key unlocks unlimited generation; the proxy
serves everyone else. Keep the client-side generation code
transport-agnostic so the two paths share everything but the URL and auth.

## 8. App Store checklist

- **Info.plist:** `NSLocalNetworkUsageDescription` ("Frame Painter finds and
  talks to your Samsung Frame TVs on your home network"),
  `NSBonjourServices` (`_airplay._tcp`, `_googlecast._tcp`),
  `NSPhotoLibraryUsageDescription` (or use the out-of-process PhotosPicker,
  which needs no permission at all — prefer that).
- **ATS:** the TV's REST endpoint is plain `http://<ip>:8001` and the
  WebSocket is `wss` with a self-signed cert. Scope exceptions as narrowly
  as possible; raw IPs can't get per-domain exceptions, so document the
  chosen approach (`NSAllowsArbitraryLoads` with a review-notes
  justification, or move device info to a raw socket implementation).
  Parent-repo gotcha: don't set `NSAllowsLocalNetworking` **alongside**
  `NSAllowsArbitraryLoads` — the granular key makes iOS ignore the broad one.
- **Multicast entitlement** application for SSDP (§6.1) — start it week 1.
- **Review notes:** reviewers won't have a Frame TV. Provide a demo video of
  scan→approve→hang, and make the app degrade gracefully with zero TVs found
  (the library and AI studio still work — generate and save without a TV).
- **Trademark care:** "Samsung" and "The Frame" only descriptively ("works
  with Samsung Frame TVs"), never in the app name or icon; include a "not
  affiliated with Samsung" line in the description and About screen.
- Free Apple ID sideloading notes from the parent repo don't apply — this
  ships through a paid developer account, TestFlight beta first.

## 9. Hard-won gotchas index (do not relearn these)

All discovered on real hardware in the parent project; grep the referenced
file in [samsung-tv-controller](https://github.com/xavierbach/samsung-tv-controller)
for context:

| Gotcha | Reference |
|---|---|
| Idle TV sockets die silently; first write "succeeds" into the void | `tv.py` (`CONNECTION_MAX_IDLE`) |
| Reconnect+resend on dead-socket errors, never on timeout (double-toggle risk) | `tv.py` (`DEAD_SOCKET_ERRORS`) |
| Frame in Art Mode reports PowerState "on"; art channel disambiguates | `tv.py` (`_art_mode_on`) |
| Newer firmware never answers `get_artmode` / app-list — abandonable tasks with timeouts, then drop the socket | `tv.py` |
| Allow prompt needs ~30s timeout or the connection dies un-tokened and every command re-prompts | `tv.py` (`_connect`) |
| KEY_POWER tap = Art Mode toggle on Frames; 3s hold or KEY_POWEROFF = real off; verify, don't trust | `tv.py` (`power_off_hard`) |
| Upload at exactly 3840×2160 with `matte: "none"` or the TV mats the art | `imagegen.py`, `tv.py` (`set_artwork`) |
| Wake a sleeping Frame (WoL + poll) before judging or uploading anything | `tv.py` (`set_artwork`) |
| Never mention TVs/hanging in the image-gen prompt (model paints the TV) | `imagegen.py` (`FRAME_PROMPT`) |
| Gemini: TEXT+IMAGE modalities required; retry without `imageSize` on rejection; surface model text when no image returns | `imagegen.py` |
| Vision saliency rects are bottom-left-origin normalized; CGImage crops top-left | `SmartCropper.swift` |
| Prune only *our* recorded content_ids; store art is sacred; drop records even when TV-side delete fails | `library.py` (`record_hang`) |
| Strip Samsung's `[TV] ` name prefix; merge re-scans by name, keep existing MAC/port | `discovery.py`, `tv.py` (`discover_and_save`) |

## 10. Milestones

- **M0 — FrameKit spike (the risk burner):** Swift package proving the full
  direct-to-TV chain on real hardware: discover → token handshake w/ Allow
  prompt → art upload → select → delete. No UI beyond a test harness.
  *Everything else in this project is conventional iOS work; this is the
  part that can kill it, so it goes first.*
- **M1 — Photo path end-to-end:** onboarding scan/approve UI, photo pick,
  smart crop with manual adjust, hang on TV, library persistence. This is a
  usable app.
- **M2 — AI studio:** generation UI (port ArtStudioSheet UX), BYO-key path
  first, preview, hang, library integration.
- **M3 — Proxy + monetization:** cloud function, App Attest, IAP
  ("Frame Painter Pro"), rate limiting.
- **M4 — Polish & ship:** empty states, error taxonomy (TV asleep / wrong
  network / declined prompt / not a Frame), troubleshooting page, App Store
  assets, demo video for review, TestFlight beta → release.

## 11. Success criteria for v1

- Cold start to first artwork hung: **under 2 minutes** on a network with
  one Frame TV.
- Photo path works with **zero accounts, zero servers, zero configuration**.
- A hang succeeds on a Frame that was asleep in Art Mode when the user
  tapped the button.
- No data leaves the phone except the AI generation request.
