# HomePod voice control

Two layers, use both:

## 1. Free-form commands via a Siri Shortcut (works today)

HomePods relay Siri Shortcuts through your iPhone, so any HomePod in the
house can drive the server. Build this once in the **Shortcuts** app on your
iPhone:

1. New shortcut, name it **TV** (the name is what you'll say).
2. Add action **Dictate Text**.
3. Add action **Get Contents of URL**:
   - URL: `http://<your-mac-ip>:8765/command` — use the Mac's IP rather than
     a `.local` name (HomePod relays resolve mDNS unreliably), and use the
     port the server actually runs on (`TVCTL_PORT`; this house runs 8766)
   - Method: **POST**, Request Body: **JSON**
   - Add field: `text` = *Dictated Text* (the magic variable from step 2)
   - Add field: `source` = `homepod`
4. Add action **Get Dictionary Value** → key `reply` (from *Contents of URL*).
5. Add action **Speak Text** → *Dictionary Value*.

Then, anywhere in the house:

> **"Hey Siri, TV"** → *"What would you like?"* → **"I want to watch ABC News in the dining room"**

Siri speaks the server's one-line confirmation back through the HomePod.

### Room awareness

Shortcuts don't know which HomePod heard you, so either name the room in the
sentence, or duplicate the shortcut per room with the room baked in:
copy it, rename to **Dining TV**, and add `room` = `dining-room` as a third
JSON field. Then *"Hey Siri, Dining TV"* → *"pause"* just works.

### Notes

- Personal-request relay requires your iPhone to be on the home network
  (it will be — you're standing in the house).
- In the Home app, make sure **Personal Requests** are enabled for your
  HomePods (Home Settings → your profile → Personal Requests).

## 2. Native Siri once the Apple TVs arrive

With an Apple TV paired in a room and assigned to that room in the Home app,
some commands stop needing the shortcut at all — *"Hey Siri, pause the
dining room"* and AirPlay-style *"play X on the dining room Apple TV"* are
native and room-aware. Keep the shortcut for the smart stuff (content
resolution, multi-TV commands, anything with judgment) — Siri handles the
reflexes, the shortcut handles the brain.
