#!/usr/bin/env bash
# Boss-Man, SpriteKit edition, build helper. Wraps `swift build` with the
# swift.org toolchain + wasm SDK env so wasm32-wasip1 actually finds the
# C target (KitABI shim.c + Box2DBridge cbox2d.cpp) — Xcode's bundled clang
# has no wasm backend, so we run through xcrun --toolchain swift to pick the
# swift.org clang the wasm SDK was built against.
#
# Usage:
#   ./build.sh                  # debug
#   ./build.sh release          # release
#   ./build.sh --target BossMan # forwarded to swift build

set -eo pipefail

if [ ! -d "../superbox64-wasmkit" ]; then
  echo "→ Cloning superbox64-wasmkit..."
  git clone https://github.com/macOS26/superbox64-wasmkit ../superbox64-wasmkit
else
  git -C ../superbox64-wasmkit pull --ff-only -q 2>/dev/null || true   # keep the runtime clone fresh
fi

SWIFT_TOOLCHAIN="${SWIFT_TOOLCHAIN:-org.swift.6.3.2-release}"
WASM_SDK="${WASM_SDK:-swift-6.3.2-RELEASE_wasm}"

CONFIG_ARGS=()
PASSTHROUGH=()
for arg in "$@"; do
  case "$arg" in
    release) CONFIG_ARGS=(-c release -Xswiftc -Osize -Xlinker -s -Xswiftc -Xfrontend -Xswiftc -disable-reflection-metadata) ;;  # -Osize + strip + drop reflection field metadata (Mirror only; conformance/cast metadata kept). LTO/hermetic-seal externalize the runtime DSO-image hook and break wasm instantiation
    debug)   CONFIG_ARGS=(-c debug)   ;;
    *)       PASSTHROUGH+=("$arg")    ;;
  esac
done

echo "→ swift build  (toolchain=$SWIFT_TOOLCHAIN  sdk=$WASM_SDK)"
TOOLCHAINS="$SWIFT_TOOLCHAIN" \
  xcrun --toolchain swift swift build \
  --swift-sdk "$WASM_SDK" \
  "${CONFIG_ARGS[@]}" \
  "${PASSTHROUGH[@]}"

# Auto-publish into web/ when building release so the page is one curl away.
if [ "${CONFIG_ARGS[1]:-}" = "release" ]; then
  REL=.build/wasm32-unknown-wasip1/release/BossMan.wasm
  if command -v wasm-opt >/dev/null 2>&1; then
    # wasm-opt -Oz reads the binary's own target_features section, so it only
    # emits instructions the current runtime already supports. Squeezes a few
    # more % out after the compiler's -Osize + wasm-ld --gc-sections dead-strip.
    wasm-opt -Oz \
      --enable-bulk-memory --enable-nontrapping-float-to-int \
      --enable-sign-ext --enable-mutable-globals --enable-multivalue \
      "$REL" -o web/bossman.wasm
    echo
    echo "✓ Release artifact published (wasm-opt -Oz): web/bossman.wasm"
  else
    cp "$REL" web/bossman.wasm
    echo
    echo "✓ Release artifact published (install binaryen for a smaller wasm): web/bossman.wasm"
  fi
else
  cp .build/wasm32-unknown-wasip1/debug/BossMan.wasm web/bossman.wasm
  echo
  echo "✓ Debug artifact published: web/bossman.wasm"
fi

source ../superbox64-wasmkit/build.sh
wasmweb_manifest web/assets web/manifest.json
rm -f web/runtime.js web/runtime-embedded-min.js
cp ../superbox64-wasmkit/runtime.js web/runtime.js
# Minified runtime used by the Embedded build + the website (smaller, same behavior).
cp ../superbox64-wasmkit/runtime-embedded-min.js web/runtime-embedded-min.js
