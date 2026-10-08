#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
if [[ ! -f Assets/AppIcon.icns ]]; then ./scripts/build-icon.sh; fi
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "VERSION must contain a version such as 1.3.2" >&2
    exit 1
fi
ARCHITECTURES=("$(uname -m)")
case "${1:-}" in
    --universal) ARCHITECTURES=(arm64 x86_64) ;;
    "") ;;
    *) echo "Usage: $0 [--universal]" >&2; exit 1 ;;
esac
mkdir -p .build/clang-cache
BINARIES=()
for ARCH in "${ARCHITECTURES[@]}"; do
    swiftc -O -swift-version 5 -target "$ARCH-apple-macosx13.0" -parse-as-library -module-name ClipShelf \
        -module-cache-path "$PWD/.build/clang-cache" \
        Sources/ClipShelf/*.swift -o ".build/ClipShelf-$ARCH"
    BINARIES+=(".build/ClipShelf-$ARCH")
done
if (( ${#BINARIES[@]} > 1 )); then
    lipo -create "${BINARIES[@]}" -output .build/ClipShelf
else
    cp "${BINARIES[1]}" .build/ClipShelf
fi
APP="$(pwd)/dist/ClipShelf.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/ClipShelf "$APP/Contents/MacOS/ClipShelf"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ClipShelf</string>
<key>CFBundleDisplayName</key><string>ClipShelf</string>
<key>CFBundleIdentifier</key><string>dev.clipshelf.app</string>
<key>CFBundleExecutable</key><string>ClipShelf</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
cat > dist/Restart-ClipShelf.command <<'RESTART'
#!/bin/zsh
exec /usr/bin/open -n "$(dirname "$0")/ClipShelf.app"
RESTART
chmod +x dist/Restart-ClipShelf.command
echo "Built $APP"
