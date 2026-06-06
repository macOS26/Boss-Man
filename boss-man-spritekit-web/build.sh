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
    wasm-opt -Oz "$REL" -o web/bossman.wasm
    echo
    echo "✓ Release artifact published (wasm-opt -Oz): web/bossman.wasm"
  else
    cp "$REL" web/bossman.wasm
    echo
    echo "✓ Release artifact published (install binaryen for a smaller wasm): web/bossman.wasm"
  fi
  # Pre-compress so a static host can serve the negotiated variant; the wire
  # transfer drops to a fraction of the on-disk wasm (browser inflates to run).
  raw=$(wc -c < web/bossman.wasm)
  if command -v brotli >/dev/null 2>&1; then
    brotli -f -q 11 web/bossman.wasm -o web/bossman.wasm.br
    printf "✓ brotli: web/bossman.wasm.br  (%d -> %d bytes)\n" "$raw" "$(wc -c < web/bossman.wasm.br)"
  else
    echo "(brotli not installed: skipped web/bossman.wasm.br)"
  fi
  gzip -9 -kf web/bossman.wasm
  printf "✓ gzip:   web/bossman.wasm.gz  (%d -> %d bytes)\n" "$raw" "$(wc -c < web/bossman.wasm.gz)"
else
  cp .build/wasm32-unknown-wasip1/debug/BossMan.wasm web/bossman.wasm
  echo
  echo "✓ Debug artifact published: web/bossman.wasm"
fi

# Regenerate the file:/// bundle so opening web/local.html directly works
# without a local server. Includes bossman.wasm + every manifest asset as
# inline data: URLs (~25 MiB base64). server.html ships the bare wasm+assets
# over HTTP and needs no bundle. Skip with NO_BUNDLE=1.
KIT_BUNDLE="../wasm-web-kit/scripts/bundle.py"
if [ -z "${NO_BUNDLE:-}" ] && [ -f "$KIT_BUNDLE" ]; then
  python3 "$KIT_BUNDLE" web bossman.wasm || echo "(bundle.js regeneration failed)"
fi
