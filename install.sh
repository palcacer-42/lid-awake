#!/bin/zsh
# Install Lid Awake: CLI + app + passwordless sudoers rule.
# Re-run safe. Needs sudo once (for the sudoers rule).
set -e
HERE="${0:A:h}"
USER_NAME="$(whoami)"

echo "==> 1/3  Installing CLI to ~/.local/bin/lid-toggle"
mkdir -p "$HOME/.local/bin"
install -m 755 "$HERE/lid-toggle" "$HOME/.local/bin/lid-toggle"

echo "==> 2/3  Installing sudoers rule (needs your password once)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$tmp"
sudo install -m 440 -o root -g wheel "$tmp" /etc/sudoers.d/lid-toggle
sudo visudo -c

echo "==> 3/3  Building and installing the app"
"$HERE/build.sh" --install

echo
echo "Done."
echo "  - App:  ~/Applications/Lid Awake.app"
echo "  - CLI:  lid-toggle [on|off|status|toggle]   (ensure ~/.local/bin is on PATH)"
echo
echo "Open the app once to allow it, then flip the toggle."
