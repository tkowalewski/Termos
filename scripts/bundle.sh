#!/bin/sh
# Builds Termos and wraps the executable into build/Termos.app.
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -eu

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Termos.app"

swift build --package-path "$ROOT" -c "$CONFIG"
BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/Termos"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Termos"

cp "$ROOT/Sources/Termos/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles (tree-sitter queries etc.) are looked up in Contents/Resources.
for bundle in "$(dirname "$BIN")"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

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

codesign --force --sign - "$APP" >/dev/null
# Make Finder and the Dock pick up a changed icon instead of a cached one.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP"
