#!/bin/bash
#
# Generates "AppIcon.icns" from a master 1024x1024 image.
# Uses sips to downscale and iconutil to package them.
#
# Usage: ./Scripts/make-icons.sh <master-image.png/jpg>
#

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_1024x1024_image>"
    exit 1
fi

SRC_IMAGE="$1"
ICONSET="dist/AppIcon.iconset"
ICNS="dist/AppIcon.icns"
ASSET_CATALOG="Sources/UnliRice/Resources/Assets.xcassets"
ASSET_APPICON="$ASSET_CATALOG/AppIcon.appiconset"

mkdir -p dist
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

echo "==> Generating icon sizes using sips..."
sips -s format png -z 16 16     "$SRC_IMAGE" --out "$ICONSET/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "$SRC_IMAGE" --out "$ICONSET/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "$SRC_IMAGE" --out "$ICONSET/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "$SRC_IMAGE" --out "$ICONSET/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "$SRC_IMAGE" --out "$ICONSET/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "$SRC_IMAGE" --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "$SRC_IMAGE" --out "$ICONSET/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "$SRC_IMAGE" --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "$SRC_IMAGE" --out "$ICONSET/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "$SRC_IMAGE" --out "$ICONSET/icon_512x512@2x.png" > /dev/null

echo "==> Updating the Xcode App Icon asset catalog..."
rm -rf "$ASSET_APPICON"
mkdir -p "$ASSET_APPICON"
cp "$ICONSET"/*.png "$ASSET_APPICON/"
cat > "$ASSET_CATALOG/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
cat > "$ASSET_APPICON/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "==> Compiling a legacy .icns for Scripts/make-app.sh..."
if ! iconutil -c icns "$ICONSET" -o "$ICNS"; then
    echo "WARNING: iconutil rejected the generated iconset. The Xcode asset catalog was still updated successfully."
fi

# Clean up iconset
rm -rf "$ICONSET"

echo "==> Updated $ASSET_APPICON successfully"
