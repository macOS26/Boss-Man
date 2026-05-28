# SuperBox64 SpriteKit

**An open reimplementation of Apple's SpriteKit, in Swift, that runs in the
browser as WebAssembly.**

It provides the SpriteKit API — `SKScene`, `SKNode`, `SKSpriteNode`,
`SKLabelNode`, `SKShapeNode`, `SKAction`, `SKPhysicsBody`/`SKPhysicsWorld`, etc. —
implemented from scratch on the [`wasm-web-kit`](../README.md) runtime (Canvas2D +
WebAudio + DOM input), with physics driven by **Box2D** compiled into the same
SwiftPM package. The package is branded *SuperBox64 SpriteKit* but vends a
module named `SpriteKit`, so a game's `import SpriteKit` resolves here
**unchanged** — it's drop-in.

It also ships drop-in shims for `AppKit`, `UIKit`, `Cocoa`, `GameKit`,
`GameplayKit`, `GameController`, `AVFoundation`, and `AudioToolbox`, so a
Swift game written for macOS or iOS compiles to wasm with no source edits at
the import site.

## Why is this needed for WebAssembly?

Apple's SpriteKit is a **closed-source, Apple-only** framework — it's built on
Metal, Core Animation, and the Objective-C runtime, and ships only inside iOS /
macOS / tvOS. It **cannot compile to, or run on, WebAssembly**: there is no
`import SpriteKit` off Apple platforms, and you can't ship Apple's binary to a
browser.

But the *language* travels fine: Swift compiles to `wasm32-wasip1` (via the
swift.org WebAssembly SDK, no Emscripten). So to run a Swift/SpriteKit game on
the web, the missing pieces are **SpriteKit itself** and the Apple platform
frameworks the game touches. SuperBox64 SpriteKit *is* those missing pieces —
a web-native reimplementation that `import SpriteKit` (and friends) bind to
instead of Apple's frameworks.

It also supplies the physics engine Apple's SpriteKit otherwise hides.
SpriteKit's `SKPhysicsBody` is internally a **fork of Box2D**; on web there is
no bundled engine, so the package bundles **Box2D 2.4.1** behind
`SKPhysicsWorld` — the same engine, brought in explicitly (the "Box" in
*SuperBox64*) so bodies, collisions, and `didBegin` contacts behave like they
do on a Mac.

Net: `import SpriteKit` + Swift → wasm + SuperBox64 SpriteKit + Box2D = a
SpriteKit game running in a browser tab. No Emscripten, no Apple frameworks.

> Reference/demo: [`../../boss-man-spritekit-web`](../../boss-man-spritekit-web)
> — an interactive scene (arrow-key player, SKActions, a Box2D physics pile).
> It does **not** modify the original `boss-man-spritekit-swift` project.

## Modules

The package vends one product per Apple framework. Pick the modules your
game imports:

| Product          | Use when the game imports...                                |
|------------------|-------------------------------------------------------------|
| `SpriteKit`      | always                                                      |
| `Box2DBridge`    | always (links the C++ physics engine)                       |
| `AppKit`         | macOS games (NSColor / NSImage / NSFont / NSBezierPath / NSEvent) |
| `UIKit`          | iOS games (UIViewController / UITouch / UIScreen / UIGesture\*) |
| `Cocoa`          | macOS games doing `import Cocoa` (re-exports AppKit)        |
| `GameController` | gamepad / USB arcade joystick (GCController / GCExtendedGamepad) |
| `GameKit`        | Game Center calls (silent local stub; success callbacks fire) |
| `GameplayKit`    | imports of GameplayKit (GKRandom, GKEntity / GKComponent)   |
| `AVFoundation`   | AVAudioPlayer / AVAudioEngine / AVSpeechSynthesizer         |
| `AudioToolbox`   | AudioServicesPlayAlertSound (vibration; no-op on web)       |
| `KitABI`         | raw C ABI to the JS runtime (advanced)                      |

## What's implemented

