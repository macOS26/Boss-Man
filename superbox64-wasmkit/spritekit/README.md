# SuperBox64 SpriteKit

An open source Swift reimplementation of Apple's SpriteKit framework, compiled to WebAssembly via WASI Preview 1. Drop `import SpriteKit` into an existing macOS/iOS SpriteKit game and it runs in any modern browser, wrapped in a native WebView on Windows, Linux, and Android, with zero changes to the game source.

No Emscripten. No loading screens. No watermarks. No branding you did not design.

**Live demo:** [boss-man.us/play](https://boss-man.us/play) — Boss-Man, a full arcade game running on this engine.

**Reference game:** [github.com/macOS26/Boss-Man](https://github.com/macOS26/Boss-Man)

---

## What It Provides

### SpriteKit (drop-in replacement)

| Class / Type | Notes |
|---|---|
| `SKScene` | Full scene lifecycle: `didMove(to:)`, `update(_:)`, `didFinishUpdate()`, `willMove(from:)` |
| `SKNode` | Full node tree: `addChild`, `removeFromParent`, `children`, `parent`, `name`, `zPosition`, `alpha`, `isHidden`, `xScale/yScale`, `zRotation`, `position`, `run(_:)` |
| `SKSpriteNode` | Texture, color, colorBlendFactor, anchorPoint, size, blending modes |
| `SKLabelNode` | fontName, fontSize, fontColor, text, horizontalAlignmentMode, verticalAlignmentMode, preferredMaxLayoutWidth |
| `SKShapeNode` | fillColor, strokeColor, lineWidth, path (CGPath), circular shorthand `.init(circleOfRadius:)`, rect `.init(rect:)` |
| `SKEmitterNode` | Particle emitter with position/velocity/lifetime/color range |
| `SKCameraNode` | Camera with position, scale, xScale/yScale |
| `SKCropNode` | Mask-based cropping via maskNode |
| `SKEffectNode` | Filter/blend offscreen layer |
| `SKAudioNode` | Positional audio node |
| `SKAction` | `moveBy`, `moveTo`, `scaleTo`, `scaleBy`, `fadeIn`, `fadeOut`, `fadeAlphaTo`, `rotate`, `sequence`, `group`, `repeatForever`, `wait`, `run`, `setTexture`, `colorize`, `customAction` |
| `SKTexture` | Image textures, color textures, `textureRect`, `size` |
| `SKView` | Canvas-backed view, `presentScene`, `texture(from:)`, `ignoresSiblingOrder` |
| `SKTransition` | `fade`, `crossFade`, `doorsOpenHorizontal`, `push`, `reveal`, `moveIn` |
| `SKPhysicsBody` | `dynamic`, `categoryBitMask`, `contactTestBitMask`, `collisionBitMask`, `velocity`, `applyImpulse`, `isDynamic`, `affectedByGravity` |
| `SKPhysicsWorld` | `gravity`, `contactDelegate`, `enumerateBodies(inRect:)` |
| `SKPhysicsContact` | `bodyA`, `bodyB`, `contactPoint`, `collisionImpulse` |
| `SKConstraint` | Position and orientation constraints |
| `SKKeyframeSequence` | Keyframe-driven value interpolation |
| `SKWarpGeometry` | Mesh warp deformation |
| `SKColor` | Full RGBA color type, `.systemRed/Blue/Yellow/...` matching macOS light-mode palette |
| `CGPoint / CGSize / CGRect / CGVector` | Full geometry types |
| `CGPath / CGMutablePath` | Path construction (addLine, addArc, addCurve, closeSubpath) |
| `CGAffineTransform` | Matrix transforms |

### Platform Shims (drop-in, zero `#if` in game code)

| Module | What it shims |
|---|---|
| `AppKit` | `NSColor`, `NSFont`, `NSImage`, `NSEvent`, `NSWindow`, `NSScreen`, `NSApplication`, `NSViewController` |
| `UIKit` | `UIColor`, `UIFont`, `UIImage`, `UIViewController`, `UIScreen`, `UIDevice`, `UIApplication` |
| `Cocoa` | Re-exports AppKit + Foundation essentials |
| `GameKit` | `GKLocalPlayer`, `GKLeaderboard`, `GKScore`, `GKAchievement`, `GKGameCenterViewController` |
| `GameplayKit` | `GKRandomDistribution`, `GKShuffledDistribution`, `GKGaussianDistribution`, `GKRandomSource`, `GKMersenneTwisterRandomSource` |
| `GameController` | `GCController`, `GCExtendedGamepad`, `GCControllerDirectionPad`, `GCControllerButtonInput` |
| `AVFoundation` | `AVAudioPlayer`, `AVSpeechSynthesizer`, `AVSpeechUtterance` |
| `AudioToolbox` | `AudioServicesPlaySystemSound` |
| `Combine` | `PassthroughSubject`, `CurrentValueSubject`, `AnyCancellable` |
| `SwiftUI` | `Color`, `View` stubs for games that import but do not use SwiftUI |

### Physics (Box2D 2.4.1)

Physics is provided by Box2D 2.4.1 via `Box2DBridge` (the "Box" in SuperBox64). Bodies, fixtures, joints, contacts, and raycasts map directly to `SKPhysicsBody` / `SKPhysicsWorld`.

### KitABI

The C ABI that sits between the Swift game and the JavaScript runtime (`runtime.js`). Every drawing, audio, input, and asset call crosses this boundary. Games never call KitABI directly — it is consumed by the SpriteKit layer.

---

## How It Works

The package vends a module literally named `SpriteKit`. When you build for WASM:

```swift
// This import binds to SuperBox64 SpriteKit, not Apple's, with zero source changes
import SpriteKit
```

On macOS/iOS, `import SpriteKit` resolves to Apple's framework as normal. On WASM, it resolves to this package. The same Swift source compiles both ways.

The WASM binary is a WASI Preview 1 reactor exporting `_initialize`, `boot()`, and `frame(dtMs)`. The JavaScript runtime (`superbox64-wasmkit`) drives the game loop via `requestAnimationFrame`, implements graphics on Canvas2D, audio on Web Audio, input on DOM events + Web Gamepad API, and persistence on localStorage.

---

## Adding to a Game

```swift
// Package.swift
.package(url: "https://github.com/macOS26/superbox64-spritekit", branch: "main"),

// Target dependencies
.product(name: "SpriteKit", package: "superbox64-spritekit"),
.product(name: "AppKit",    package: "superbox64-spritekit"),
// ...add whichever shims the game imports
```

---

## Requirements

- Swift 6.3.2+ toolchain from swift.org
- `swift-6.3.2-RELEASE_wasm` SDK (from swift.org)
- `xcrun --toolchain swift swift build --swift-sdk swift-6.3.2-RELEASE_wasm -c release`

---

## Related

- [superbox64-wasmkit](https://github.com/macOS26/superbox64-wasmkit) — the JavaScript runtime that loads and runs the WASM binary
- [Boss-Man](https://github.com/macOS26/Boss-Man) — the arcade game built with this engine, shipping on 6 platforms from one Swift source
