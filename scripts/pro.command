#!/bin/bash
# ============================================================
#  PRO — run this on the always-on MacBook PRO (the server).
#
#  Double-click to run. If macOS blocks it ("unidentified
#  developer"), right-click the file > Open > Open.
#  Or run it from Terminal:  bash ~/Downloads/pro.command
# ============================================================
set -euo pipefail
clear
echo "=================================================="
echo "  TV super controller — PRO (server) setup"
echo "=================================================="
echo

# Apple's command-line tools provide git
if ! xcode-select -p >/dev/null 2>&1; then
    echo "First: installing Apple's command-line tools."
    echo "A dialog will pop up — click Install, wait for it to finish,"
    echo "then double-click this file again."
    xcode-select --install || true
    read -r -p "Press Enter to close..." _
    exit 0
fi

REPO="https://github.com/xavierbach/Samsung-tv-controller"
DIR="$HOME/samsung-tv-controller"

if [ -d "$DIR/.git" ]; then
    echo "Updating existing install..."
    git -C "$DIR" pull --ff-only
else
    echo "Downloading the TV controller..."
    git clone "$REPO" "$DIR"
fi

# The real work lives in the repo so it stays up to date
bash "$DIR/scripts/setup-mac.sh"

echo
echo "PRO setup finished. This Mac is now the house brain."
echo "Server check:  curl http://localhost:8765/health"
read -r -p "Press Enter to close..." _
