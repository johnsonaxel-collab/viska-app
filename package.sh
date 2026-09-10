#!/bin/bash
# Build a SELF-CONTAINED, shareable Viska.app + Viska.dmg into ./dist
# (engine + dylibs + model bundled inside the .app). Leaves the local
# ~/whisperflow/Viska.app untouched.
#
# Model to bundle: WF_MODEL (default ggml-small.bin — fast on modest Macs).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

MODEL_NAME="${WF_MODEL:-ggml-small.bin}"
DIST="$HERE/dist"
APP="$DIST/Viska.app"
C="$APP/Contents"

echo "==> clean dist"
rm -rf "$APP" "$DIST/Viska.dmg"
mkdir -p "$C/MacOS" "$C/Resources/bin" "$C/Resources/lib" "$C/Resources/models"

echo "==> compile Swift app"
swiftc -O app/Viska.swift -o "$C/MacOS/Viska" \
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

echo "==> bundle engine (whisper-cli + dylibs)"
cp whisper.cpp/build/bin/whisper-cli "$C/Resources/bin/"
cp -a whisper.cpp/build/bin/*.dylib "$C/Resources/lib/"

echo "==> rewire dylib search path to inside the app"
install_name_tool -delete_rpath "$HERE/whisper.cpp/build/bin" "$C/Resources/bin/whisper-cli" 2>/dev/null || true
install_name_tool -add_rpath "@executable_path/../lib" "$C/Resources/bin/whisper-cli"

echo "==> bundle model: $MODEL_NAME"
cp "models/$MODEL_NAME" "$C/Resources/models/"

echo "==> ad-hoc sign (nested code included)"
codesign --force --deep --sign - "$APP"

echo "==> verify bundled engine resolves its libraries"
if [ -f /tmp/wf_sv.wav ]; then
  "$C/Resources/bin/whisper-cli" -m "$C/Resources/models/$MODEL_NAME" \
    -f /tmp/wf_sv.wav -l sv -nt -np -fa -t 4 2>/dev/null || echo "    (varning: testkörning misslyckades)"
fi

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
