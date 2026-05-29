#!/usr/bin/env bash
# Build, embed, sign, notarize, staple, and zip the universal macOS release of
# the C++ SFML Boss-Man into Boss-Man-macOS-universal.zip.
#
# The CMake build links SFML/Box2D as @rpath dylibs and SFML pulls its codec
# libraries in as @rpath/../Frameworks/*.framework. None of that is inside the
# .app, so a bare zip will not launch on another Mac. This script copies the
# dylibs + frameworks into Contents/Frameworks, points the executable's rpath
# at them, then Developer ID signs everything with the hardened runtime,
# notarizes the zip, staples the ticket, and re-zips the stapled app.
#
# One-time setup for notarization (stores an App Store Connect credential in the
# keychain under the profile name this script expects):
#   xcrun notarytool store-credentials boss-man-notary \
#       --apple-id "you@example.com" --team-id 469UCUB275 \
#       --password "app-specific-password"
# (or use --key/--key-id/--issuer for an App Store Connect API key.)
#
# Usage:
#   scripts/release-macos.sh                 # full build -> signed, notarized zip
#   SKIP_NOTARIZE=1 scripts/release-macos.sh # stop after signing + zip (local test)
#
# Overridable env: IDENTITY, NOTARY_PROFILE, BUILD_DIR, ZIP_OUT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build-universal}"
IDENTITY="${IDENTITY:-Developer ID Application: Todd Bruss (469UCUB275)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-boss-man-notary}"
ZIP_OUT="${ZIP_OUT:-$ROOT/Boss-Man-macOS-universal.zip}"
APP="$BUILD_DIR/Boss-Man-mac.app"
EXE="$APP/Contents/MacOS/Boss-Man-mac"
FW="$APP/Contents/Frameworks"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

say "Configuring + building universal Release (arm64 + x86_64)"
cmake -S "$ROOT" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu)"
[ -d "$APP" ] || { echo "error: $APP not found after build" >&2; exit 1; }

say "Embedding SFML/Box2D dylibs + codec frameworks into the bundle"
SFML_LIB="$BUILD_DIR/_deps/sfml-build/lib"
BOX2D_BIN="$BUILD_DIR/_deps/box2d-build/bin"
SFML_FW="$BUILD_DIR/_deps/sfml-src/extlibs/libs-osx/Frameworks"
rm -rf "$FW"; mkdir -p "$FW"

# Copy every @rpath dylib the executable links, resolving the real file.
for dep in $(otool -L "$EXE" | awk '/@rpath\/.*\.dylib/ {print $1}' | sed 's|@rpath/||' | sort -u); do
    src=""
    [ -f "$SFML_LIB/$dep" ] && src="$SFML_LIB/$dep"
    [ -z "$src" ] && [ -f "$BOX2D_BIN/$dep" ] && src="$BOX2D_BIN/$dep"
    [ -z "$src" ] && { echo "error: cannot find dylib for $dep" >&2; exit 1; }
    ditto "$src" "$FW/$dep"
    chmod u+w "$FW/$dep"
    install_name_tool -id "@rpath/$dep" "$FW/$dep"
done

# Copy SFML's vendored codec frameworks. Their consumers reference them as
# @rpath/../Frameworks/<name>.framework, which resolves to Contents/Frameworks
# once the executable rpath below points there.
for fwk in freetype FLAC ogg vorbis vorbisenc vorbisfile OpenAL; do
    [ -d "$SFML_FW/$fwk.framework" ] && ditto "$SFML_FW/$fwk.framework" "$FW/$fwk.framework"
done

say "Pointing the executable rpath at the embedded Frameworks"
for rp in $(otool -l "$EXE" | awk '/cmd LC_RPATH/{c=1} c&&/ path /{print $2; c=0}' | sort -u); do
    install_name_tool -delete_rpath "$rp" "$EXE" 2>/dev/null || true
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"

say "Developer ID signing (hardened runtime, secure timestamp), inside-out"
sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }
for f in "$FW"/*.framework; do [ -e "$f" ] && sign "$f"; done
for d in "$FW"/*.dylib;     do [ -e "$d" ] && sign "$d"; done
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

say "Zipping $ZIP_OUT"
rm -f "$ZIP_OUT"
ditto -c -k --keepParent "$APP" "$ZIP_OUT"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    say "SKIP_NOTARIZE=1 set — signed + zipped, skipping notarization"
    exit 0
fi

say "Notarizing (this waits for Apple)"
xcrun notarytool submit "$ZIP_OUT" --keychain-profile "$NOTARY_PROFILE" --wait

say "Stapling the ticket and re-zipping"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP_OUT"
ditto -c -k --keepParent "$APP" "$ZIP_OUT"
spctl -a -t exec -vv "$APP" || true

say "Done: $ZIP_OUT"
