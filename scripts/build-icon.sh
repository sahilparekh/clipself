#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
ICONSET="$PWD/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" Assets/AppIcon-source.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" Assets/AppIcon-source.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
if ! iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns 2>/dev/null; then
    python3 Tools/PackIcon.py "$ICONSET" Assets/AppIcon.icns
fi
echo "Built Assets/AppIcon.icns"
