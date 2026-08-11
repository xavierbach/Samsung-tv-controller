#!/bin/bash
# Grants Claude's session SSH access to this Mac:
#   1. installs Claude's public key (public info, safe to commit)
#   2. enables macOS Remote Login (asks for your Mac password)
#   3. prints what to tell Claude
# Run:  curl -sL <short-url> | bash
set -u

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKs8o8KzLk2xIdZS2LVcnQl4Wt8r9TAHR4j0/K2v/xfB claude-session'

echo "== Granting Claude SSH access to this Mac =="

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if ! grep -qF "$KEY" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    echo "$KEY" >> "$HOME/.ssh/authorized_keys"
fi
chmod 600 "$HOME/.ssh/authorized_keys"
echo "   SSH key installed."

echo "   Enabling Remote Login (type your Mac password when asked)..."
if sudo systemsetup -setremotelogin on >/dev/null 2>&1; then
    echo "   Remote Login: ON"
else
    echo "   Could not enable it automatically. Do it by mouse:"
    echo "   System Settings > General > Sharing > Remote Login: ON"
fi

echo
echo "=============== TELL CLAUDE THIS ==============="
echo "   machine: $(scutil --get LocalHostName 2>/dev/null || hostname)"
echo "   user:    $(whoami)"
echo "================================================"
