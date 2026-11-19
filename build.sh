#!/bin/sh
# Builds build/Spelltide.app. Run: ./build.sh && open build/Spelltide.app
set -e
cd "$(dirname "$0")"
APP=build/Spelltide.app
BIN="$APP/Contents/MacOS/Spelltide"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Build beside the old program, then swap, so a running game is not disturbed.
clang++ -std=c++20 -O2 -fobjc-arc -Wall -Wextra \
    src/main.mm -o "$BIN.new" \
    -framework Cocoa -framework QuartzCore
mv -f "$BIN.new" "$BIN"

cp Info.plist "$APP/Contents/Info.plist"
cp words.txt "$APP/Contents/Resources/words.txt"
cp Spelltide.icns "$APP/Contents/Resources/Spelltide.icns"
touch "$APP"   # nudges Finder to pick up a changed icon
echo "Built $APP"
