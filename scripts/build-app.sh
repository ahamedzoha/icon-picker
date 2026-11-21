#!/bin/bash
# Builds a universal "Icon Picker.app" into build/.
#
#   VERSION  marketing version (default: latest git tag without "v", else 0.0.0)
#   BUILD    build number Sparkle compares (default: number of commits)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="build/Icon Picker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/IconPicker" "$APP/Contents/MacOS/IconPicker"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature (no Apple Developer ID). Sparkle.framework keeps its own signature.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "Built $APP (version $VERSION, build $BUILD)"
