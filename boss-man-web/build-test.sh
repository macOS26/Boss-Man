#!/usr/bin/env bash
# Compile the toolchain-proof module to wasm32-wasi (reactor) with WASI SDK.
# No Emscripten anywhere in this pipeline.
set -euo pipefail

WASI_SDK="${WASI_SDK:-$HOME/wasi-sdk}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/web"
mkdir -p "$OUT"

"$WASI_SDK/bin/clang++" \
  --target=wasm32-wasi \
  --sysroot="$WASI_SDK/share/wasi-sysroot" \
  -mexec-model=reactor \
  -std=c++20 -O2 -fno-exceptions -fno-rtti \
  -Wl,--allow-undefined \
  -Wl,--export=boot -Wl,--export=frame -Wl,--export=key_event \
  -Wl,--export=__heap_base -Wl,--export=memory \
  "$ROOT/test/web_main.cpp" \
  -o "$OUT/boss.wasm"

echo "built $OUT/boss.wasm ($(du -h "$OUT/boss.wasm" | cut -f1))"
