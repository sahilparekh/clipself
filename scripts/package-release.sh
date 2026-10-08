#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh --universal
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/ClipShelf.app"
lipo "$APP/Contents/MacOS/ClipShelf" -verify_arch arm64 x86_64
codesign --verify --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
STAGE="$PWD/.build/release/ClipShelf"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/ClipShelf.app"
cp LICENSE "$STAGE/LICENSE.txt"
cat > "$STAGE/INSTALL.txt" <<'INSTALL'
ClipShelf — macOS 13 or later, Apple Silicon and Intel

1. Drag ClipShelf.app into your Applications folder.
2. Open ClipShelf.app. It runs in the menu bar.
3. Copy a few items normally, then press Command + Option + Down/Up to cycle.
4. Press Command + V to paste into your current app.

Open searchable history: Command + Shift + V
Quit: right-click the clipboard icon in the menu bar and choose Quit ClipShelf.

This preview uses an ad-hoc signature. It is not Developer ID signed or
notarized by Apple. macOS may block the first launch of a downloaded copy.
If you trust this download, after trying to open the app, use System Settings
> Privacy & Security > Open Anyway to approve this app.
Apple's instructions: https://support.apple.com/en-us/102445

File clips refer to the originals; keep those files in place. Clipboard history
is stored locally as unencrypted JSON. Pause capture before copying secrets.

Project and source: https://github.com/sahilparekh/clipself
INSTALL
ARCHIVE="ClipShelf-$APP_VERSION-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
echo "Packaged dist/$ARCHIVE"