| Area          | Types / API                                                                                                                                  |
|---------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| Geometry      | `CGFloat` (Double), `CGPoint`, `CGSize`, `CGRect`, `CGVector` (+ operators)                                                                  |
| Path          | `CGPath` / `CGMutablePath` (move/line/rect/ellipse/arc/close), arc-length sampling                                                           |
| Color         | `SKColor` (rgba, palette, hsba)                                                                                                              |
| Scene graph   | `SKNode` (position, zPosition, xScale/yScale, zRotation, alpha, speed, isPaused, constraints, enumerateChildNodes), `SKScene` (size, backgroundColor, anchorPoint, **camera**, full lifecycle hooks: sceneDidLoad/didMove/willMove/didChangeSize/update/didEvaluateActions/didSimulatePhysics/didApplyConstraints/didFinishUpdate), `SKView` (presentScene + transition overload, debug overlays as no-ops) |
| Nodes         | `SKSpriteNode`, `SKLabelNode` (numberOfLines, preferredMaxLayoutWidth, alignment modes), `SKShapeNode` (rect/circle/path), `SKTexture`, `SKTextureAtlas`, `SKEmitterNode`, `SKCameraNode` (visibleRect/contains), `SKAudioNode` (autoplayLooped/volume/play/stop), `SKVideoNode`, **`SKReferenceNode` / `SKTileMapNode` / `SKTileSet` / `SKTileGroup` / `SKEffectNode` / `SKCropNode` / `SKShader` / `SKUniform` / `SKAttribute` / `SKFieldNode` / `SKLightNode` / `SKRegion`** (compile-and-render stubs) |
| Actions       | `SKAction`: moveBy/moveTo(x/y), scale(to/by), fadeAlpha/In/Out, rotate(by/to), wait, run, **customAction**, sequence/group/repeat/repeatForever, removeFromParent, **setTexture**, **animate(with:textures:timePerFrame:resize:restore:)**, **changeVolume**, **resize(to/by)**, **follow(_:asOffset:orientToPath:duration:)** (CGPath arc-length sampling), **colorize(with:colorBlendFactor:duration:)**, **playSoundFileNamed**, **reversed()** (real for moveBy/rotateBy/scaleBy/sequence/group/repeat); timing modes (linear/easeIn/easeOut/easeInEaseOut) |
| Physics       | `SKPhysicsBody` (rectangle/circle/edgeLoop, category/contactTest/collision masks, velocity, isDynamic, isSensor, allowsRotation, density/charge/pinned/usesPreciseCollisionDetection/fieldBitMask), `SKPhysicsWorld` (gravity, contactDelegate, speed), `SKPhysicsContact`, `SKPhysicsContactDelegate.didBegin` — all on **Box2D 2.4.1** bundled in `Box2DBridge` |
| Input         | `SKKey` codes + `skKeyIsDown(_:)`; `SKScene.keyDown/keyUp/mouseDown/mouseUp/mouseMoved` dispatched by `SKView` from the kit's event queue    |
| Gamepad       | **Full Web Gamepad API**: 4 controllers, USB arcade sticks register as standard gamepads. By default d-pad/left stick edges synthesize Arrow keydown/keyup; A→Space, Start→P, so games written for the keyboard auto-bind to a controller. `GameController` module re-skins this as `GCController`/`GCExtendedGamepad` with `valueChangedHandler` / `pressedChangedHandler`. |
| Text-to-speech | Web Speech API; `AVSpeechSynthesizer.speak()` routes through `tts_speak`. |

## Building a game with it

```swift
// Package.swift
// swift-tools-version:6.0
import PackageDescription
let package = Package(
    name: "MyGame",
    dependencies: [
        .package(url: "https://github.com/your-org/SuperBox64SpriteKit.git", from: "0.1.0"),
        // or .package(path: "../wasm-web-kit/spritekit") for local
    ],
    targets: [
        .executableTarget(
            name: "Game",
            dependencies: [
                .product(name: "SpriteKit",      package: "SuperBox64SpriteKit"),
                .product(name: "Box2DBridge",    package: "SuperBox64SpriteKit"),  // physics
                .product(name: "AppKit",         package: "SuperBox64SpriteKit"),  // if needed
                .product(name: "GameController", package: "SuperBox64SpriteKit"),  // if needed
                .product(name: "AVFoundation",   package: "SuperBox64SpriteKit"),  // if needed
            ],
            linkerSettings: [.unsafeFlags([
                "-Xclang-linker","-mexec-model=reactor",
                "-Xlinker","--export=boot","-Xlinker","--export=frame",
                "-Xlinker","--export-if-defined=_initialize","-Xlinker","--allow-undefined",
            ])]
        )
    ]
)
```

