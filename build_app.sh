#!/bin/bash
# Build Viska.app (a self-contained Swift menu bar app) into the project dir.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

APP="$HERE/Viska.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "==> compiling Swift app"
swiftc -O app/Viska.swift -o "$MACOS/Viska" \
  -framework Cocoa -framework AVFoundation \
  -framework ApplicationServices -framework CoreGraphics

echo "==> writing Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Viska</string>
  <key>CFBundleDisplayName</key>     <string>Viska</string>
  <key>CFBundleIdentifier</key>      <string>com.axel.viska</string>
  <key>CFBundleVersion</key>         <string>1.0</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleExecutable</key>      <string>Viska</string>
  <key>CFBundleIconFile</key>        <string>Viska</string>
  <key>LSMinimumSystemVersion</key>  <string>12.0</string>
  <key>LSUIElement</key>             <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Viska spelar in din röst för att transkribera den lokalt.</string>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "==> installing app icon"
if [ -f assets/Viska.icns ]; then
  cp assets/Viska.icns "$RES/Viska.icns"
else
  echo "    (assets/Viska.icns saknas — hoppar över ikon)"
fi

echo "==> ad-hoc code signing (stable TCC identity)"
codesign --force --deep --sign - "$APP" 2>/dev/null || \
  echo "    (codesign hoppades över — appen fungerar ändå)"

echo ""
echo "==> KLART: $APP"
echo "    Öppna med:  open '$APP'    (eller dubbelklicka i Finder)"
