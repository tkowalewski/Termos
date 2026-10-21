#!/bin/sh
# Builds Termos and wraps the executable into build/Termos.app.
# Usage: scripts/bundle.sh [debug|release]   (default: release)
#
# Release builds are universal (arm64 + x86_64); debug builds are for this Mac only.
# Signs with $TERMOS_SIGN_IDENTITY (e.g. "Developer ID Application: Name (TEAMID)"),
# or ad-hoc when it is not set.
set -eu

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Termos.app"
IDENTITY="${TERMOS_SIGN_IDENTITY:--}"

if [ "$CONFIG" = release ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
else
    ARCH_FLAGS=""
fi

swift build --package-path "$ROOT" -c "$CONFIG" $ARCH_FLAGS
BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" $ARCH_FLAGS --show-bin-path)/Termos"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Termos"

cp "$ROOT/Sources/Termos/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles (tree-sitter queries etc.) are looked up in Contents/Resources.
for bundle in "$(dirname "$BIN")"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Swift 6.2 links libswiftCompatibilitySpan, which macOS ships only from version 26.
# Bundle it for older systems; /usr/lib/swift stays first in the search path, so newer
# systems keep using their own copy.
SPAN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libswiftCompatibilitySpan.dylib"
if otool -L "$APP/Contents/MacOS/Termos" | grep -q libswiftCompatibilitySpan; then
    cp "$SPAN" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Termos"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Termos</string>
    <key>CFBundleDisplayName</key><string>Termos</string>
    <key>CFBundleIdentifier</key><string>pl.tkowalewski.Termos</string>
    <key>CFBundleExecutable</key><string>Termos</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

if [ "$IDENTITY" = - ]; then
    SIGN_FLAGS=""
else
    # Notarization requires the hardened runtime and a secure timestamp.
    SIGN_FLAGS="--options runtime --timestamp"
fi
for lib in "$APP"/Contents/Frameworks/*.dylib; do
    [ -e "$lib" ] && codesign --force --sign "$IDENTITY" $SIGN_FLAGS "$lib"
done
codesign --force --sign "$IDENTITY" $SIGN_FLAGS "$APP"
codesign --verify --strict "$APP"

# Make Finder and the Dock pick up a changed icon instead of a cached one.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP"
