#!/bin/bash
# Build a SELF-CONTAINED, shareable Viska.app + Viska.dmg into ./dist
# (engine + dylibs bundled inside the .app). The KB-Whisper model is not
# bundled: the app downloads it on first launch, with a progress window.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

DIST="$HERE/dist"
APP="$DIST/Viska.app"
C="$APP/Contents"

echo "==> clean dist"
rm -rf "$APP" "$DIST/Viska.dmg"
mkdir -p "$C/MacOS" "$C/Resources/bin" "$C/Resources/lib"

echo "==> compile Swift app"
swiftc -O app/core/*.swift app/ui/*.swift -o "$C/MacOS/Viska" \
  -framework Cocoa -framework AVFoundation \
  -framework ApplicationServices -framework CoreGraphics

echo "==> Info.plist + icon"
cp assets/Viska.icns "$C/Resources/Viska.icns"
cat > "$C/Info.plist" <<'PLIST'
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

echo "==> bundle engine (whisper-server, whisper-cli + dylibs)"
cp whisper.cpp/build/bin/whisper-cli whisper.cpp/build/bin/whisper-server "$C/Resources/bin/"
cp -a whisper.cpp/build/bin/*.dylib "$C/Resources/lib/"

echo "==> rewire dylib search path to inside the app"
for b in whisper-cli whisper-server; do
  install_name_tool -delete_rpath "$HERE/whisper.cpp/build/bin" "$C/Resources/bin/$b" 2>/dev/null || true
  install_name_tool -add_rpath "@executable_path/../lib" "$C/Resources/bin/$b"
done

echo "==> ad-hoc sign (nested code included)"
codesign --force --deep --sign - "$APP"

echo "==> verify bundled engine resolves its libraries"
"$C/Resources/bin/whisper-server" --help >/dev/null 2>&1 || echo "    (varning: whisper-server startar inte)"

echo "==> build Viska.dmg (drag-to-Applications)"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Viska" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Viska.dmg" >/dev/null
rm -rf "$STAGE"

echo ""
echo "==> KLART"
echo "    App:  $APP"
echo "    DMG:  $DIST/Viska.dmg  ($(du -h "$DIST/Viska.dmg" | awk '{print $1}'))"
