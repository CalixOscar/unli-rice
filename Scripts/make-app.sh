#!/bin/bash
#
# Builds "Unli Rice.app" — a double-clickable app bundle.
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
LAUNCHAGENTS="$APP/Contents/Library/LaunchAgents"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES" "$LAUNCHAGENTS"

# The GUI, plus the two executables it needs to be able to point at: the MCP
# server (Get Started writes its path into other tools' configs) and the
# background agent (launchd runs it directly).
for binary in UnliRice unlirice-mcp unlirice-agent; do
    cp "$BIN/$binary" "$MACOS/$binary"
done

# Copy AppIcon if it exists
if [ -f "dist/AppIcon.icns" ]; then
    echo "==> Embedding AppIcon.icns"
    cp "dist/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
    echo "WARNING: dist/AppIcon.icns not found! Run Scripts/make-icons.sh first."
fi

# SMAppService only registers launch agents declared inside the app bundle.
cp "Config/LaunchAgents/com.calmdownoscar.unlirice.agent.plist" "$LAUNCHAGENTS/"
cp "Sources/UnliRice/Resources/PrivacyInfo.xcprivacy" "$RESOURCES/"

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
    <string>com.calmdownoscar.unlirice</string>
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
    <key>LSUIElement</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 calmdownoscar. All rights reserved.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
</dict>
</plist>
PLIST

# Code signing with entitlements for sandbox compliance
echo "==> Signing targets with entitlements (ad-hoc)"
ENTITLEMENTS="UnliRice.entitlements"
HELPER_ENTITLEMENTS="UnliRiceHelper.entitlements"

# Sign each executable inside the bundle
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$MACOS/UnliRice"
codesign --force --options runtime --identifier com.calmdownoscar.unlirice.agent --entitlements "$HELPER_ENTITLEMENTS" --sign - "$MACOS/unlirice-agent"
codesign --force --options runtime --identifier com.calmdownoscar.unlirice.mcp --entitlements "$HELPER_ENTITLEMENTS" --sign - "$MACOS/unlirice-mcp"

# Sign the entire bundle
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP" 2>/dev/null || {
    echo "    codesign failed — the app will still run locally."
}

echo
echo "Built: $APP"
echo
