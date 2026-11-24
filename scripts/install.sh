#!/bin/sh
# Build, copy to ~/Applications, and start at login via a LaunchAgent.
set -eu
cd "$(dirname "$0")/.."
./scripts/build.sh

DEST="$HOME/Applications/ExcelHotkey.app"
LABEL=local.excelhotkey
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$DEST"
cp -R build/ExcelHotkey.app "$DEST"

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/ExcelHotkey</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $DEST and started it. Grant Accessibility in System Settings if asked."
