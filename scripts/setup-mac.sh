#!/bin/bash
# One-paste setup for the always-on Mac. Run in Terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/xavierbach/Samsung-tv-controller/main/scripts/setup-mac.sh | bash
#
# Or clone the repo and run ./scripts/setup-mac.sh
# Idempotent: safe to re-run.

set -euo pipefail

REPO="https://github.com/xavierbach/Samsung-tv-controller"
DIR="$HOME/samsung-tv-controller"
CONFIG_DIR="$HOME/.config/samsung-tv-controller"
ENV_FILE="$CONFIG_DIR/env"

echo "== Samsung TV super controller: Mac setup =="

# 1. Python 3.10+ (auto-installs via Homebrew if missing)
find_python() {
    PY=""
    for cand in python3.13 python3.12 python3.11 python3.10 python3 \
                /opt/homebrew/bin/python3.12 /usr/local/bin/python3.12; do
        if command -v "$cand" >/dev/null 2>&1 && \
           "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
            PY="$(command -v "$cand")"
            return 0
        fi
    done
    return 1
}
if ! find_python; then
    echo "Python 3.10+ not found — installing it via Homebrew..."
    BREW=""
    for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$cand" ] && BREW="$cand" && break
    done
    if [ -z "$BREW" ]; then
        echo "Installing Homebrew first (it will ask for your Mac password —"
        echo "typing is invisible, that's normal)..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            [ -x "$cand" ] && BREW="$cand" && break
        done
    fi
    eval "$("$BREW" shellenv)"
    brew install python@3.12
    find_python || { echo "Python install failed — see messages above." >&2; exit 1; }
fi
echo "Using $PY"

# 2. Get the code
if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull --ff-only
else
    git clone "$REPO" "$DIR"
fi

# 3. Virtualenv + install (with Apple TV support)
"$PY" -m venv "$DIR/.venv"
"$DIR/.venv/bin/pip" install --quiet --upgrade pip
(cd "$DIR" && .venv/bin/pip install --quiet -e ".[appletv]")
TVCTL="$DIR/.venv/bin/tvctl"
echo "Installed: $TVCTL"

# 4. API key
mkdir -p "$CONFIG_DIR"
if ! grep -q '^ANTHROPIC_API_KEY=' "$ENV_FILE" 2>/dev/null; then
    if [ -t 0 ]; then
        read -r -s -p "Paste your Anthropic API key (sk-ant-...): " KEY; echo
        printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"
    else
        echo "NOTE: no TTY — put your key in $ENV_FILE as ANTHROPIC_API_KEY=sk-ant-..."
    fi
fi

# 5. Find the TVs
echo
echo "== Scanning for Samsung TVs (make sure they're on) =="
"$TVCTL" discover --save || true
echo
echo "== Scanning for Apple TVs =="
"$TVCTL" atv-scan || true

# 6. Install the server as a launchd agent
export PATH="$DIR/.venv/bin:$PATH"
"$DIR/scripts/install-macos-server.sh"

echo
echo "== Done. Next steps =="
echo "1. Pair each Apple TV to its room (PIN appears on the TV):"
echo "       $TVCTL atv-pair <tv-name> <apple-tv-ip>"
echo "2. Send the first command to each Samsung TV and accept the on-screen prompt:"
echo "       $TVCTL do \"which tvs are on?\""
echo "3. Test the magic:"
echo "       $TVCTL do \"play the latest ABC News Victoria bulletin in the gym\""
echo "4. Keep the Mac awake: System Settings > Energy > prevent sleeping."
