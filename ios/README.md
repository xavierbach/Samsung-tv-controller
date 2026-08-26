# TVRemote — the iPhone & iPad app

A universal SwiftUI app: hold the circle, speak, release — the TVs react.
Speech-to-text runs **on-device** (`SFSpeechRecognizer` with
`requiresOnDeviceRecognition`), so the transcript is ready the moment your
thumb lifts and the only network hop is one small POST to the Mac.

There's also a picture-frame button next to the gear: pick any photo and it
becomes **Frame TV artwork**. The app crops it to 16:9 on-device using
Vision's attention-based saliency — the crop window slides to keep faces and
subjects in frame instead of blindly slicing the center — shows you the
result, asks which TV, and the server uploads it into Art Mode.

## Build it — fast path (XcodeGen)

```bash
brew install xcodegen
cd ios && xcodegen generate
open TVRemote.xcodeproj
```

`project.yml` carries all the Info.plist permission keys, so the only manual
step left is **Signing & Capabilities → set your Team**, pick your iPhone as
the destination, and Run. Skip to "Point it at the Mac" below.

## Build it — manual path (no XcodeGen)

The Swift sources live in `TVRemote/`. Create the project shell yourself:

1. Xcode → **File → New → Project → iOS App**
   - Product name: `TVRemote`, Interface: SwiftUI, Language: Swift
   - Save it anywhere (e.g. this `ios/` folder — Xcode makes `TVRemote.xcodeproj`)
2. Delete the generated `ContentView.swift` / `TVRemoteApp.swift`, then drag
   the Swift files from this repo's `TVRemote/` folder into the project
   (check "Copy items if needed" **off** so git stays the source of truth).
3. In the target's **Info** tab, add these keys:

   | Key | Value |
   |---|---|
   | `NSMicrophoneUsageDescription` | "Hold-to-talk uses the microphone." |
   | `NSSpeechRecognitionUsageDescription` | "Your commands are transcribed on this device." |
   | `NSLocalNetworkUsageDescription` | "Talks to the TV server on your home network." |
   | `App Transport Security Settings` → `NSAllowsArbitraryLoads` | `YES` — the server is plain http on a private network, and ATS blocks cleartext even to raw IP addresses (which can't be exempted individually). Don't add `NSAllowsLocalNetworking` alongside it: that granular key makes iOS ignore `NSAllowsArbitraryLoads`. |

4. **Signing & Capabilities** → set your Team (your Apple ID) and a unique
   bundle ID like `com.yourname.tvremote`.
5. Select your iPhone as the run target and hit **Run**. First launch on
   device: Settings → General → VPN & Device Management → trust your
   developer certificate.

Repeat step 5 with the iPad selected — same app, the grid adapts.

## Point it at the Mac

Open the app's settings (gear icon) and set the server URL —
`http://<your-macbook-name>.local:<port>` (find the name in macOS System
Settings → General → Sharing → Local hostname), or the Mac's IP. The PRO
setup script prints the exact address, port included, when it finishes.

**Away from home:** use the Mac's Tailscale IP or MagicDNS name with the
same port (e.g. `http://100.x.y.z:8766`), and make sure the Tailscale app
on the phone says **Connected** — iOS drops the tunnel in the background.
See the Tailscale troubleshooting section in the main README.

## Sideloading refresher

- **Free Apple ID:** builds expire after 7 days; re-run from Xcode weekly,
  or use AltStore to auto-refresh. Max 3 sideloaded apps.
- **Paid developer account ($99/yr):** certificates last a year, and you can
  distribute to your own devices via TestFlight (90-day builds).

## First-launch permissions

You'll get three prompts: microphone, speech recognition, and local network.
Allow all three — deny any one and the app can't do its job.
