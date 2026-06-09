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

Next decision: proceed to **P2** and start fixing Layer 1 (`weak`→`unowned`, 8
sites) then Layer 2 (the `JSONValue` enum across MiniJSON/SKSceneLoader/
UserDefaults), each landing on the normal build first and verified identical.
