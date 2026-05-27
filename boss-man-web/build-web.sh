#!/usr/bin/env bash
# Compile the full BOSS-MAN game to wasm32-wasi (reactor) with the WASI SDK.
# No Emscripten anywhere: clang++ targets wasm32-wasip1 and links against the
# WASI sysroot's libc++. runtime.js drives the resulting module.
#
# Inputs:
#   - boss-man-web/src/*.cpp          (game sources, copied from the native tree)
#   - Box2D v2.4.1 sources            (fetched by the native cmake)
#   - nlohmann/json single-include    (fetched by the native cmake)
#   - boss-man-web/platform/web/SFML  (our hand-rolled sf:: web headers)
#
# Output: boss-man-web/web/boss.wasm
set -euo pipefail

WASI_SDK="${WASI_SDK:-$HOME/wasi-sdk}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
NATIVE="$(cd "$ROOT/.." && pwd)/boss-man-box2d-sfml-cpp"
OUT="$ROOT/web"
mkdir -p "$OUT"

CLANGXX="$WASI_SDK/bin/clang++"
SYSROOT="$WASI_SDK/share/wasi-sysroot"

BOX2D_SRC="$NATIVE/build/_deps/box2d-src"
JSON_INC="$NATIVE/build/_deps/json-src/single_include"

if [ ! -x "$CLANGXX" ]; then
  echo "error: WASI SDK clang++ not found at $CLANGXX (set WASI_SDK)" >&2
  exit 1
fi
if [ ! -d "$BOX2D_SRC/src" ]; then
  echo "error: Box2D sources not found at $BOX2D_SRC/src" >&2
  echo "       build the native project once so cmake fetches box2d." >&2
  exit 1
fi
if [ ! -d "$JSON_INC/nlohmann" ]; then
  echo "error: nlohmann/json single-include not found at $JSON_INC" >&2
  exit 1
fi

# Game sources. EmojiTexture.mm / MacWindow.mm are Objective-C++ (native-only)
# and were never copied into src/, so the glob naturally excludes them; the web
# build uses EmojiTextureStub.cpp instead.
GAME_SRCS=$(find "$ROOT/src" -name '*.cpp')

# Our sf:: layer's out-of-line statics (Time::Zero, Color constants, ...).
IMPL_SRCS="$ROOT/platform/web/sfml_web_impl.cpp"

# All Box2D translation units.
BOX2D_SRCS=$(find "$BOX2D_SRC/src" -name '*.cpp')

# Exceptions: nlohmann/json throws, and WASI SDK libc++ ships full exception
# support, so we compile WITHOUT -fno-exceptions and let the default
# (Itanium/Wasm) EH personality handle it. If the linker ever complains about a
# missing EH personality, switch the EXC flag below to -fwasm-exceptions (which
# also requires building Box2D + libc++ with the same flag). The plain default
# is correct for WASI SDK 22+/33.
# The WASI sysroot's prebuilt libc++ uses legacy EH, so -fwasm-exceptions can't
# link cleanly and the legacy lowering emits Emscripten-style env imports the
# browser can't provide. We build exception-free: nlohmann/json is told not to
# throw (JSON_NOEXCEPTION) and the parse sites use allow_exceptions=false.
EXC="-fno-exceptions -DJSON_NOEXCEPTION"

INCLUDES=(
  -I "$ROOT/platform/web"            # <SFML/...> -> platform/web/SFML/...
  -I "$ROOT/src"
  -I "$BOX2D_SRC/include"
  -I "$BOX2D_SRC/src"
  -I "$JSON_INC"
)

CXXFLAGS=(
  --target=wasm32-wasip1
  --sysroot="$SYSROOT"
  -mexec-model=reactor
  -std=c++20 -O2
  -fno-rtti
  $EXC
  -DBOSS_MAN_WEB=1
)

LDFLAGS=(
  -Wl,--allow-undefined                 # the abi.h env imports
  -Wl,-z,stack-size=8388608             # 8 MiB: Box2D solver recursion needs it
  -Wl,--export=_initialize
  -Wl,--export=boot
  -Wl,--export=frame
  -Wl,--export=memory
)

echo "compiling $(echo "$GAME_SRCS" | wc -l | tr -d ' ') game + $(echo "$BOX2D_SRCS" | wc -l | tr -d ' ') box2d sources ..."

"$CLANGXX" \
  "${CXXFLAGS[@]}" \
  "${INCLUDES[@]}" \
  $GAME_SRCS \
  $IMPL_SRCS \
  $BOX2D_SRCS \
  "${LDFLAGS[@]}" \
  -o "$OUT/boss.wasm"

echo "built $OUT/boss.wasm ($(du -h "$OUT/boss.wasm" | cut -f1))"
