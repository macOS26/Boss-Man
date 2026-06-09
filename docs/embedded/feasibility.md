# Embedded Swift Feasibility — Boss-Man WASM (Phase 0 probe)

Branch: `embedded-swift-no-foundation`. Reproduce with `docs/embedded/probe.sh`.
Goal: eliminate Foundation and the Swift stdlib surface so the WASM build can one
day compile with `-enable-experimental-feature Embedded`.

## Headline findings (evidence-based)

1. **Foundation is already gone from the WASM build.** The compiled swiftmodules
   are `AppKit, AVFoundation, BossMan, GameController, GameKit, SpriteKit, UIKit`
   — there is **no `Foundation.swiftmodule`**. The shared (WASI-compiled) game
   code uses zero real Foundation; the Foundation-looking types it touches are
   framework shims (`UserDefaults`→localStorage, `Bundle`, `URL`, `UUID`,
   `NSRange`, and an `NSCoder` stub for `required init?(coder:)`). JSON is
   hand-rolled (see `LocalHighScores.swift`, `LevelEditorScene.swift`,
   `MiniJSON.swift`) precisely because Codable/JSONEncoder are absent on WASI.
   Real Foundation usages (`NSObject`, `NotificationCenter`, `JSONSerialization`,
   `FileManager`, `NSString`, `NSLog`, `DispatchQueue`) live only in
   macOS-gated files not in the WASM target.

2. **The game's pure logic is Embedded-ready today.** Compiling the 10 stdlib-only
   game files under `-enable-experimental-feature Embedded -target
   wasm32-unknown-none-wasm` produced **zero genuine Embedded-restriction
   errors**. The only stdlib-level blocker is `@MainActor` (8 sites), which the
   Embedded stdlib does not vend. Every other diagnostic was a missing
   cross-module symbol (`Persistence`, `HUD`, `KeyCode`) owned by
   framework-importing files — not an Embedded incompatibility.

3. **The entire Embedded barrier is the SpriteKit framework**
   (`../superbox64-spritekit`). The game can't go Embedded while it links a
   non-Embedded `SpriteKit`.

## Residual non-Foundation footprint
- ~10 ICU symbols still link from **stdlib `String`** operations (not Foundation).
  Relevant to stdlib slimming, independent of the Foundation work.

## P1 framework spike — ACTUAL Embedded errors (overrides the survey)

Compiled all 30 `superbox64-spritekit/Sources/SpriteKit/*.swift` under
`-enable-experimental-feature Embedded -target wasm32-unknown-none-wasm` with
KitABI on the include path. The static survey above assumed **early**-Embedded
rules and was wrong: current Embedded Swift (6.3.2) **accepts class inheritance,
`open` classes, vtable/`override` dispatch, polymorphic `[SKNode]`, and
class-to-class `as?` downcasts.** None of those produced errors.

The compiler reports exactly **two layers** of real blockers (40 sites, ~8 files):

**Layer 1 — `weak`/`unowned` (8 sites, 5 files).** Embedded has no weak-reference
runtime side table.
- `SKNode.parent`, `SKScene.view`, `SKScene.camera`, `SKPhysicsBody.node`,
  `SKPhysicsWorld.contactDelegate`, `SKEmitterNode.targetNode` (weak vars)
- `SKAction.swift:243` `[weak target]` capture
- Fix: `unowned(unsafe)` back-references (single-threaded wasm, lifetimes are
  scene-scoped) or explicit parent-owned pointers. Mechanical.

**Layer 2 — existential `Any` / non-class protocols + casts from them (32 sites).**
These are the genuine refactors; all in value-marshalling code, NOT the node graph:
| Kind | Sites | Files |
|------|-------|-------|
| `cannot do dynamic casting` (`as?` **from `Any`/protocol**, not class downcasts) | 18 | `SKSceneLoader` (6), `SKKeyframeSequence`, `SKStubs`, `UserDefaults`, … |
| `value of protocol type 'Any'` | 8 | `MiniJSON` (3), `UserDefaults`, … |
| `value of protocol type 'any SKAudioURL'` | 4 | `SKAudioNode`, `SKStubs` |
| `value of protocol type 'any NSNumberLike'` | 2 | `SKKeyframeSequence` |

Fixes (behavior-preserving, ship to the normal build first):
- **MiniJSON / SKSceneLoader / UserDefaults**: replace the `Any` JSON value with a
  `enum JSONValue { case string/number/bool/array/object/null }`; the `as?` chains
  become `switch`. (`SKSceneLoader` may be excludable from the wasm build — the game
  builds scenes programmatically; verify the `Levels.swift` reference path.)
- **SKKeyframeSequence**: make it generic over the value type or use a small typed
  enum instead of `any NSNumberLike` + `[Any]`.
