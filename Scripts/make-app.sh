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

# The finished bundle lives in dist/, but it is ASSEMBLED AND SIGNED in a staging
# directory outside iCloud. This project folder is iCloud-synced, and the file
# provider re-attaches com.apple.FinderInfo to the bundle root asynchronously —
# fast enough to land between one codesign call and the next, which made signing
# fail with "resource fork, Finder information, or similar detritus not allowed"
# on whichever binary happened to be third. Clearing xattrs in a loop cannot win
# that race; not being in the synced folder can.
FINAL_APP="dist/Unli Rice.app"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/unlirice-app.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Unli Rice.app"
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
# The GUI's SwiftPM product is "UnliRiceApp" but it ships as "UnliRice" inside the
# bundle — CFBundleExecutable below and the Mac App Store record both expect that
# name. The product was renamed only to stop it colliding with the "unlirice" CLI
# product on a case-insensitive filesystem; see Package.swift.
# ditto, not cp: cp inherits com.apple.macl, and codesign then refuses the binary
# with "resource fork, Finder information, or similar detritus not allowed". macl is
# kernel-managed, so `xattr -c` cannot strip it after the fact — it has to not be
# copied in the first place. (com.apple.provenance survives and is harmless.)
ditto --noextattr --norsrc "$BIN/UnliRiceApp" "$MACOS/UnliRice"
for binary in unlirice-mcp unlirice-agent; do
    ditto --noextattr --norsrc "$BIN/$binary" "$MACOS/$binary"
done

# Copy AppIcon if it exists
if [ -f "dist/AppIcon.icns" ]; then
    echo "==> Embedding AppIcon.icns"
    ditto --noextattr --norsrc "dist/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
    echo "WARNING: dist/AppIcon.icns not found! Run Scripts/make-icons.sh first."
fi

# SMAppService only registers launch agents declared inside the app bundle.
ditto --noextattr --norsrc "Config/LaunchAgents/com.calmdownoscar.unlirice.agent.plist" "$LAUNCHAGENTS/com.calmdownoscar.unlirice.agent.plist"
ditto --noextattr --norsrc "Sources/UnliRice/Resources/PrivacyInfo.xcprivacy" "$RESOURCES/PrivacyInfo.xcprivacy"

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
# --- signing identity ---------------------------------------------------------
# Ad-hoc signing (--sign -) produces a NEW identity on every build, and macOS binds
# security-scoped bookmarks to the signing identity. So every rebuild silently
# invalidated every folder the user had granted: the app would launch, find its
# bookmarks unresolvable, and report "No folders granted yet" as though nothing had
# ever been picked. Signing with a real certificate makes the grant survive rebuilds,
# and makes this build share grants with Xcode's.
#
# Resolved by HASH, not by name: two "Apple Development: ..." certificates for the
# same person are common, and codesign refuses an ambiguous name match. Override with
# SIGN_IDENTITY=<hash|name>. Falls back to ad-hoc so a fresh clone still builds — with
# a warning, because the fallback is what causes the symptom above.
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Developer ID Application|Apple Development/ { print $2; exit }')
fi
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="-"
    echo "==> WARNING: no signing certificate found — signing ad-hoc."
    echo "    Folder grants will not survive the next rebuild."
else
    echo "==> Signing with ${SIGN_IDENTITY}"
fi

# Extended attributes make codesign refuse with "resource fork, Finder information,
# or similar detritus not allowed". They arrive from Finder, iCloud and downloads and
# are invisible in ls, so this failure looked random.
# This project lives in an iCloud-synced folder, and the file provider re-attaches
# com.apple.FinderInfo to the bundle asynchronously — so clearing once up front is not
# enough; it can come back between here and the next codesign call. Clear immediately
# before each signature instead.
strip_xattrs() { xattr -cr "$APP" 2>/dev/null || true; xattr -c "$APP" 2>/dev/null || true; }
strip_xattrs

# Inside-out: nested code first, then the bundle. NOT --deep on the outer pass.
# --deep re-signs nested binaries with the OUTER identifier, discarding the distinct
# ones set below — which is why `codesign --verify --deep --strict` reported "nested
# code is modified or invalid" for both helpers while the build claimed success. Apple
# documents --deep as being for emergency repairs, not for building.
strip_xattrs
codesign --force --options runtime --identifier com.calmdownoscar.unlirice.agent --entitlements "$HELPER_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$MACOS/unlirice-agent"
strip_xattrs
codesign --force --options runtime --identifier com.calmdownoscar.unlirice.mcp --entitlements "$HELPER_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$MACOS/unlirice-mcp"
strip_xattrs
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$MACOS/UnliRice"
strip_xattrs
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"

# Verify rather than assume. The previous version sent codesign's stderr to /dev/null
# and printed "the app will still run locally" on failure, so an invalid signature
# looked like a successful build.
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
    echo "    signature verified"
else
    echo "    WARNING: signature did NOT verify — folder grants may not persist."
    codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/      /' | head -5
fi

# Move the signed bundle into dist/. FinderInfo may reappear on the bundle root
# here, which is harmless: the code signature seals Contents/, not the directory's
# own extended attributes.
echo "==> Installing to $FINAL_APP"
rm -rf "$FINAL_APP"
mkdir -p "$(dirname "$FINAL_APP")"
# Plain ditto here, NOT --noextattr: code signatures for non-Mach-O files inside a
# bundle are stored in extended attributes (com.apple.cs.CodeDirectory), so stripping
# them installs an unverifiable copy of a bundle that verified fine in staging.
ditto "$APP" "$FINAL_APP"

if codesign --verify --deep --strict "$FINAL_APP" 2>/dev/null; then
    echo "    installed signature verified"
else
    echo "    WARNING: installed bundle did not verify"
    codesign --verify --deep --strict --verbose=2 "$FINAL_APP" 2>&1 | sed 's/^/      /' | head -4
fi

echo
echo "Built: $FINAL_APP"
echo