```swift
// Game entrypoint (exports boot/frame; SKView drives the rest)
import SpriteKit
nonisolated(unsafe) var view: SKView?
@_cdecl("boot")  public func boot()           { let v = SKView(); v.presentScene(MyScene(size: .init(width: 1184, height: 666))); view = v }
@_cdecl("frame") public func frame(_ ms: Double) { view?.tick(ms) }
```

Build + serve:

```sh
# One-time: install the swift.org wasm SDK
swift sdk install \
  https://download.swift.org/swift-6.3.2-release/wasm/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum <published-checksum>

# Build
TOOLCHAINS=org.swift.6.3.2-release \
  xcrun --toolchain swift swift build --swift-sdk swift-6.3.2-RELEASE_wasm -c release

# Wire up web/
cp .build/wasm32-unknown-wasip1/release/Game.wasm web/game.wasm
cp ../wasm-web-kit/runtime.js web/
# add web/index.html with window.WASMWEB = { wasmUrl: 'game.wasm', assetRoot: 'assets', ... }

# Serve
python3 -m http.server 8080
```

## Rendering model

The scene renders in SpriteKit's world space (origin bottom-left, **y-up**).
`SKView` flips that onto the Canvas y-down surface once at the root
(`translate(0,H); scale(1,-1)`); text and images are locally re-flipped so
they aren't mirrored. If `scene.camera` is set, `SKView` applies the camera's
inverse before rendering the tree, so camera children act as UI overlays
riding along.

Each node applies `translate → rotate → scale` and an inherited alpha, then
draws via the kit ABI (`gfx_fill_rect`/`gfx_fill_circle`/`gfx_stroke_*`/
`gfx_fill_poly`/`gfx_draw_text`/`gfx_draw_image`). Children render sorted by
`zPosition`.

## Physics model

`SKView.tick` each frame: poll input → poll gamepads → run actions →
`scene.update` → `physicsWorld.step` → render. `step` pushes any game-set
velocities into Box2D (`cb_set_velocity`), advances the world (`cb_step`),
syncs each dynamic body's position/rotation back to its `SKNode`, and routes
Box2D `BeginContact` through `categoryBitMask`/`contactTestBitMask` to
`didBegin`. Bodies are created lazily from `node.physicsBody`. SpriteKit
points are used directly as Box2D meters.

## Gamepad / USB arcade joystick

Out of the box, every connected gamepad (Xbox/PlayStation/Switch via
Bluetooth or USB, plus USB arcade joysticks that register as standard
gamepads) emits **synthetic arrow-key / Space / P events**, so a game
written for the keyboard "just works" with a controller — no game-side code
change. Disable with `gp_map_to_keys(0)` if you want raw access via the
`GameController` module's `GCController.extendedGamepad` callbacks.

## Limits / not yet done

- **Not a full SpriteKit.** `SKTileMapNode`, `SKFieldNode`, `SKLightNode`,
  `SKShader`, `SKEffectNode`, `SKCropNode`, `SKConstraint orientToPoint`,
  `SKReferenceNode`, and `SKVideoNode` compile and accept their properties
  but skip the actual visual/physics effect (Canvas2D has no GLSL pipeline,
  no offscreen render target, no Box2D force fields).
- `.sks` scene-file parsing isn't implemented, so `SKScene(fileNamed:)` and
  `SKReferenceNode(fileNamed:)` return empty nodes. Build your scene tree in
  code or via a parallel JSON loader.
- `GameKit` / Game Center is a silent local stub: posting succeeds, queries
  return empty, authentication completes unauthenticated.
- `AVAudioEngine` compiles but doesn't play through the engine graph — use
  `AVAudioPlayer` (or `SKAction.playSoundFileNamed`) for sound.

## Gotcha: globals in a reactor module

Top-level `let`/`var` *with initializers* in the executable's `main.swift`
are run by `main()`, which a **WASI reactor never calls** — so they stay
uninitialized and trap on access. Put game constants in `static let`
(lazily initialized, like `SKColor.black`) or build them in a function. A
zero-initialized `var x: T? = nil` global is fine.
