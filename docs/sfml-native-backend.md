# Native Rendering Backends for SuperBox64 SpriteKit

## The goal

Today SuperBox64 SpriteKit has one rendering backend: Canvas 2D, delivered via WebAssembly. The game runs everywhere (web, Android, Windows, Linux, macOS WebView) through that single path.

The next architectural step is a second backend: CSFML (the C binding for SFML), giving native OpenGL rendering on Windows, Linux, and macOS without a WebView wrapper. The game source stays 100% identical Swift/SpriteKit. Only the framework grows a new renderer.

```
Game source (Swift/SpriteKit) — zero changes
    |
    v
SuperBox64 SpriteKit framework
    |-- Canvas 2D backend  -->  bossman.wasm  -->  Web + WebView wrappers
    \-- SFML backend       -->  native binary -->  Windows / Linux / macOS
```

---

## Why CSFML, not SFML directly

SFML is C++. Swift cannot call C++ directly (without a C bridge or Swift/C++ interop, which is still experimental for complex types). CSFML is the official C binding for SFML, callable from Swift via standard C interop with no friction. The project already uses this pattern: `Box2DBridge` wraps C++ Box2D behind a C interface (`cbox2d.cpp`) and Swift calls it directly. CSFML would be the same pattern applied to rendering.

---

## What already exists

- `boss-man-box2d-sfml-cpp/` is a complete, working C++ port of the game using SFML + Box2D. It is the reference implementation for every scene, every behavior, every visual. The SFML backend would port its rendering logic into the Swift framework rather than maintaining a separate C++ codebase.
- `Box2DBridge` (in `superbox64-wasmkit/spritekit/Sources/`) already proves C interop works for Box2D. The same bridge pattern applies to CSFML.
- The Canvas 2D backend (`superbox64-wasmkit/spritekit/`) defines the full SpriteKit API surface the game uses. That API is the contract the SFML backend must satisfy.

---

## Implementation plan

### Phase 1: CSFML Swift wrapper

Add CSFML as a system library target in `superbox64-wasmkit/spritekit/Package.swift` (or as a vendored source target). Create a thin Swift overlay (`SFMLKit`) that wraps:

- `sfRenderWindow` (window + event loop)
- `sfSprite` / `sfTexture` (sprite rendering)
- `sfRectangleShape` / `sfCircleShape` (shape nodes)
- `sfFont` / `sfText` (label nodes)
- `sfMusic` / `sfSound` / `sfSoundBuffer` (AVFoundation shim)
- `sfClock` (game loop timing)

This wrapper is small: CSFML's API is already close to what SpriteKit needs.

### Phase 2: SFML rendering backend

Add a compile-time backend switch. When building for WASM (`os(WASI)`), the existing Canvas 2D backend is used. When building natively for macOS/Windows/Linux, the SFML backend is compiled in.

Key SpriteKit types to implement against SFML:

| SpriteKit type | SFML equivalent |
|---|---|
| `SKSpriteNode` | `sfSprite` + `sfTexture` |
| `SKShapeNode` | `sfRectangleShape` / `sfConvexShape` |
| `SKLabelNode` | `sfText` + `sfFont` |
| `SKAction` | frame-delta accumulator, no SFML dependency |
| `SKScene.update()` | `sfRenderWindow` event + draw loop |
| `SKPhysicsBody` | already Box2D via `Box2DBridge` |

`SKAction` and the scene graph are pure Swift with no renderer dependency, so they require no changes.

### Phase 3: Platform targets

Add new executable targets in `boss-man-spritekit-web/Package.swift` (or a new `boss-man-spritekit-native/`) that link against the SFML backend instead of the WASM runtime:

```
BossManNative (macOS/Windows/Linux)
    depends on: SpriteKit (SFML backend), Box2DBridge, AVFoundation shim
```

Swift on Windows and Linux is already supported. The toolchain ships the Swift standard library as a runtime that can be bundled alongside the binary.

### Phase 4: CI

Mirror the existing WebView workflows with native workflows:

- `build-native-macos.yml`: `swift build --arch arm64 --arch x86_64`, codesign + notarize (reuse existing secrets)
- `build-native-windows.yml`: matrix x64/arm64, `swift build` on Windows runner
- `build-native-linux.yml`: matrix x86_64/arm64, `swift build` on Ubuntu runner, produce `.deb` + `.tar.gz`

Android stays on the WebView path. SFML's Android support is experimental; the WebView approach is more reliable there.

---

## What this retires

