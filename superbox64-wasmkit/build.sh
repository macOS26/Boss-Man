#!/usr/bin/env bash
# superbox64-wasmkit build helper. No Emscripten: compiles a C/C++ game to wasm32-wasi
# with the WASI SDK and links it against the kit's sf:: web layer.
#
# Usage from your game's build script:
#   WASMWEB_OUT=path/to/game.wasm
#   WASMWEB_SRC_DIRS=(path/to/src ...)      # dirs scanned for *.cpp / *.c
#   WASMWEB_EXTRA_SRCS=(extra/file.cpp ...) # explicit extra sources (deps, glue)
#   WASMWEB_INCLUDES=(dir1 dir2 ...)        # extra -I dirs
#   WASMWEB_DEFINES=(BOSS_MAN_WEB ...)      # extra -D defines
#   WASMWEB_EXCEPTIONS=off                  # on|off (WASI libc++ is legacy-EH)
#   WASMWEB_SFML=on                         # on links the sf:: layer; off = raw ABI
#   WASMWEB_ASSETS=path/to/assets           # optional: scan for manifest
#   WASMWEB_MANIFEST=path/to/web/manifest.json
#   source path/to/superbox64-wasmkit/build.sh
#   wasmweb_build
set -euo pipefail
WASMWEB_KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

wasmweb_manifest() {  # <assetsDir> <outFile>
  python3 - "$1" "$2" <<'PY'
import os, sys, json
A, out = sys.argv[1], sys.argv[2]
def walk(sub, exts):
    d = os.path.join(A, sub); r = []
    if os.path.isdir(d):
        for root, _, files in os.walk(d):
            for f in files:
                if f.lower().endswith(exts):
                    r.append(os.path.relpath(os.path.join(root, f), A).replace(os.sep, '/'))
    return sorted(r)
m = {
    "fonts":  walk('fonts', ('.ttf', '.otf')),
    "images": walk('emoji', ('.png',)) + walk('images', ('.png', '.jpg', '.jpeg')),
    "sounds": walk('voice', ('.wav',)) + walk('sfx', ('.wav', '.ogg')),
    "texts":  sorted(f for f in os.listdir(A) if f.endswith('.json')),
}
open(out, 'w').write(json.dumps(m))
print(f"superbox64-wasmkit: manifest {len(m['fonts'])}f {len(m['images'])}i {len(m['sounds'])}s {len(m['texts'])}t")
PY
}

wasmweb_build() {
  local WASI="${WASI_SDK:-$HOME/wasi-sdk}"
  local CLANGXX="$WASI/bin/clang++"
  local SYSROOT="$WASI/share/wasi-sysroot"
  [ -x "$CLANGXX" ] || { echo "error: WASI SDK clang++ not at $CLANGXX (set WASI_SDK)" >&2; return 1; }
  : "${WASMWEB_OUT:?set WASMWEB_OUT to the output .wasm path}"

  local STD="${WASMWEB_STD:-c++20}"
  local EXC="-fno-exceptions"
  [ "${WASMWEB_EXCEPTIONS:-off}" = "on" ] && EXC=""

  local srcs=()
  for d in ${WASMWEB_SRC_DIRS[@]+"${WASMWEB_SRC_DIRS[@]}"}; do
    while IFS= read -r f; do srcs+=("$f"); done < <(find "$d" \( -name '*.cpp' -o -name '*.c' \))
  done
  for f in ${WASMWEB_EXTRA_SRCS[@]+"${WASMWEB_EXTRA_SRCS[@]}"}; do srcs+=("$f"); done
  [ "${WASMWEB_SFML:-on}" = "on" ] && srcs+=("$WASMWEB_KIT_DIR/src/sfml_web_impl.cpp")

  local inc=(-I "$WASMWEB_KIT_DIR/include")
  for d in ${WASMWEB_INCLUDES[@]+"${WASMWEB_INCLUDES[@]}"}; do inc+=(-I "$d"); done

  local def=()
  for x in ${WASMWEB_DEFINES[@]+"${WASMWEB_DEFINES[@]}"}; do def+=("-D$x"); done

  mkdir -p "$(dirname "$WASMWEB_OUT")"
  if [ -n "${WASMWEB_ASSETS:-}" ] && [ -n "${WASMWEB_MANIFEST:-}" ]; then
    wasmweb_manifest "$WASMWEB_ASSETS" "$WASMWEB_MANIFEST"
  fi

  echo "superbox64-wasmkit: compiling ${#srcs[@]} sources -> $WASMWEB_OUT"
  "$CLANGXX" \
    --target=wasm32-wasip1 --sysroot="$SYSROOT" -mexec-model=reactor \
    -std="$STD" -Os -fno-rtti $EXC \
    "${def[@]}" "${inc[@]}" \
    "${srcs[@]}" \
    -Wl,--allow-undefined \
    -Wl,-z,stack-size=8388608 \
    -Wl,--strip-all \
    -Wl,--export=_initialize -Wl,--export=boot -Wl,--export=frame -Wl,--export=memory \
    -o "$WASMWEB_OUT"
  echo "superbox64-wasmkit: built $WASMWEB_OUT ($(du -h "$WASMWEB_OUT" | cut -f1))"
}
