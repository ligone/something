#!/usr/bin/env bash
# Builds build/Menagerie.app: a double-clickable, ad-hoc signed app bundle.
#
#   Scripts/build-app.sh               # for this Mac's architecture
#   Scripts/build-app.sh --universal   # Apple silicon + Intel in one binary
#
# Requires Xcode (or the Command Line Tools) with Swift 5.9 or newer.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/Menagerie.app"
VERSION="1.0"

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

step() { printf '\033[1;35m▸\033[0m %s\n' "$1"; }

step "Compiling in release mode"
swift build -c release --product Menagerie ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --product Menagerie ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

step "Assembling $(basename "$APP")"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Menagerie" "$APP/Contents/MacOS/Menagerie"

LINES_OF_SWIFT="$(find App Engines -name '*.swift' -print0 | xargs -0 cat | wc -l | tr -d ' ')"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Menagerie</string>
    <key>CFBundleExecutable</key>
    <string>Menagerie</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.ligone.Menagerie</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Menagerie</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.education</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>MenagerieLinesOfSwift</key>
    <integer>$LINES_OF_SWIFT</integer>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Designed and written by Claude. Released into the public domain.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

step "Drawing the app icon"
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/Menagerie" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

step "Signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP"

step "Done: $APP"
echo "    Open it with:  open \"$APP\""
