#!/usr/bin/env bash
# Build AgencyOS.app: render icon -> .icns, release build, assemble + sign the
# bundle, copy to the Desktop. Re-run any time after code or icon changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(dirname "$SCRIPT_DIR")"
ICONDIR="$PKG/Icon"
APP="$PKG/dist/AgencyOS.app"

echo "==> Rendering icon from SVG (QuickLook)"
MASTER="$ICONDIR/icon_master_1024.png"
rm -f "$ICONDIR/AppIcon.svg.png"
qlmanage -t -s 1024 -o "$ICONDIR" "$ICONDIR/AppIcon.svg" >/dev/null 2>&1
mv -f "$ICONDIR/AppIcon.svg.png" "$MASTER"

echo "==> Building iconset -> AppIcon.icns"
ISET="$ICONDIR/AppIcon.iconset"
rm -rf "$ISET"; mkdir -p "$ISET"
gen() { sips -z "$1" "$1" "$MASTER" --out "$ISET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png
iconutil -c icns "$ISET" -o "$ICONDIR/AppIcon.icns"

echo "==> Release build"
swift build -c release --package-path "$PKG"
BIN="$(swift build -c release --package-path "$PKG" --show-bin-path)/AgencyOS"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AgencyOS"
cp "$ICONDIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$PKG/Packaging/Info.plist" "$APP/Contents/Info.plist"

echo "==> Ad-hoc codesign"
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "==> Copying to Desktop"
DESK="$HOME/Desktop/AgencyOS.app"
rm -rf "$DESK"
cp -R "$APP" "$DESK"

# Clean throwaway renders
rm -f "$ICONDIR/render_magick.png" "$ICONDIR/render_ql.png"

echo ""
echo "Done."
echo "  Bundle:  $APP"
echo "  Desktop: $DESK"