#!/bin/zsh
# make-icon.sh — build AppIcon.icns for "Lid Awake" from scratch.
#
#   ./make-icon.sh          # writes ./AppIcon.icns
#   ./make-icon.sh --install  # also copy into ~/Applications/Lid Awake.app
#
# Needs Xcode Command Line Tools (swiftc) and iconutil (built into macOS).
set -e
HERE="${0:A:h}"
OUT="$HERE/AppIcon.icns"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

swiftc -O -o "$tmp/make_icon" "$HERE/tools/make_icon.swift" -framework AppKit
"$tmp/make_icon" "$tmp/png"

iconset="$tmp/AppIcon.iconset"
mkdir -p "$iconset"
cp "$tmp/png/icon_16.png"   "$iconset/icon_16x16.png"
cp "$tmp/png/icon_32.png"   "$iconset/icon_16x16@2x.png"
cp "$tmp/png/icon_32.png"   "$iconset/icon_32x32.png"
cp "$tmp/png/icon_64.png"   "$iconset/icon_32x32@2x.png"
cp "$tmp/png/icon_128.png"  "$iconset/icon_128x128.png"
cp "$tmp/png/icon_256.png"  "$iconset/icon_128x128@2x.png"
cp "$tmp/png/icon_256.png"  "$iconset/icon_256x256.png"
cp "$tmp/png/icon_512.png"  "$iconset/icon_256x256@2x.png"
cp "$tmp/png/icon_512.png"  "$iconset/icon_512x512.png"
cp "$tmp/png/icon_1024.png" "$iconset/icon_512x512@2x.png"

iconutil -c icns "$iconset" -o "$OUT"
echo "built: $OUT"

if [[ "${1:-}" == "--install" ]]; then
  APP="$HOME/Applications/Lid Awake.app"
  if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found; run ./build.sh --install first" >&2
    exit 1
  fi
  mkdir -p "$APP/Contents/Resources"
  cp "$OUT" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  touch "$APP"
  echo "installed icon into: $APP"
fi
