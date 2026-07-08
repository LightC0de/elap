#!/bin/sh
# Assembles dist/ELAP.app: bundles the ELAPApp menu bar UI with the elap CLI
# binary inside Contents/MacOS/elap, so the app can drive display changes via
# subprocess instead of mutating displays in-process (see menu-bar-app-plan.md).
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/ELAP.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

BUNDLE_ID="${ELAP_BUNDLE_ID:-com.elap.app}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

VERSION_FILE="$ROOT_DIR/Sources/ELAPCore/Version.swift"
VERSION=$(sed -n 's/.*elapVersion *= *"\(.*\)".*/\1/p' "$VERSION_FILE")
if [ -z "$VERSION" ]; then
    echo "error: could not extract elapVersion from $VERSION_FILE" >&2
    exit 1
fi

echo "==> Building ELAPApp and ELAP (release)"
swift build -c release --product ELAPApp
swift build -c release --product ELAP

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/ELAPApp" "$MACOS_DIR/ELAPApp"
cp "$ROOT_DIR/.build/release/elap" "$MACOS_DIR/elap"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ELAPApp</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>ELAP</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

echo "==> Codesigning (identity: $CODESIGN_IDENTITY)"
codesign --force --sign "$CODESIGN_IDENTITY" --options runtime "$MACOS_DIR/elap"
codesign --force --sign "$CODESIGN_IDENTITY" --options runtime "$APP_DIR"

echo "==> Built $APP_DIR (version $VERSION, bundle id $BUNDLE_ID)"
