#!/usr/bin/env bash
# Convenience build wrapper for SuperBox64 SpriteKit.
#
# Reasons this script exists:
#  - The wasm32-wasip1 target only works through swift.org's toolchain, not
#    Xcode's bundled Swift. We need TOOLCHAINS=org.swift.<version>-release.
#  - SwiftPM defaults to the active Swift, which on macOS is Xcode's; that
#    clang has no wasm support and the C target ("KitABI shim.c") then
#    fails with "No available targets are compatible with triple
#    wasm32-unknown-wasip1". xcrun --toolchain swift fixes that.
#  - We pick the wasm SDK by name (the artifactbundle installed via
#    `swift sdk install`); override with WASM_SDK if you've named yours
#    differently.
#
# Usage:
#   ./build.sh                # debug build
#   ./build.sh release        # release build
#   ./build.sh --target Hello # forwarded to swift build

set -eo pipefail

SWIFT_TOOLCHAIN="${SWIFT_TOOLCHAIN:-org.swift.6.3.2-release}"
WASM_SDK="${WASM_SDK:-swift-6.3.2-RELEASE_wasm}"

CONFIG_ARGS=()
PASSTHROUGH=()

for arg in "$@"; do
  case "$arg" in
    release)         CONFIG_ARGS=(-c release) ;;
    debug)           CONFIG_ARGS=(-c debug)   ;;
    *)               PASSTHROUGH+=("$arg")    ;;
  esac
done

echo "→ swift build  (toolchain=$SWIFT_TOOLCHAIN  sdk=$WASM_SDK)"
TOOLCHAINS="$SWIFT_TOOLCHAIN" \
  xcrun --toolchain swift swift build \
  --swift-sdk "$WASM_SDK" \
  "${CONFIG_ARGS[@]}" \
  "${PASSTHROUGH[@]}"

echo
echo "✓ Build complete."
if [ ${#CONFIG_ARGS[@]} -gt 0 ] && [ "${CONFIG_ARGS[1]:-}" = "release" ]; then
  echo "  Artifacts: .build/wasm32-unknown-wasip1/release/"
else
  echo "  Artifacts: .build/wasm32-unknown-wasip1/debug/"
fi
