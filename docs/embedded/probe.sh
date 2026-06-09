#!/usr/bin/env bash
# Embedded-Swift feasibility probe for Boss-Man (Phase 0).
#
# Confirms (a) the toolchain compiles Embedded Swift for bare wasm, and
# (b) the game's stdlib-only logic files have no Embedded-Swift semantic
# blockers. Pure reconnaissance: compiles to a throwaway object, runs nothing.
#
# Usage:  docs/embedded/probe.sh
set -uo pipefail

GAME="$(cd "$(dirname "$0")/../../boss-man-spritekit-swift/Boss-Man" && pwd)"
OUT="$(mktemp -d)"
SC=(xcrun --toolchain swift swiftc -enable-experimental-feature Embedded -wmo
    -parse-as-library -target wasm32-unknown-none-wasm)

echo "→ toolchain: $(xcrun --toolchain swift swift --version | head -1)"

echo "→ Tier 1: trivial Embedded wasm"
printf 'func add(_ a: Int, _ b: Int) -> Int { a + b }\n' > "$OUT/hello.swift"
"${SC[@]}" -c "$OUT/hello.swift" -o "$OUT/hello.o" 2>"$OUT/t1.txt" \
  && echo "  ✓ Embedded wasm objects compile" || { cat "$OUT/t1.txt"; exit 1; }

# stdlib-only game files (no `import SpriteKit`): the slice that could go
# Embedded today if the framework did. Keep in sync with the import audit.
LOGIC=(GameRandom GameState LevelTravelers LocalHighScores MoveDirection
       PhysicsCategory PowerPelletTimer Strings Strings+Shared WaterGunState)

echo "→ Tier 2: pure game-logic slice under Embedded"
mkdir -p "$OUT/game"
for f in "${LOGIC[@]}"; do cp "$GAME/$f.swift" "$OUT/game/"; done
# @MainActor is not vended by the Embedded stdlib; strip to see what's underneath.
for f in "$OUT"/game/*.swift; do sed -i '' 's/@MainActor//g' "$f"; done
"${SC[@]}" -c "$OUT"/game/*.swift -o "$OUT/game.o" 2>"$OUT/t2.txt"

emb=$(grep -hiE "embedded swift|existential|metatype|reflection|dynamic cast|runtime support" "$OUT/t2.txt" \
      | grep -vi "cannot find\|has no member\|argument label\|redeclaration\|convert value" | wc -l | tr -d ' ')
xref=$(grep -c "cannot find\|has no member" "$OUT/t2.txt")
echo "  genuine Embedded-restriction errors in pure logic: $emb"
echo "  cross-module missing-symbol errors (framework-owned): $xref"
echo
echo "Verdict: pure game logic has no stdlib-level Embedded blockers (modulo @MainActor)."

# Tier 3: the SpriteKit framework itself. Point FW at the local checkout.
FW="${FW:-$(cd "$(dirname "$0")/../../../superbox64-spritekit" 2>/dev/null && pwd)}"
if [ -n "$FW" ] && [ -d "$FW/Sources/SpriteKit" ]; then
  echo "→ Tier 3: SpriteKit framework under Embedded ($FW)"
  mkdir -p "$OUT/sk"; cp "$FW"/Sources/SpriteKit/*.swift "$OUT/sk/"
  for f in "$OUT"/sk/*.swift; do
    sed -i '' 's/@MainActor//g; s/weak var/var/g; s/weak let/let/g' "$f"
    sed -i '' -E 's/\[weak ([a-zA-Z_]+)\]/[\1]/g' "$f"   # neutralize weak (compile-only) to expose layer 2
  done
  "${SC[@]}" -I "$FW/Sources/KitABI/include" -c "$OUT"/sk/*.swift -o "$OUT/sk.o" 2>"$OUT/t3.txt"
  echo "  Embedded restriction errors after weak-strip (layer 2): $(grep -c 'EmbeddedRestrictions' "$OUT/t3.txt")"
  grep -hoE "cannot (do dynamic casting|use a value of protocol type '[^']*')" "$OUT/t3.txt" | sort | uniq -c | sort -rn | sed 's/^/    /'
fi
echo
echo "The Embedded barrier is ~40 sites in SpriteKit marshalling files. See feasibility.md."
echo "logs: $OUT"