- **SKAudioNode**: make `SKAudioURL` a concrete type (or generic), drop the existential.

**Not blockers (Embedded accepts them):** the SKNode hierarchy, `open` classes,
`override`, `[SKNode]` storage, class-bound `AnyObject` delegate protocols, and
class-to-class `as?` (so the game's ~18 `node as? PixelPerson`-style casts are fine).
`@MainActor` (drop on single-threaded wasm) and stdlib `String`→ICU remain, handled last.

Revised estimate: **days–weeks for the framework**, not months — ~40 mechanical/
small-refactor sites in ~8 marshalling files, with the node graph untouched.

## Recommended path (incremental, keeps the shipping game green)

- **P0 (done):** probe + map. The game-logic slice compiles Embedded.
- **P1 (done):** framework spike. SpriteKit compiles under Embedded except 40
  concrete sites in ~8 marshalling files (see table above). Node graph is fine.
- **P2 — de-existentialize the framework, behavior-preserving:**
  - finalize the SKNode subclasses; replace `open` with `final` where the game
    doesn't subclass, keep a minimal extension point where it does (`Scene3D`).
  - replace `AnyObject` delegates with concrete generic or closure callbacks.
  - replace node-subtype `as?` chains with a `kind` enum + typed accessors
    (visitor), starting with the hottest: `SKAction`, `SKView` dispatch.
  - make `SKKeyframeSequence` generic over the value type; drop `[Any]`.
  These ship to the normal (non-Embedded) build first and must keep it identical.
- **P3 — flip the flag** on a dedicated Embedded build target once #1–#4 are clear;
  handle `@MainActor` (single-threaded wasm → drop the global actor or use the
  Embedded concurrency model) and the ICU `String` ops last.

## Reality check
The static survey guessed 3–6 months assuming early-Embedded rules. The actual
compiler disagrees: the node graph (open classes, overrides, polymorphic arrays,
class downcasts) compiles Embedded as-is. The real work is **~40 sites in ~8
marshalling files** (weak refs + `Any`/protocol-existential JSON/keyframe/audio
code) — a days-to-weeks effort in `superbox64-spritekit`, done behavior-
preservingly against the live web build. Game-side risk is ~zero (P0).

## P2 progress (framework branch `superbox64-spritekit@embedded`)

**Layer 1 — DONE & verified.** All 8 `weak` sites guarded with
`#if hasFeature(Embedded)` → `unowned(unsafe)` (else `weak`). Normal wasm
SpriteKit build still compiles unchanged (production untouched); Embedded weak
errors 8→0. Files: SKNode, SKScene, SKPhysics, SKEmitterNode, SKAction.

**Layer 2 — scoped, remaining (32 errors).** Split by whether Boss-Man uses it:
- **Dead code for the game** (`SKEmitterNode`, `SKKeyframeSequence`, `SKAudioNode`
  are UNUSED): ~12 errors (`any NSNumberLike` ×2, `any SKAudioURL` ×4, keyframe
  `Any`/casts). Fix: `#if !hasFeature(Embedded)` exclude the `Any`-based members
  on the Embedded build (never called). Low risk.
- **Live code** (level parsing + persistence): the real refactor.
  - `MiniJSON.parseJSON` returns `Any?` → introduce
    `enum JSONValue { case object([String:JSONValue]); case array([JSONValue]);
    case string(String); case number(Double); case bool(Bool); case null }`
    and return `JSONValue?`. Consumers switch instead of `as?`.
  - Consumers to migrate together: framework `SKSceneLoader` (6 casts; dead for
    the game, can `#if`-exclude on Embedded), framework `UserDefaults` (1 `Any`
    + 1 cast), and **game `Levels.swift`** (`obj[name] as? [Any]` → switch on
    `JSONValue`). This is cross-repo (framework `embedded` + a game branch) and
    must be verified by parsing a real level and diffing behavior.

**Layer 2 progress (framework `embedded` branch):**
- **P2.2 dead-code existentials — DONE.** Guarded the subsystems Boss-Man never
  uses. Each verified: Embedded errors drop, normal wasm SpriteKit build unchanged.
  - `any SKAudioURL` → store `String` (lastPathComponent; never read), unused
    existential `init(url:)` behind `#if !hasFeature(Embedded)` (SKAudioNode, SKStubs).
    Note: Embedded also forbids **generic `init` on classes**, so the URL init is
    excluded rather than made generic.
  - `SKKeyframeSequence` init/`sample`/`lerp` (`[Any]`/`NSNumberLike`/casts) and the
    `SKEmitterNode` `.sample` call sites guarded `#if !hasFeature(Embedded)` (the
    `.sks` particle editor is unused; sequences are always nil → identical behavior).
  - **Embedded blocker sites: 40 → 12.** All remaining are LIVE, cross-repo (P2.3).

**P2.3 — remaining 12 sites (live, cross-repo, needs game runtime verification):**
- `JSONValue` enum: `MiniJSON.parseJSON` (3) + `SKSceneLoader` build/helpers (6) +
  `UserDefaults` (2), with game `Levels.swift` switched off the enum. (`SKSceneLoader`'s
  `loadAssetText` is LIVE and already clean — only its `.sks` `build`/`readX` casts.)
- `CIFilter(name:parameters:)`: the game passes `[inputRadiusKey: 12.5]` (a
  `[String: Any]`) for the leaderboard blur — change to a typed `inputRadius:`
  parameter in framework `CIFilter` + game `LeaderboardPanel` call site.

**P2.3 — DONE & verified.** `JSONValue` enum landed; framework SpriteKit now has
**0 Embedded errors** (modulo `@MainActor`, which is P3).
- `MiniJSON.parseJSON` returns `JSONValue` (typed enum + `.stringValue`/`.arrayValue`/
  `.objectValue` accessors) instead of `Any`; parser rewritten, `MiniJSONNull` dropped.
- `SKSceneLoader` build/helpers consume `JSONValue` (`loadAssetText` unchanged).
- `UserDefaults` Foundation-mirror `Any` methods guarded `#if !hasFeature(Embedded)`.
- `CIFilter(name:parameters:)` `[String:Any]?` → `[String:Double]?` (game passes 12.5).
- Game `Levels.swift` switched to `parseJSON(text)?.objectValue` / `.arrayValue` /
  `.stringValue`; web `Package.swift` points at framework `embedded` branch.

Verification: framework normal wasm build green; full game wasm builds against the
embedded framework branch; the `JSONValue` parser reproduces `levels.json` exactly
(24/24 levels, 408 rows = 24×17, Level 1 = 37×17 with the tunnel top row).

**Status: every Layer-1/Layer-2 source blocker is resolved.** Only P3 remains.

## P3 — flip the flag (remaining)
- `@MainActor`: the framework targets use `.defaultIsolation(MainActor.self)`, which
  the Embedded stdlib doesn't vend. Need an Embedded build variant that drops the
  global-actor default (single-threaded wasm) — a Package/build-setting change, not
  source.
- ICU `String` ops (~10 symbols) — gate the few Unicode-heavy calls.
- Add an Embedded wasm build target (`wasm32-unknown-none-wasm`, `-wmo`,
  `-enable-experimental-feature Embedded`) and measure the size vs the 4.90 MB baseline.

When merging back: framework `embedded` → framework `main`, then flip the game's web
`Package.swift` dependency from `branch: "embedded"` back to `branch: "main"`.

## P3 results — first Embedded wasm + size, and the full-game scope

**Size (the payoff).** Built a real Embedded wasm: the whole Embedded-clean
SpriteKit framework + a scene/sprite/label reactor (`docs/embedded/build-embedded-wasm.sh`).

| Build | raw | gzip-9 |
|-------|-----|--------|
| Normal full-game wasm (baseline) | 4.90 MB | 1.80 MB |
| Embedded SpriteKit core (wasm-opt -Oz) | **60.3 KB** | **23.8 KB** |
| Embedded floor (trivial reactor) | 548 B | — |

The normal build's bulk is the Swift stdlib runtime + reflection metadata + ICU,
which Embedded drops entirely.

**All 10 framework modules are Embedded-clean.** Compiling SpriteKit + AppKit +
UIKit + GameKit + GameController + AVFoundation + Combine + SwiftUI + AudioToolbox
+ GameplayKit under Embedded produced 0 restriction errors (the lone diagnostic was
a cross-module `import` artifact of the single-WMO probe).

**Box2D (correction).** Box2D IS the physics engine and the game uses it heavily:
game `physicsBody` → `SKPhysics.swift` (31 `cb_*` calls) → C ABI in `KitABI.h` →
`Box2DBridge/cbox2d.cpp` + `box2d-src` (C++, `libcbox2d.a`). It is NOT an Embedded
blocker because the Swift↔Box2D boundary is a **plain C ABI** (Embedded Swift fully
supports calling C), and the C++ is compiled separately by clang and linked at the
wasm level exactly as in the normal build — Embedded Swift never sees the C++.

**Remaining for a full Embedded game build (P3 wrap):**
1. `@MainActor`: drop `.defaultIsolation(MainActor.self)` for the Embedded variant
   (single-threaded wasm). Build-setting/Package change, not source. 27 game annotations.
2. ICU `String` ops (~10 symbols) — gate the few Unicode-heavy calls.
3. Per-module Embedded build graph (emit each module's Embedded `.swiftmodule`, then
   the game) + link the clang-compiled C/C++ (`KitABI` shim, `libcbox2d.a`) — wired
   like the normal build but with the Embedded flag and `wasm32-unknown-none-wasm`.

## P3 — concurrency wall cleared; remaining is build-pipeline + game weak refs

**Concurrency is NOT a wall.** Embedded Swift 6.3.2 has no `@MainActor`/`Task`/
`async` (no `_Concurrency`), but almost all of the game's concurrency is
**macOS-gated** (`LeaderboardPanel`, `SoundManager+Speech`, `MainQueueCompat` — not
in the WASI build). The only WASI-compiled site was `WorkerController.flashColor`,
which has **zero callers** and whose `Task.sleep` never fired on wasm anyway — now
`#if !hasFeature(Embedded)`-guarded. So no concurrency *logic* migration is needed;
`@MainActor` is handled by dropping `.defaultIsolation(MainActor.self)` and stripping
the annotations in the Embedded build (build-time, single-threaded wasm).

**Full-game Embedded compile (combined-module probe of all 10 framework modules +
the 48 WASI game files).** After stripping `@MainActor`/imports: the only real
errors are the game's **38 `weak` refs** (`attribute 'weak' cannot be used`) — the
identical mechanical `#if hasFeature(Embedded)` → `unowned(unsafe)` guard the
framework Layer-1 used. Everything else was single-module-hack noise (`KeyCode`
member resolution that a real per-module build resolves). **No existentials, casts,
or other restriction errors in the game.**

**So: can the Embedded game run yet? Not yet — but every source blocker is now known
and bounded:**
1. Guard the game's 38 `weak` refs (mechanical, production-safe via `#if`).
2. Stand up the per-module Embedded build graph: emit each framework module's
   Embedded `.swiftmodule` in dependency order, compile the 48 game files + the
   `@_cdecl` boot/frame `main.swift` against them, with `@MainActor` stripped and
   `.defaultIsolation` dropped.
3. Link the clang-compiled C/C++ (`KitABI` shim, `libcbox2d.a` Box2D) + the Embedded
   Swift objects with `wasm-ld` (reactor model, export boot/frame), then `wasm-opt -Oz`.
4. Boot it in the runtime and compare size to the 4.90 MB / 1.80 MB baseline.

Steps 1 is mechanical; 2–4 are build-pipeline integration (no remaining source
unknowns). The 60.3 KB Embedded SpriteKit-core measurement already shows the
magnitude of the win.

## P3 — IT BOOTS. The full Embedded game runs in the browser.

The entire game + all 6 framework modules compile under Embedded Swift, link with
Box2D (C++) + the embedded stdlib + WASI libc/libc++, and **boot in the stock
runtime.js, rendering the title screen identically to the normal build** (fonts,
sprites, leaderboard, all of it). Reproduce: `docs/embedded/build-embedded-game.sh`.

What it took beyond the source fixes (all committed):
- Per-module Embedded build graph (each module → `.swiftmodule`, KitABI C module
  via `-Xcc -fmodule-map-file`), then the game module + `@_cdecl` boot/frame.
- `@MainActor` dropped at build time (single-threaded wasm) by preprocessing the
  sources (strip the attribute + the `{ @MainActor in` closure form) and building
  with raw swiftc (no SwiftPM `.defaultIsolation`).
- `os(WASI) || hasFeature(Embedded)` so the WASI code paths fire on the Embedded
  `wasm32-unknown-none-wasm` target (where `os` = none).
- One `@usableFromInline` (`SKNode.teardownPhysics`) for cross-module serialization.
- A tiny `embedded-stubs.c` (`superbox64-spritekit/embedded/`): `_initialize` →
  `__wasm_call_ctors` (C++ global ctors), locale-free `strtod`, and a
  `swift_conformsToProtocol` stub (class-bound `as?` → nil; title screen doesn't
  need it).
- Link the embedded `libswiftUnicodeDataTables.a`; export memory (not import it);
  Box2D compiled with `-ffunction-sections` + `--gc-sections` to drop the
  joints/ropes/fields the game never uses.

### Final size — the payoff
| Build | raw (wasm-opt -Oz) | gzip |
|-------|--------------------|------|
| Normal full game (baseline) | 4.90 MB | 1.80 MB |
| Embedded — Swift only (no Box2D) | 599 KB | 222 KB |
| Embedded — full Box2D | 1.62 MB | 521 KB |
| **Embedded — gc'd Box2D (only what's used)** | **0.76 MB** | **310 KB** |

**~6.4× smaller raw, ~5.8× smaller gzipped** — the entire Swift stdlib runtime,
reflection metadata, and ICU eliminated. The Embedded build's runtime is
`superbox64-wasmkit/runtime-embedded.js` (currently identical to stock — it boots
unmodified; reserved for Embedded-specific tweaks).
