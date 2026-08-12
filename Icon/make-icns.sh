#!/bin/bash
# Regenerates Resources/AppIcon.icns from Icon/GenerateIcon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

MASTER="$(mktemp -t standyouup-icon).png"
ICONSET="$(mktemp -d -t AppIcon)/AppIcon.iconset"
mkdir -p "$ICONSET" Resources

echo "▸ Rendering master 1024×1024…"
swiftc -O -framework Cocoa -o "$(dirname "$MASTER")/genicon" Icon/GenerateIcon.swift
"$(dirname "$MASTER")/genicon" "$MASTER"

echo "▸ Producing iconset…"
sips -z 16 16   "$MASTER" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   "$MASTER" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   "$MASTER" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   "$MASTER" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128 "$MASTER" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

echo "▸ Building icns…"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

echo "✓ Resources/AppIcon.icns"
