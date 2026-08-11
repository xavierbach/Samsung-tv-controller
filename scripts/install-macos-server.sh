#!/bin/bash
# Install the TV controller server as a macOS launchd agent so it starts at
# login and restarts if it crashes. Run this once on the always-on Mac:
#
#     ./scripts/install-macos-server.sh
#
# Requires: the package installed (pip install -e ".[appletv]") and
# ANTHROPIC_API_KEY available. The key is read from your current shell or
# from ~/.config/samsung-tv-controller/env (KEY=value lines).

set -euo pipefail

LABEL="com.tvctl.server"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/tvctl"
CONFIG_DIR="$HOME/.config/samsung-tv-controller"
ENV_FILE="$CONFIG_DIR/env"

TVCTL="$(command -v tvctl || true)"
if [ -z "$TVCTL" ]; then
    echo "error: 'tvctl' not found on PATH. Install first: pip install -e '.[appletv]'" >&2
    exit 1
fi

API_KEY="${ANTHROPIC_API_KEY:-}"
if [ -z "$API_KEY" ] && [ -f "$ENV_FILE" ]; then
    API_KEY="$(sed -n 's/^ANTHROPIC_API_KEY=//p' "$ENV_FILE" | head -1)"
fi
if [ -z "$API_KEY" ]; then
    echo "error: ANTHROPIC_API_KEY not set and not found in $ENV_FILE" >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$CONFIG_DIR" "$(dirname "$PLIST")"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TVCTL</string>
        <string>serve</string>
        <string>--host</string><string>0.0.0.0</string>
        <string>--port</string><string>8765</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>ANTHROPIC_API_KEY</key><string>$API_KEY</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$LOG_DIR/server.log</string>
    <key>StandardErrorPath</key><string>$LOG_DIR/server.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "Installed and started. Check it:"
echo "    curl http://localhost:8765/health"
echo "Logs: $LOG_DIR/server.log"
echo
echo "Note: keep the Mac awake for the network — System Settings > Energy >"
echo "'Prevent automatic sleeping when the display is off', or: sudo pmset -a sleep 0"
