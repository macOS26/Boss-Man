#!/usr/bin/env bash
# BOSS-MAN web build: configures wasm-web-kit for this game and builds boss.wasm.
# The game sources are the SHARED native tree (web bits behind BOSS_MAN_WEB).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
NATIVE="$REPO/boss-man-box2d-sfml-cpp"
KIT="$REPO/wasm-web-kit"
BOX2D="$NATIVE/build/_deps/box2d-src"
JSON="$NATIVE/build/_deps/json-src/single_include"

[ -d "$BOX2D/src" ] || { echo "error: build the native project once so cmake fetches box2d ($BOX2D)" >&2; exit 1; }
[ -d "$JSON/nlohmann" ] || { echo "error: nlohmann/json single-include not found at $JSON" >&2; exit 1; }

WASMWEB_OUT="$ROOT/web/boss.wasm"
WASMWEB_SRC_DIRS=("$NATIVE/src")
WASMWEB_EXTRA_SRCS=("$ROOT/platform/web/MacWindow_web.cpp")     # game-specific web glue
while IFS= read -r f; do WASMWEB_EXTRA_SRCS+=("$f"); done < <(find "$BOX2D/src" -name '*.cpp')
WASMWEB_INCLUDES=("$NATIVE/src" "$BOX2D/include" "$BOX2D/src" "$JSON")
WASMWEB_DEFINES=(BOSS_MAN_WEB JSON_NOEXCEPTION)
WASMWEB_EXCEPTIONS=off
WASMWEB_SFML=on
WASMWEB_ASSETS="$NATIVE/assets"
WASMWEB_MANIFEST="$ROOT/web/manifest.json"

source "$KIT/build.sh"
wasmweb_build
