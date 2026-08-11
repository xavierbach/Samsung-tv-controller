#!/bin/bash
# ============================================================
#  AIR — run this on the MacBook AIR (builds the iPhone app).
#
#  EASIEST WAY TO RUN (avoids macOS security blocks):
#    1. Open Terminal (Cmd+Space, type Terminal)
#    2. Type:  bash
#       then a SPACE, then drag this file into the window
#    3. Press Enter
#
#  Prerequisite: Xcode from the App Store (free, big download).
#  Everything is logged to  ~/Desktop/tv-setup-air.log
# ============================================================
set -euo pipefail

LOG="$HOME/Desktop/tv-setup-air.log"
exec > >(tee -a "$LOG") 2>&1

on_fail() {
    code=$?
    echo
    echo "**************************************************"
    echo "***  SOMETHING FAILED (exit code $code)"
    echo "***  The full log is on your Desktop:"
    echo "***      tv-setup-air.log"
    echo "***  Send that file (or a photo of this window)"
    echo "***  back to Claude and I'll fix it."
    echo "**************************************************"
    read -r -p "Press Enter to close..." _ || true
}
trap on_fail ERR

clear
echo "=================================================="
echo "  TV super controller — AIR (app build) setup"
echo "  $(date)"
echo "=================================================="
echo

echo "[1/5] Checking for Xcode..."
if [ ! -d "/Applications/Xcode.app" ]; then
    echo "      Xcode isn't installed yet. To fix:"
    echo "        1. Open the App Store, search 'Xcode', install (free)."
    echo "        2. Open Xcode once and accept the license."
    echo "        3. Run this file again."
    read -r -p "Press Enter to close..." _
    exit 0
fi
echo "      OK"

echo "[2/5] Checking Apple command-line tools..."
if ! xcode-select -p >/dev/null 2>&1; then
    echo "      Installing (a dialog will pop up — click Install),"
    echo "      then run this file again."
    xcode-select --install || true
    read -r -p "Press Enter to close..." _
    exit 0
fi
echo "      OK"

echo "[3/5] Getting the TV controller code..."
REPO="https://github.com/xavierbach/Samsung-tv-controller"
DIR="$HOME/samsung-tv-controller"
if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull --ff-only
else
    git clone "$REPO" "$DIR"
fi
echo "      OK — $DIR"

echo "[4/5] Setting up Homebrew + XcodeGen..."
BREW=""
for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$cand" ] && BREW="$cand" && break
done
if [ -z "$BREW" ]; then
    echo "      Installing Homebrew (it will ask for your Mac password —"
    echo "      typing is invisible, that's normal)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$cand" ] && BREW="$cand" && break
    done
fi
eval "$("$BREW" shellenv)"
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
echo "      OK"

echo "[5/5] Generating and opening the Xcode project..."
cd "$DIR/ios"
xcodegen generate
open TVRemote.xcodeproj
echo "      OK"

echo
echo "=================================================="
echo "  SUCCESS — Xcode is opening. Final steps (~2 min):"
echo "=================================================="
echo "  1. Plug your iPhone into this Mac with a cable"
echo "     (tap 'Trust' on the phone if asked)."
echo "  2. In Xcode's left sidebar click the blue 'TVRemote' icon"
echo "     > Signing & Capabilities > Team > add/select your Apple ID."
echo "  3. In the toolbar device menu (top centre), pick your iPhone."
echo "  4. Press the Play button. First run only: on the iPhone go to"
echo "     Settings > General > VPN & Device Management > trust the cert."
echo "  5. In the app, tap the gear and set the server address shown"
echo "     at the end of the PRO setup (http://....local:8765)."
echo
echo "  Repeat steps 3-4 with your iPad to install it there too."
read -r -p "Press Enter to close..." _
