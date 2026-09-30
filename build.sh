#!/bin/zsh
# Build "Lid Awake.app" from main.swift into ./dist (and optionally install it).
#
#   ./build.sh              build to ./dist/Lid Awake.app
#   ./build.sh --install    build and copy to ~/Applications
#
# Requires Xcode Command Line Tools (swiftc). Check: xcode-select -p
set -e
HERE="${0:A:h}"
DIST="$HERE/dist"
APP="$DIST/Lid Awake.app"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

swiftc -O -o "$tmp/LidAwake" "$HERE/main.swift" -framework AppKit

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$tmp/LidAwake" "$APP/Contents/MacOS/LidAwake"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lid Awake</string>
  <key>CFBundleDisplayName</key><string>Lid Awake</string>
  <key>CFBundleIdentifier</key><string>com.lidawake.app</string>
  <key>CFBundleExecutable</key><string>LidAwake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>2.0</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><false/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Lid Awake.app"
  cp -R "$APP" "$HOME/Applications/Lid Awake.app"
  echo "installed: $HOME/Applications/Lid Awake.app"
fi
