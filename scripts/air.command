#!/bin/bash
# ============================================================
#  AIR — run this on the MacBook AIR (builds the iPhone app).
#
#  Double-click to run. If macOS blocks it ("unidentified
#  developer"), right-click the file > Open > Open.
#  Or run it from Terminal:  bash ~/Downloads/air.command
#
#  Prerequisite: Xcode from the App Store (free, big download).
# ============================================================
set -euo pipefail
clear
echo "=================================================="
echo "  TV super controller — AIR (app build) setup"
echo "=================================================="
echo

# Full Xcode is required to build for iPhone
if [ ! -d "/Applications/Xcode.app" ]; then
    echo "Xcode isn't installed yet."
    echo "  1. Install Xcode from the App Store (free)."
    echo "  2. Open it once and accept the license."
    echo "  3. Double-click this file again."
    read -r -p "Press Enter to close..." _
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Installing Apple's command-line tools (dialog will pop up)."
    echo "When it finishes, double-click this file again."
    xcode-select --install || true
    read -r -p "Press Enter to close..." _
    exit 0
fi

REPO="https://github.com/xavierbach/Samsung-tv-controller"
DIR="$HOME/samsung-tv-controller"

if [ -d "$DIR/.git" ]; then
    echo "Updating existing checkout..."
    git -C "$DIR" pull --ff-only
else
    echo "Downloading the TV controller..."
    git clone "$REPO" "$DIR"
fi

# Homebrew (for XcodeGen). Handles Apple Silicon and Intel paths.
BREW=""
for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$cand" ] && BREW="$cand" && break
done
if [ -z "$BREW" ]; then
    echo "Installing Homebrew (you'll be asked for your Mac password)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$cand" ] && BREW="$cand" && break
    done
fi
eval "$("$BREW" shellenv)"

echo "Installing XcodeGen..."
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen

echo "Generating the Xcode project..."
cd "$DIR/ios"
xcodegen generate
open TVRemote.xcodeproj

echo
echo "=================================================="
echo "  Xcode is opening. Final steps (one-time, ~2 min):"
echo "=================================================="
echo "  1. Plug your iPhone into this Mac with a cable"
echo "     (tap 'Trust' on the phone if asked)."
echo "  2. In Xcode, click the TVRemote project (blue icon, left sidebar)"
echo "     > Signing & Capabilities > Team > add/select your Apple ID."
echo "  3. In the toolbar device menu, pick your iPhone."
echo "  4. Press the Play button. First run only: on the iPhone go to"
echo "     Settings > General > VPN & Device Management > trust your cert."
echo "  5. In the app, tap the gear and set the server address to your"
echo "     Pro, e.g.  http://<pro-name>.local:8765"
echo
echo "  Repeat steps 3-4 with your iPad selected to install it there too."
read -r -p "Press Enter to close..." _
