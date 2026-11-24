#!/bin/sh
# Build build/ExcelHotkey.app with the command line tools (no Xcode needed).
set -eu
cd "$(dirname "$0")/.."
APP=build/ExcelHotkey.app
IDENTITY="ExcelHotkey Local Signing"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/keymap"
swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/ExcelHotkey"
cp keymap/*.json "$APP/Contents/Resources/keymap/" 2>/dev/null || true
cat >"$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.excelhotkey</string>
  <key>CFBundleName</key><string>ExcelHotkey</string>
  <key>CFBundleExecutable</key><string>ExcelHotkey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>ExcelHotkey runs Excel commands for your key tips.</string>
</dict></plist>
EOF

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: no '$IDENTITY' identity (run scripts/make-cert.sh); signing ad hoc" >&2
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
