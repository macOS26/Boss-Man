# SuperBox64 SpriteKit

**An open reimplementation of Apple's SpriteKit, in Swift, that runs in the
browser as WebAssembly.**

It provides the SpriteKit API — `SKScene`, `SKNode`, `SKSpriteNode`,
`SKLabelNode`, `SKShapeNode`, `SKAction`, `SKPhysicsBody`/`SKPhysicsWorld`, etc. —
implemented from scratch on the [`wasm-web-kit`](../README.md) runtime (Canvas2D +
WebAudio + DOM input), with physics driven by **Box2D** compiled to the same wasm
module. The package is branded *SuperBox64 SpriteKit* but vends a module named
`SpriteKit`, so a game's `import SpriteKit` resolves here **unchanged** — it's
drop-in.

## Why is this needed for WebAssembly?

Apple's SpriteKit is a **closed-source, Apple-only** framework — it's built on
Metal, Core Animation, and the Objective-C runtime, and ships only inside iOS /
macOS / tvOS. It **cannot compile to, or run on, WebAssembly**: there is no
`import SpriteKit` off Apple platforms, and you can't ship Apple's binary to a
browser.

But the *language* travels fine: Swift compiles to `wasm32-wasip1` (via the
swift.org WebAssembly SDK, no Emscripten). So to run a Swift/SpriteKit game on the
web, the only missing piece is **SpriteKit itself** — the scene graph, the action
system, and the physics. SuperBox64 SpriteKit *is* that missing piece: a web-native
reimplementation that `import SpriteKit` binds to instead of Apple's framework.

It also supplies the physics engine Apple's SpriteKit otherwise hides. SpriteKit's
`SKPhysicsBody` is internally a **fork of Box2D**; on web there is no bundled
engine, so we link **Box2D-to-wasm** behind `SKPhysicsWorld` — the same engine,
brought in explicitly (the "Box" in *SuperBox64*) so bodies, collisions, and
`didBegin` contacts behave like they do on a Mac.

Net: `import SpriteKit` + Swift→wasm + SuperBox64 SpriteKit + Box2D = a SpriteKit
game running in a browser tab, no Emscripten, no Apple frameworks.

> Reference/demo: [`../../boss-man-spritekit-web`](../../boss-man-spritekit-web) —
> an interactive scene (arrow-key player, SKActions, a Box2D physics pile). It does
> **not** modify the original `boss-man-spritekit-swift` project.

## What's implemented

| Area | Types / API |
|---|---|
| Geometry | `CGFloat` (Double), `CGPoint`, `CGSize`, `CGRect`, `CGVector` (+ operators) |
| Color | `SKColor` (rgba, palette, `withAlphaComponent`) |
| Scene graph | `SKNode` (position, zPosition, xScale/yScale, zRotation, alpha, name, children, `addChild`/`removeFromParent`, `childNode(withName:)`), `SKScene` (size, backgroundColor, anchorPoint, `didMove`, `update`, `didSimulatePhysics`), `SKView` (`presentScene`, frame loop) |
| Nodes | `SKSpriteNode` (color/texture/anchorPoint), `SKLabelNode` (text, fontSize, fontColor, alignment modes), `SKShapeNode` (rect/circle/path + `CGPath`), `SKTexture`, `SKEffectNode`/`SKCropNode` (pass-through) |
| Actions | `SKAction`: moveBy/moveTo(x/y), scale(to/by), fadeAlpha/In/Out, rotate(by/to), wait, run, customAction, **sequence/group/repeat/repeatForever**, removeFromParent, timing modes, `run(_:completion:)`, `playSoundFileNamed` |
| Physics | `SKPhysicsBody` (rectangle/circle/edgeLoop, category/contactTest/collision masks, velocity, isDynamic), `SKPhysicsWorld` (gravity, contactDelegate), `SKPhysicsContact`, `SKPhysicsContactDelegate.didBegin` — all on Box2D |
| Input | `SKKey` codes + `skKeyIsDown(_:)`; `SKScene.keyDown/keyUp/mouseDown/mouseUp/mouseMoved` dispatched by `SKView` from the kit's event queue |

