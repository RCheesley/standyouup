#!/bin/bash
# Builds StandYouUp.app from the SwiftPM executable target.
# Requires the Xcode Command Line Tools (no full Xcode needed).
#
# Set UNIVERSAL=1 to build for both Apple Silicon and Intel (needs full Xcode).
# Releases are built this way; a plain build targets the Mac you're on.
set -euo pipefail

cd "$(dirname "$0")"

APP="StandYouUp.app"
BIN_NAME="StandYouUp"
BUNDLE_ID="uk.co.silavapi.StandYouUp"
VERSION="$(cat VERSION)"

ARCH_FLAGS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

echo "==> Building StandYouUp (swift build -c release ${ARCH_FLAGS})..."
# ARCH_FLAGS is deliberately unquoted so it splits into separate arguments.
swift build -c release ${ARCH_FLAGS} --product "${BIN_NAME}"

BIN_PATH="$(swift build -c release ${ARCH_FLAGS} --product "${BIN_NAME}" --show-bin-path)/${BIN_NAME}"

echo "==> Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN_NAME}"

ICON_LINE=""
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
    ICON_LINE="    <key>CFBundleIconFile</key>        <string>AppIcon</string>"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>StandYouUp</string>
    <key>CFBundleDisplayName</key>     <string>StandYouUp</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>${BIN_NAME}</string>
${ICON_LINE}
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>StandYouUp - GPL-3.0-or-later</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code-signing..."
codesign --force --deep --sign - "${APP}" 2>/dev/null || echo "    (codesign skipped)"

echo "OK: Built ${APP} (v${VERSION}) for: $(lipo -archs "${APP}/Contents/MacOS/${BIN_NAME}")"
echo
echo "Run it with:   open \"$(pwd)/${APP}\""
echo "It appears in the menu bar (no Dock icon)."
