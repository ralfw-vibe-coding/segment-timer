#!/bin/zsh
# Baut "Segment Timer.app" ohne Xcode-Projekt – nur mit Swift Package Manager.
#   ./build.sh           → build/Segment Timer.app
#   ./build.sh install   → zusätzlich nach ~/Applications kopieren und starten
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Segment Timer"
BUNDLE_ID="local.segmenttimer"
VERSION="1.0"
APP="build/$APP_NAME.app"

echo "▸ Kompiliere (release) …"
swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null || swift build -c release --show-bin-path)/SegmentTimer"

echo "▸ Erzeuge App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SegmentTimer"

if [[ ! -f build/AppIcon.icns ]]; then
  echo "▸ Erzeuge Icon …"
  ICONSET="build/AppIcon.iconset"
  mkdir -p "$ICONSET"
  swift scripts/make-icon.swift build/icon_1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
  rm -rf "$ICONSET" build/icon_1024.png
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>SegmentTimer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "▸ Signiere (ad hoc) …"
codesign --force --deep --sign - "$APP" >/dev/null

echo "✓ Fertig: $APP"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -x SegmentTimer 2>/dev/null || true
  rm -rf ~/Applications/"$APP_NAME.app"
  cp -R "$APP" ~/Applications/
  echo "✓ Installiert: ~/Applications/$APP_NAME.app"
  open ~/Applications/"$APP_NAME.app"
fi