## Rendering model

The scene renders in SpriteKit's world space (origin bottom-left, **y-up**). `SKView`
flips that onto the Canvas y-down surface once at the root (`translate(0,H); scale(1,-1)`);
text and images are locally re-flipped so they aren't mirrored. Each node applies
`translate → rotate → scale` and an inherited alpha, then draws via the kit ABI
(`gfx_fill_rect`/`gfx_fill_circle`/`gfx_stroke_*`/`gfx_fill_poly`/`gfx_draw_text`/
`gfx_draw_image`). Children render sorted by `zPosition`.

## Physics model

`SKView.tick` each frame: poll input → run actions → `scene.update` →
`physicsWorld.step` → render. `step` pushes any game-set velocities into Box2D
(`cb_set_velocity`), advances the world (`cb_step`), syncs each dynamic body's
position/rotation back to its `SKNode`, and routes Box2D `BeginContact` through
`categoryBitMask`/`contactTestBitMask` to `didBegin`. Bodies are created lazily
from `node.physicsBody`. SpriteKit points are used directly as Box2D meters.

The Box2D C shim is [`boss-man-spritekit-web/native/cbox2d.cpp`](../../boss-man-spritekit-web/native/cbox2d.cpp),
built into `libcbox2d.a` with the **Swift toolchain's clang against the WASM SDK
sysroot** (one libc++, clean link) and passed to the Swift link via `-Xlinker`.

## Building a game with it

```swift
// Package.swift
dependencies: [ .package(path: "../wasm-web-kit/spritekit") ],
targets: [ .executableTarget(name: "Game",
    dependencies: [ .product(name: "SpriteKit", package: "spritekit") ],
    linkerSettings: [ .unsafeFlags([
        "-Xclang-linker","-mexec-model=reactor",
        "-Xlinker","--export=boot","-Xlinker","--export=frame",
        "-Xlinker","--export-if-defined=_initialize","-Xlinker","--allow-undefined",
        "-Xlinker","<abs>/libcbox2d.a",   // if using physics
    ])]) ]
```
```swift
// the game exports boot/frame; SKView drives the rest
nonisolated(unsafe) var view: SKView?
@_cdecl("boot")  func boot()            { let v = SKView(); v.presentScene(MyScene(size: .init(width:1184,height:666))); view = v }
@_cdecl("frame") func frame(_ ms: Double) { view?.tick(ms) }
```
Build + serve:
```
swift build --swift-sdk swift-6.3.2-RELEASE_wasm -c release
# copy .build/wasm32-unknown-wasip1/release/Game.wasm -> web/, add index.html (window.WASMWEB) + runtime.js
python3 -m http.server 8080   # from a dir that can reach runtime.js
```

## Limits / not yet done

- **Not a full SpriteKit.** Implemented is the 2D subset games commonly use.
  Missing/stubbed: `SKTileMapNode`/`SKTileSet`, `SKEmitterNode`, real `SKEffectNode`
  filters, `SKCropNode` masking, `reversed()` (best-effort), `convert` (translation
  only), most `SKAction` timing curves beyond ease in/out.
- **Porting a real macOS/iOS SpriteKit game also needs non-SpriteKit shims**: the
  app entry (`@main`/`NSApplication`/`SKView` in a window), `AppKit`/`UIKit`,
  `GameKit` (Game Center), `AVFoundation`, `GameController`. Those are separate
  compat shims, not part of this layer.
- `CGFloat` is `Double`; `sf::`-style assumptions don't apply here.
- Coordinate `convert`/rotation edge cases are approximate.

## Gotcha: globals in a reactor module

Top-level `let`/`var` *with initializers* in the executable's `main.swift` are run
by `main()`, which a **WASI reactor never calls** — so they stay uninitialized and
trap on access. Put game constants in `static let` (lazily initialized, like
`SKColor.black`) or build them in a function. A zero-initialized `var x: T? = nil`
global is fine.
