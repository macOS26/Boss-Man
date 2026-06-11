#!/usr/bin/env bash
# Build a real Embedded-Swift wasm from the (Embedded-clean) SpriteKit framework
# + a minimal scene reactor, and report its size vs the normal full-game build.
#
# This is a P3 size demonstrator, not the full game (which additionally needs the
# @MainActor default-isolation dropped and a per-module Embedded build graph).
#
# Usage:  FW=../../../SuperBox64Kit docs/embedded/build-embedded-wasm.sh
set -euo pipefail

FW="${FW:-$(cd "$(dirname "$0")/../../../SuperBox64Kit" && pwd)}"
TC="swift"
WASMLD="$(find "$HOME/Library/Developer/Toolchains" -name wasm-ld 2>/dev/null | head -1)"
OUT="$(mktemp -d)"

cp "$FW"/Sources/SpriteKit/*.swift "$OUT/"
# @MainActor isn't vended by the Embedded stdlib; single-threaded wasm drops it.
for f in "$OUT"/*.swift; do sed -i '' 's/@MainActor//g' "$f"; done

cat > "$OUT/_reactor.swift" <<'EOF'
nonisolated(unsafe) var scene: SKScene? = nil
@_cdecl("boot") func boot() {
    let s = SKScene(size: CGSize(width: 1184, height: 666))
    let n = SKSpriteNode(color: .white, size: CGSize(width: 32, height: 32))
    n.position = CGPoint(x: 100, y: 100); s.addChild(n)
    s.addChild(SKLabelNode(text: "BOSS"))
    scene = s
}
@_cdecl("frame") func frame(_ dt: Double) { scene?.update(dt) }
EOF

xcrun --toolchain "$TC" swiftc -enable-experimental-feature Embedded -wmo -parse-as-library \
  -Osize -target wasm32-unknown-none-wasm -I "$FW/Sources/KitABI/include" \
  -c "$OUT"/*.swift -o "$OUT/sk.o"
"$WASMLD" --no-entry --export=boot --export=frame --allow-undefined -o "$OUT/sk.wasm" "$OUT/sk.o"
wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext \
  --enable-mutable-globals --enable-multivalue "$OUT/sk.wasm" -o "$OUT/sk-oz.wasm"

raw=$(stat -f%z "$OUT/sk-oz.wasm"); gz=$(gzip -c -9 "$OUT/sk-oz.wasm" | wc -c | tr -d ' ')
echo "Embedded SpriteKit core wasm (wasm-opt -Oz): $raw bytes raw, $gz bytes gzip-9"
echo "Normal full-game baseline: 5138028 bytes raw, ~1883322 gzip-9"
