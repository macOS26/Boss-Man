#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WEB_SRC="$HERE/../boss-man-spritekit-web/web"
CONFIG="${1:-release}"
APP_NAME="Boss-Man-wk"
APP="$HERE/build/$APP_NAME.app"

if [[ ! -f "$WEB_SRC/bossman.wasm" ]]; then
  echo "error: $WEB_SRC/bossman.wasm not found. Build the web target first:" >&2
  echo "       (cd $HERE/../boss-man-spritekit-web && ./build.sh release)" >&2
  exit 1
fi

echo "==> swift build -c $CONFIG (universal)"
swift build --package-path "$HERE" -c "$CONFIG" --arch arm64 --arch x86_64
BIN="$HERE/.build/apple/Products/$([ "$CONFIG" = "release" ] && echo Release || echo Debug)/BossManDesktop"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web/assets"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>Boss-Man-wk</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>com.starplayrx.bossman.desktop</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

cp "$HERE/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$WEB_SRC/server.html" "$APP/Contents/Resources/web/"
cp -L "$WEB_SRC/runtime.js" "$APP/Contents/Resources/web/"
cp "$WEB_SRC/manifest.json" "$APP/Contents/Resources/web/"
cp "$WEB_SRC/bossman.wasm" "$APP/Contents/Resources/web/"
cp -R "$WEB_SRC/assets/." "$APP/Contents/Resources/web/assets/"
rm -f "$APP/Contents/Resources/web/assets/.DS_Store"

echo "==> done: $APP"
echo "    open \"$APP\""
