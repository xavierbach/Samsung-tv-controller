#!/bin/bash
# ============================================================
#  PRO — run this on the always-on MacBook PRO (the server).
#
#  EASIEST WAY TO RUN (avoids macOS security blocks):
#    1. Open Terminal (Cmd+Space, type Terminal)
#    2. Type:  bash
#       then a SPACE, then drag this file into the window
#    3. Press Enter
#
#  Everything is logged to  ~/Desktop/tv-setup-pro.log
# ============================================================
set -euo pipefail

LOG="$HOME/Desktop/tv-setup-pro.log"
exec > >(tee -a "$LOG") 2>&1

on_fail() {
    code=$?
    echo
    echo "**************************************************"
    echo "***  SOMETHING FAILED (exit code $code)"
    echo "***  The full log is on your Desktop:"
    echo "***      tv-setup-pro.log"
    echo "***  Send that file (or a photo of this window)"
    echo "***  back to Claude and I'll fix it."
    echo "**************************************************"
    read -r -p "Press Enter to close..." _ || true
}
trap on_fail ERR

clear
echo "=================================================="
echo "  TV super controller — PRO (server) setup"
echo "  $(date)"
echo "=================================================="
echo

echo "[1/4] Checking Apple command-line tools (for git)..."
if ! xcode-select -p >/dev/null 2>&1; then
    echo "      Not installed. A dialog will pop up — click Install."
    echo "      (If you don't see it, check behind other windows.)"
    xcode-select --install || true
    echo "      When that install finishes, run this file again."
    read -r -p "Press Enter to close..." _
    exit 0
fi
echo "      OK"

echo "[2/4] Getting the TV controller code..."
REPO="https://github.com/xavierbach/Samsung-tv-controller"
DIR="$HOME/samsung-tv-controller"
if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull --ff-only
else
    git clone "$REPO" "$DIR"
fi
echo "      OK — $DIR"

echo "[3/4] Running the main setup (Python, TVs, server)..."
bash "$DIR/scripts/setup-mac.sh"

echo "[4/4] Checking the server is alive..."
# The port the server was actually installed with (setup records it here).
PORT="$(sed -n 's/^TVCTL_PORT=//p' "$HOME/.config/samsung-tv-controller/env" 2>/dev/null | head -1 || true)"
PORT="${PORT:-8765}"
# Booting the venv + uvicorn takes a few seconds; poll rather than guess.
ALIVE=""
for _ in $(seq 1 20); do
    if curl -sf "http://localhost:$PORT/health" >/dev/null; then
        ALIVE=1
        break
    fi
    sleep 1
done
if [ -n "$ALIVE" ]; then
    echo "      OK — server is running on port $PORT"
else
    echo "      Server not answering on port $PORT after 20s — check the log at"
    echo "      ~/Library/Logs/tvctl/server.err.log"
fi

echo
echo "=================================================="
echo "  SUCCESS — this Mac is now the house brain."
echo "  Its address for the iPhone app:"
echo "      http://$(scutil --get LocalHostName 2>/dev/null || hostname).local:$PORT"
echo "=================================================="
read -r -p "Press Enter to close..." _
