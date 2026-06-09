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

## Blocker inventory (ranked by effort), framework first

| # | Blocker | Where | Scale | Effort |
|---|---------|-------|-------|--------|
| 1 | `open` SKNode class hierarchy + polymorphic `[SKNode]` + `override` dispatch | framework `SpriteKit` | ~29 open classes, 94 overrides | **Showstopper** |
| 2 | Dynamic `as?`/`as!` casts (node subtype dispatch, scene loader, keyframe lerp) | framework 59, game 18 | 77 sites | High |
| 3 | `AnyObject` delegate protocols | framework 3 (`SKPhysicsContactDelegate`, `SKActionTarget`, `SKTouchResponder`), game 8 (`BossControllerDelegate`, `WorkerControllerDelegate`, …) | 11 protocols | High |
| 4 | `[Any]` / `userData: [String:Any]` existential containers | framework (`SKKeyframeSequence.values`, `SKNode.userData`, MiniJSON), game (`Levels.swift`) | ~13 | Medium-High |
| 5 | `@MainActor` global actor | game (pervasive) + framework | 8+ in pure logic | Low (gate/strip) |
| 6 | ObjC interop (`NSObject`, `@objc`, `#selector`, `required init?(coder:)`) | macOS app layer + 7 SKNode `init?(coder:)` stubs | ~28 | Low for WASM (mostly macOS-gated; coder stubs can drop) |
| 7 | stdlib `String` → ICU | game `String` ops | ~10 symbols | Low-Medium (gate Unicode-heavy ops) |

Reflection (`Mirror`/`dump`) and `type(of:)`: **none found** — good.

## Recommended path (incremental, keeps the shipping game green)

- **P0 (done):** this probe + map. The game-logic slice compiles Embedded.
- **P1 — framework feasibility spike:** compile `superbox64-spritekit/Sources/SpriteKit`
  under the Embedded flag in isolation to enumerate the real per-symbol errors of
  blockers #1–#4 (the survey predicts them; the spike makes them concrete and
  countable). No behavior change.
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
The static survey estimated 3–6 months for a full framework rewrite. The probe
narrows the *game-side* risk to near zero and localizes the work to the framework
hierarchy. P1–P2 are the real cost and should be done in `superbox64-spritekit`,
verified continuously against the live web build so nothing regresses.
