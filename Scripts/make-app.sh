#!/bin/bash
#
# Builds "Unli Rice.app" — a double-clickable app bundle.
#
# Why this exists: `swift build` produces a bare executable, which means the
# only way to start this app was a terminal command from inside the repo. That
# is a bad fit for something whose whole promise is that you can ignore it for
# months and still be glad it's there — "open it once a year" doesn't work if
# opening it means remembering a command.
#
# A bundle also buys two things the bare binary couldn't have:
#   * LaunchServices knows about it, so it appears in Spotlight and the Dock.
#   * `unlirice-agent` sits next to the GUI inside the bundle, which is how
#     BackgroundAgent.locateBinary finds it — a launchd job pointing into
#     .build/debug would break the next time someone ran `swift package clean`.
#
# Usage:  ./Scripts/make-app.sh [--debug]
# Output: dist/Unli Rice.app

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIGURATION="debug"
fi

APP="dist/Unli Rice.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

# The GUI, plus the two executables it needs to be able to point at: the MCP
# server (Get Started writes its path into other tools' configs) and the
# background agent (launchd runs it directly).
for binary in UnliRice unlirice-mcp unlirice-agent; do
    cp "$BIN/$binary" "$MACOS/$binary"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Unli Rice</string>
    <key>CFBundleDisplayName</key>
    <string>Unli Rice</string>
    <key>CFBundleIdentifier</key>
    <string>com.unlirice.app</string>
    <key>CFBundleExecutable</key>
    <string>UnliRice</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Not an agent: this has a real window and belongs in the Dock while it's
         open. The part that runs without a window is a separate executable
         (unlirice-agent) started by launchd, precisely so the GUI doesn't have
         to be resident to keep working. -->
    <key>LSUIElement</key>
    <false/>
</dict>
PLIST
echo "</plist>" >> "$APP/Contents/Info.plist"

# Ad-hoc signature. Not a distribution signature and not pretending to be one —
# it's what stops macOS treating a freshly assembled bundle as damaged when it's
# moved out of the build directory. Anyone shipping this to another machine
# needs a real Developer ID and notarisation.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null || {
    echo "    codesign failed — the app will still run locally."
}

echo
echo "Built: $APP"
echo
echo "Next:"
echo "  open \"$APP\"                      # run it"
echo "  cp -R \"$APP\" /Applications/       # keep it"
echo
echo "The 'In background' toggle in the app installs the launchd job that keeps"
echo "routines running with the window closed. It only works from the bundle —"
echo "that's where unlirice-agent lives."