Once the SFML backend is complete and stable, `boss-man-box2d-sfml-cpp/` can be archived. All platform behavior lives in a single Swift source tree with two rendering paths, rather than two separate codebases in two languages.

---

## Tradeoffs vs the current WebView approach

| | WebView (current) | SFML native (future) |
|---|---|---|
| Distribution | WebView comes with OS | Swift runtime must ship |
| Rendering | Canvas 2D | OpenGL (SFML) |
| Audio latency | WebAudio | SFML Audio (low) |
| Fullscreen | JS bridge required | Native window API |
| Android | Works well | Experimental |
| Build complexity | One WASM output | Per-platform native binary |
| Startup time | JIT compile delay | Instant |
| Code size | ~12MB wasm | Smaller native binary |

The WebView wrappers remain the right answer for web and Android. SFML native is the upgrade path for Windows, Linux, and macOS when app-store quality and performance matter more than build simplicity.

---

---

## Alternative backends to consider

All of these share the same integration pattern: C API callable from Swift via standard C interop, compile-time backend switch, same game source untouched.

### SDL3 (strongest alternative to SFML)

SDL3 is the most actively maintained cross-platform layer. Its C API requires no bridge (unlike SFML which needs CSFML). Valve-backed, used in AAA Linux/Steam ports. The key advantage over SFML: **Android support is production-grade**, which is where SFML falls short. SDL3 also added a GPU API with Metal, Vulkan, and D3D12 backends, so rendering can go beyond OpenGL.

| | SFML/CSFML | SDL3 |
|---|---|---|
| API language | C (via CSFML bridge) | C (native) |
| Android | Experimental | Production |
| GPU API | OpenGL only | Metal / Vulkan / D3D12 / OpenGL |
| Audio | Built-in | SDL_mixer or SDL3 audio |
| Maintenance | Community | Valve-backed |
| Existing reference | `boss-man-box2d-sfml-cpp/` | None yet |

If Android native (non-WebView) ever becomes a goal, SDL3 is the better foundation than SFML.

### sokol (lightest option, unifies WASM too)

sokol is a set of single-header C libraries: `sokol_gfx` (GPU), `sokol_app` (window/input), `sokol_audio`. No build system, no dependencies — drop headers in and compile. The killer property for this project: **sokol has a WebGL/WebGPU backend**, so it could replace the Canvas 2D renderer in the WASM build too. One renderer for both native and web.

```
SuperBox64 SpriteKit
    |-- sokol backend  -->  Metal (macOS) / D3D11 (Windows) / OpenGL (Linux) / WebGL (WASM)
```

This would be the most ambitious unification but also the highest payoff: a single GPU-accelerated renderer across all targets, retiring Canvas 2D entirely.

Tradeoff: sokol is lower-level than SFML or SDL. Implementing SKSpriteNode, SKShapeNode, etc. requires writing more rendering code (vertex buffers, shaders) vs SFML's higher-level draw calls.

### Raylib (easiest to start with)

Raylib is a C API designed for simplicity. Single compilation unit, no external dependencies, supports Windows/Linux/macOS/Web/Android. The API maps almost 1:1 to what SpriteKit needs (DrawTexture, DrawRectangle, DrawText). Lowest implementation effort of any option here.

Tradeoff: less production-hardened than SDL3, WebAssembly support exists but is secondary. Good for prototyping a native backend before committing to SDL3 or sokol.

### Skia (overkill for a 2D game)

Google's 2D graphics library (Chrome, Flutter, Android). Extremely capable, Metal/Vulkan/OpenGL backends, perfect 2D rendering. But it is a heavy C++ dependency requiring a C bridge, large binary size, and complex build. Not the right fit here unless the game's visual demands grow significantly.

---

## Recommended path

1. **Now**: WebView wrappers (current). Covers all platforms, zero new renderer work.
2. **Next**: SFML backend for Windows + Linux native (the C++ port is the reference; `Box2DBridge` is the proven pattern).
3. **Later**: Evaluate SDL3 if Android native becomes a goal. Evaluate sokol if Canvas 2D performance becomes the bottleneck on web.

---

## Reference

- CSFML: https://www.sfml-dev.org/download/csfml/
- SDL3: https://wiki.libsdl.org/SDL3/FrontPage
- sokol: https://github.com/floooh/sokol
- Raylib: https://www.raylib.com
- `boss-man-box2d-sfml-cpp/` — working C++ reference implementation
- `superbox64-wasmkit/spritekit/` — Canvas 2D backend (the API contract to match)
- `Box2DBridge` — existing C interop pattern to follow
