# TVRemote — the iPhone & iPad app

A universal SwiftUI app: hold the circle, speak, release — the TVs react.
Speech-to-text runs **on-device** (`SFSpeechRecognizer` with
`requiresOnDeviceRecognition`), so the transcript is ready the moment your
thumb lifts and the only network hop is one small POST to the Mac.

## Build it (one-time Xcode setup)

The Swift sources live in `TVRemote/`. Xcode project files don't belong in
git-diff-land, so create the project shell yourself:

1. Xcode → **File → New → Project → iOS App**
   - Product name: `TVRemote`, Interface: SwiftUI, Language: Swift
   - Save it anywhere (e.g. this `ios/` folder — Xcode makes `TVRemote.xcodeproj`)
2. Delete the generated `ContentView.swift` / `TVRemoteApp.swift`, then drag
   the four files from this repo's `TVRemote/` folder into the project
   (check "Copy items if needed" **off** so git stays the source of truth).
3. In the target's **Info** tab, add these keys:

   | Key | Value |
   |---|---|
   | `NSMicrophoneUsageDescription` | "Hold-to-talk uses the microphone." |
   | `NSSpeechRecognitionUsageDescription` | "Your commands are transcribed on this device." |
   | `NSLocalNetworkUsageDescription` | "Talks to the TV server on your home network." |
   | `App Transport Security Settings` → `NSAllowsLocalNetworking` | `YES` (the server is plain http on your LAN) |

4. **Signing & Capabilities** → set your Team (your Apple ID) and a unique
   bundle ID like `com.yourname.tvremote`.
5. Select your iPhone as the run target and hit **Run**. First launch on
   device: Settings → General → VPN & Device Management → trust your
   developer certificate.

Repeat step 5 with the iPad selected — same app, the grid adapts.

## Point it at the Mac

Open the app's settings (gear icon) and set the server URL —
`http://<your-macbook-name>.local:8765` (find the name in macOS System
Settings → General → Sharing → Local hostname), or the Mac's IP.

## Sideloading refresher

- **Free Apple ID:** builds expire after 7 days; re-run from Xcode weekly,
  or use AltStore to auto-refresh. Max 3 sideloaded apps.
- **Paid developer account ($99/yr):** certificates last a year, and you can
  distribute to your own devices via TestFlight (90-day builds).

## First-launch permissions

You'll get three prompts: microphone, speech recognition, and local network.
Allow all three — deny any one and the app can't do its job.
