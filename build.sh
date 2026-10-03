#!/bin/zsh
# Build "Lid Awake.app" from main.swift.
#
#   ./build.sh              build to ./dist/Lid Awake.app
#   ./build.sh --install    build and copy to ~/Applications
#
# Produces a universal (arm64 + x86_64) binary when possible; falls back to a
# native-only build. Requires Xcode Command Line Tools (check: xcode-select -p)
set -e
HERE="${0:A:h}"
DIST="$HERE/dist"
APP="$DIST/Lid Awake.app"
VERSION="2.2.0"
MIN_MACOS="13.0"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

build_universal() {
  swiftc -O -target "arm64-apple-macosx$MIN_MACOS"   -o "$tmp/arm64"  "$HERE/main.swift" -framework AppKit -framework IOKit 2>/dev/null || return 1
  swiftc -O -target "x86_64-apple-macosx$MIN_MACOS"  -o "$tmp/x86_64" "$HERE/main.swift" -framework AppKit -framework IOKit 2>/dev/null || return 1
  lipo -create "$tmp/arm64" "$tmp/x86_64" -output "$tmp/LidAwake" || return 1
}

if build_universal; then
  echo "built universal binary (arm64 + x86_64)"
else
  echo "universal build unavailable, building native only"
  swiftc -O -o "$tmp/LidAwake" "$HERE/main.swift" -framework AppKit -framework IOKit
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$tmp/LidAwake" "$APP/Contents/MacOS/LidAwake"

# App icon: build once if missing, then bundle it.
if [[ ! -f "$HERE/AppIcon.icns" ]]; then
  "$HERE/make-icon.sh" >/dev/null 2>&1 || echo "warning: icon generation failed (continuing)" >&2
fi
if [[ -f "$HERE/AppIcon.icns" ]]; then
  mkdir -p "$APP/Contents/Resources"
  cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lid Awake</string>
  <key>CFBundleDisplayName</key><string>Lid Awake</string>
  <key>CFBundleIdentifier</key><string>com.lidawake.app</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>LidAwake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
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
