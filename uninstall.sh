#!/bin/zsh
# Remove everything install.sh added.
set -u
echo "==> Turning lid-awake off"
"$HOME/.local/bin/lid-toggle" off 2>/dev/null || true

echo "==> Quitting the app"
osascript -e 'quit app "Lid Awake"' 2>/dev/null || true
pkill -f "Lid Awake.app/Contents/MacOS/LidAwake" 2>/dev/null || true

echo "==> Removing login item (if enabled)"
rm -f "$HOME/Library/LaunchAgents/com.lidawake.login.plist"
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.lidawake.login.plist" 2>/dev/null || true

echo "==> Removing app and CLI"
rm -rf "$HOME/Applications/Lid Awake.app"
rm -f "$HOME/.local/bin/lid-toggle"

echo "==> Removing sudoers rule (needs sudo)"
sudo rm -f /etc/sudoers.d/lid-toggle

echo "Done. The Mac is back to normal sleep-on-lid-close."
