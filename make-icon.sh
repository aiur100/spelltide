#!/bin/sh
# Rebuilds Spelltide.icns. The game paints its own icon, so this needs the
# program built first. Only run this if you change the icon drawing in main.mm.
set -e
cd "$(dirname "$0")"
BIN=build/Spelltide.app/Contents/MacOS/Spelltide
if [ ! -x "$BIN" ]; then
    echo "Run ./build.sh first." >&2
    exit 1
fi

TMP=$(mktemp -d)
SET="$TMP/Spelltide.iconset"
mkdir "$SET"
"$BIN" --icon "$TMP/icon.png"

# macOS wants the same picture at ten sizes.
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$TMP/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$TMP/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Spelltide.icns
rm -rf "$TMP"
echo "Wrote Spelltide.icns. Run ./build.sh again to put it in the app."
