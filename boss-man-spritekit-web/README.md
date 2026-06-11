# Boss-Man · SpriteKit edition on WebAssembly

The macOS [Boss-Man](../boss-man-spritekit-swift) SpriteKit game compiled to
WebAssembly via [SuperBox64 SpriteKit](https://github.com/SuperBox64/SuperBox64Kit),
Apple's SpriteKit reimplemented in Swift, no Emscripten, no Apple frameworks.
The game's `import SpriteKit` lines work unchanged here because SuperBox64
SpriteKit vends a module named `SpriteKit` that the Swift compiler binds to
in place of Apple's framework. The runtime (Canvas2D renderer, Web Audio mixer,
DOM input, asset preloader) ships from
[WasmKit](https://github.com/SuperBox64/WasmKit).

The same Swift source drives the macOS app and this wasm build; the platform
differences (boot/frame lifecycle, `localStorage` persistence, SF key codes)
live in the framework, not the game.

## What is SuperBox64 SpriteKit

[SuperBox64 SpriteKit](https://github.com/SuperBox64/SuperBox64Kit) is a
Swift reimplementation of Apple's SpriteKit that compiles to WebAssembly. A
macOS or iOS SpriteKit game adds the package, keeps every `import SpriteKit`
(and `AppKit`, `UIKit`, `GameKit`, `GameController`, `AVFoundation`,
`GameplayKit`, `Combine`, `SwiftUI`) line unchanged, and runs in any modern
browser. No Emscripten, no loading screens, no watermarks. Physics is Box2D
v3 behind Apple's `SKPhysicsBody` API; rendering, audio and input flow
through a 101-function C ABI to the
[WasmKit](https://github.com/SuperBox64/WasmKit) runtime.
The goal: 100% common game source, every platform difference pushed down into
the framework instead of forked into the game.

## Why we dropped C++ (SFML 2.6 + Box2D 2.4)

Boss-Man's first cross-platform edition was a hand-written C++ port: SFML 2.6
for windowing/rendering/audio, Box2D 2.4 for physics, built natively for
macOS, Windows and Linux (it lives on in the `legacy-cpp` branch as
`boss-man-box2d-sfml-cpp`). It worked, but it meant maintaining **two
games**: every feature, level tweak and bug fix shipped twice, once in the
Swift master and again as a C++ translation, and the port always trailed.

The replacement splits the job by what each platform does best:

- **Apple platforms get the real thing**: the native SpriteKit + Swift app
  (Metal rendering, Game Center, TestFlight), which is also the master
  source of truth for all behavior.
- **Everywhere else (and even the Mac again) gets the same source**:
  SuperBox64 SpriteKit + WasmKit compile the unmodified Swift game to one
  866 KB Embedded wasm that runs in any browser and ships as WebView apps
  for macOS, Windows, Linux and Android.

What that bought:

- **One codebase.** The C++ port is retired, not because C++ was slow, but
  because a second implementation of the same game is a permanent tax. Fixes
  land once and ship everywhere.
- **The port can't drift.** The wasm builds compile the master's files
  directly; there is nothing to forget to translate.
- **Per-platform native quirks vanished.** SFML windowing, audio backends,
  and per-OS packaging gave way to one browser runtime plus thin WebView
  shells; the binary the Mac, Windows, Linux and Android apps run is
  byte-identical.
- **The size argument died with Embedded Swift.** The honest C++ advantage
  was binary size; at 866 KB (344 KB gzipped) the Embedded wasm is in native
  C++ territory.
- **Physics stayed in the family**: Box2D 2.4 C++ was frozen upstream; the
  framework now vendors Box2D v3, pure C, called directly from Swift.

## Build

```sh
./build.sh                  # debug   → web/bossman.wasm
./build.sh release          # release → web/bossman.wasm (wasm-opt -Oz)
```

`build.sh`:

1. Uses the [WasmKit](https://github.com/SuperBox64/WasmKit)
   sibling checkout at `../../WasmKit` (its own repo, next to this
   one), cloning it there if not already present.
2. Runs `swift build` with `TOOLCHAINS=org.swift.6.3.2-release` and
   `xcrun --toolchain swift` so SwiftPM picks the swift.org clang the WASI SDK
   was built against (Xcode's bundled clang has no wasm backend). The
   SuperBox64Kit dependency is fetched from GitHub by SwiftPM.
3. Optimizes the release binary with `wasm-opt -Oz` into `web/bossman.wasm`.
4. Sources the kit's `build.sh` and calls `wasmweb_manifest` to regenerate
   `web/manifest.json` from `web/assets`.
5. Copies the kit's `runtime.js` into `web/`.

## Build sizes

Physics is Box2D v3 (pure C, vendored in SuperBox64Kit as `CBox2D`,
called directly from Swift, no C++ in any link). Box2D compiles with
function/data sections so `--gc-sections` keeps only the physics the game
calls, and with `-DNDEBUG` so its assert machinery and message strings drop
out of the shipped wasm:

| Build | Before `-DNDEBUG` | With `-DNDEBUG` | Saved |
|---|---|---|---|
| Normal wasm (`build.sh release`) | 4,431,558 | **4,385,075** | 45 KB |
| Embedded Swift wasm (`docs/embedded/build-embedded-game.sh`) | 917,088 | **865,854** (344 KB gz) | 51 KB |

Both builds were verified by scripted gameplay (same input run produces the
identical score on the normal and Embedded wasm).

## What ships at boss-man.us

The website serves the Embedded Swift wasm (865,854 bytes, ~6x smaller than
the 4.9 MB pre-Embedded build) plus the minified runtime
(`runtime-embedded-min.js`, 42 KB), loaded directly in the homepage iframe.
The current deploy (v56) brings:

- Box2D v3 physics, pure C, with no C++ or libc++ anywhere in the binary
- full 32-bit physics category/collision masks (earlier builds truncated
  them to 16 bits)
- the traveler walk-animation fix (Embedded has no runtime
  protocol-conformance lookup, so an `as? Protocol` cast silently returned
  nil and the leg animation never ran; the cast is now a concrete class
  downcast)
- Box2D built with `-DNDEBUG`, so its assert machinery and message strings
  are gone

### Memory footprint (macOS WebView app, pre-1.0.8-embedded)

Activity Monitor on the notarized Boss-Man-wk.app running the Embedded wasm,
at launch and again during gameplay:

| Process | At launch | In game |
|---|---|---|
| bossman://app (WKWebView content) | 168.1 MB | 233.8 MB |
| Graphics and Media | 90.4 MB | 114.1 MB |
| Host app | 26.1 MB | 26.0 MB |
| Networking | 6.0 MB | 5.9 MB |
| **Total** | **~290 MB** | **~380 MB** |

## Compiling the Swift wasm from scratch

The wasm needs the swift.org toolchain (Xcode's clang has no wasm backend),
the wasm Swift SDK, and Binaryen's `wasm-opt`.

### macOS

```sh
# 1. Toolchain + wasm SDK + Binaryen
curl -fLO https://download.swift.org/swift-6.3.2-release/xcode/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE-osx.pkg
installer -pkg swift-6.3.2-RELEASE-osx.pkg -target CurrentUserHomeDirectory
TOOLCHAINS=org.swift.6.3.2-release xcrun --toolchain swift swift sdk install \
  https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz
brew install binaryen

# 2. Build (the helper wraps the raw command below)
cd boss-man-spritekit-web && ./build.sh release
```

### Linux

`build.sh` is macOS-only (`xcrun`); on Linux run the raw commands.

```sh
# 1. Toolchain via swiftly (or the swift.org tarball) + wasm SDK + Binaryen
swiftly install 6.3.2 && swiftly use 6.3.2
swift sdk install \
  https://download.swift.org/swift-6.3.2-release/wasm-sdk/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE_wasm.artifactbundle.tar.gz
sudo apt install binaryen

# 2. The raw build (what build.sh runs)
cd boss-man-spritekit-web
swift build -c release --swift-sdk swift-6.3.2-RELEASE_wasm \
  -Xswiftc -Osize -Xlinker -s \
  -Xswiftc -Xfrontend -Xswiftc -disable-reflection-metadata
wasm-opt -Oz .build/wasm32-unknown-wasip1/release/BossMan.wasm -o web/bossman.wasm

# 3. Runtime + manifest from the sibling wasmkit checkout
git clone https://github.com/SuperBox64/WasmKit ../../WasmKit
cp ../../WasmKit/runtime.js web/
```

### Windows

Use WSL2 (Ubuntu) and follow the Linux steps; the toolchain, wasm SDK and
Binaryen all install the same way inside WSL. The produced
`web/` folder serves from any host. (A native Windows toolchain exists, but
the wasm Swift SDK path is only exercised here through WSL.)

## What it takes to write Embedded Swift

Embedded is a subset of Swift; code written for it still compiles and runs
normally everywhere else. The rules this codebase follows:

- **No `weak` or `unowned` references.** Use `unowned(unsafe)` behind
  `#if hasFeature(Embedded)` where Apple's API contract needs a non-owning
  reference (`node`, `delegate`, `camera`).
- **No `Any`, no non-class existentials, no metatypes.** APIs take typed
  enums or generics (`SKKeyframeValue` instead of `[Any]`); `type(of:)`,
  `.self` parameters and `Mirror` do not exist.
- **No runtime protocol casts.** `as? SomeProtocol` can never succeed; use a
  concrete class downcast (`as? PixelPerson`) or put the method on a base
  class and override it. Class-to-class casts work fine.
- **No `async`/`await`/`Task`, no `@MainActor`.** Completion handlers and
  the game loop replace them; timers and cooldowns are driven from
  `update(_:)` or `SKAction`, never `Task.sleep`.
- **Mind the strings.** `Double(String)` needs a C `strtod` shim;
  ICU-backed APIs (`lowercased()`, localized compares, `CharacterSet`) either
  do not exist or would drag megabytes of tables; the code uses plain
  ASCII-level helpers instead.
- **Classes, generics, closures, enums, structs, optionals, arrays,
  dictionaries and sets all work normally.** Inheritance and vtable dispatch
  are fully supported; generics monomorphize at compile time.
- **Failures are loud.** Anything outside the subset is a compile error or a
  link error (undefined symbol), never silent misbehavior at runtime, as
  long as no stub papers over a missing runtime hook.

The practical loop: write normal Swift, build both ways (the SwiftPM wasm
build and `docs/embedded/build-embedded-game.sh`), and let the Embedded
compiler errors point at the handful of places that need a typed API or a
concrete cast.

## Embedded Swift

The Embedded build compiles the entire game (the SuperBox64 SpriteKit framework
plus all 48 game files) with Swift's Embedded mode: no Foundation, no Swift
runtime metadata, no reflection, and a stdlib reduced to what the code actually
instantiates. The result boots the same title screen, plays the same game, and
produces the same scores as the normal build at roughly one sixth the size.

### Compile flags

Every Swift module (SpriteKit, AppKit, UIKit, GameController, AVFoundation,
GameKit, then the game) is compiled with:

```
swiftc -enable-experimental-feature Embedded \
       -wmo -Osize -parse-as-library \
       -target wasm32-unknown-none-wasm \
       -Xcc -fmodule-map-file=<KitABI module.modulemap> \
       -Xcc -fmodule-map-file=<CBox2D module.modulemap> \
       -Xcc -isystem <WASI.sdk>/include/wasm32-wasip1 \
       -I <KitABI include> -I <CBox2D include> -I <built modules> \
       -emit-module -c
```

- `-enable-experimental-feature Embedded` selects the embedded compilation
  model (monomorphized generics, no runtime type metadata).
- `-wmo` is required by Embedded (whole-module optimization).
- `-target wasm32-unknown-none-wasm` is the bare-metal wasm triple (os=none,
  not WASI), which is the only target the embedded stdlib ships for.
- The `-isystem` line points the ClangImporter at wasi-libc headers because the
  bare-metal target has no sysroot of its own (Box2D's public headers include
  math.h and stdint.h).
- `@MainActor` does not exist in the embedded stdlib; the build strips it from
  the sources at preprocess time (single-threaded wasm has nothing to isolate).

Box2D v3 compiles as plain C:

```
clang --target=wasm32-unknown-wasip1 --sysroot=<WASI.sdk> \
      -std=c17 -Os -DNDEBUG -ffunction-sections -fdata-sections -c
```

The link pulls it all together with dead-code stripping:

```
wasm-ld --no-entry --gc-sections \
        --export=boot --export=frame --export=_initialize --export=memory \
        --allow-undefined -L <WASI.sdk>/lib/wasm32-wasip1 \
        <modules>.o shim.c.o <box2d>.o embedded-stubs.o \
        libswiftUnicodeDataTables.a -lc -lm
```

No `-lc++`, no `-lc++abi`: there is no C++ in the link. `--allow-undefined`
leaves the `gfx_*`/`snd_*`/`eng_*` imports open for the JS runtime to provide.
A final `wasm-opt -Oz` pass (bulk-memory, nontrapping-float-to-int, sign-ext,
mutable-globals, multivalue) squeezes the binary to its shipped size.

### Building it by hand

Prereqs: the swift.org 6.3.2 toolchain, the `swift-6.3.2-RELEASE_wasm` SDK
(`swift sdk install`), and Binaryen (`brew install binaryen`).

```sh
# 1. Normal build first: fetches the framework checkout and compiles the
#    C objects (KitABI shim.c) the embedded link reuses.
cd boss-man-spritekit-web
./build.sh release

# 2. The embedded pipeline: builds every framework module in dependency
#    order, the game, Box2D v3, the runtime stubs, links and optimizes.
cd ..
bash docs/embedded/build-embedded-game.sh
# -> boss-man-spritekit-web/web/bossman-embedded.wasm

# 3. Serve it under the canonical name next to the embedded runtime.
cp boss-man-spritekit-web/web/bossman-embedded.wasm <site>/bossman.wasm
cp ../WasmKit/runtime-embedded-min.js    <site>/
```

The script (docs/embedded/build-embedded-game.sh) is the executable form of
those flags: it derives the toolchain and SDK paths, preprocesses the
`@MainActor` strip, builds each module with `-emit-module` so the next module
imports it, and prints the final sizes.

### Why Box2D v3, and why Box2D at all

Apple's SpriteKit physics engine is closed source and only exists on Apple
platforms; a wasm port has to bring its own. SuperBox64 SpriteKit implements
the `SKPhysicsBody` / `SKPhysicsWorld` / `contactTest` API surface on Box2D,
so game code written against Apple's API runs unchanged.

The engine moved from C++ Box2D 2.4 (behind a hand-written C bridge) to
vendored Box2D v3.1.1 because v3 is pure C:

- Embedded Swift imports the C API directly through a module map. The bridge
  layer (and its maintenance) is gone; Swift calls `b2World_Step` itself.
- No C++ means no libc++/libc++abi in the link and no C++ runtime stubs.
- Compiled with function/data sections, `--gc-sections` keeps only the physics
  the game calls; `-DNDEBUG` drops Box2D's assert machinery and strings.
- v3 is the actively maintained line (2.4 is frozen).

The port preserves 2.4-era behaviors games depend on: SpriteKit's separate
collision/contactTest masks map to a union filter plus sensor shapes, bodies
wake on teleport so contacts keep firing for node-driven movement, chains are
built from two-sided segments (v3 chains are one-sided), and begin-touch
events are snapshotted before delivery so a `didBegin` handler can safely
destroy bodies.

### Embedded restrictions the code respects

- No `weak`/`unowned` references (`unowned(unsafe)` under a feature check).
- No `Any` or non-class existentials; APIs use typed enums and generics.
- No runtime protocol conformance lookup: `as? SomeProtocol` can never
  succeed, so the code uses concrete class downcasts or base-class dispatch
  (and the link fails loudly if a new protocol cast sneaks in).
- No metatypes, no reflection, no `Task`/`async` (completion handlers
  instead), no `@MainActor`.
- `Double(String)` parsing needs a tiny C shim (`_swift_stdlib_strtod_clocale`
  in embedded/embedded-stubs.c), plus a `_initialize` reactor entry that runs
  wasi-libc's constructors.

## How graphics, sound and the 3D scenes work

### Graphics (SuperBox64 SpriteKit)

The framework is a reimplementation of Apple's SpriteKit API that renders
through a small C ABI instead of Metal. Each frame, `SKView.render` walks the
scene tree exactly like Apple's compositor would (transforms, anchor points,
z-order, alpha and color blending) and emits flat draw calls:

- `SKSpriteNode` becomes `gfx_draw_image(handle, srcRect, dstRect, tint)`;
  textures are images the runtime decoded once, addressed by handle, and
  `SKTexture(rect:in:)` sub-rects give atlas sampling for free.
- Color sprites and `SKShapeNode` become `gfx_fill_rect` / `gfx_fill_poly` /
  `gfx_stroke_*` calls; `SKLabelNode` becomes `gfx_draw_text` with real font
  metrics from `txt_width`.
- `SKView.texture(from:)`, `SKCropNode` and `SKEffectNode` render through
  offscreen canvases (`gfx_offscreen_begin/end`), so bake-to-texture and
  masking work like on macOS.
- `SKShader`, `SKLightNode` and `SKWarpGeometry` compile real GLSL on a hidden
  WebGL2 canvas (`gfx_shader_*`) and blit the result back into the 2D scene.

### Sound

`SKAudioNode`, `SoundManager` and `AVFoundation` calls land on the `snd_*` and
`eng_*` ABI: decoded Web Audio buffers addressed by handle, per-voice volume,
pan and playback rate, generated PCM via `snd_create_pcm`, and an
`AVAudioEngine`-shaped node graph (`eng_player/mixer/connect`) on the Web
Audio graph. Speech (the TPS report announcements) is the browser's own
speech synthesis through `tts_*`.

### The 3D scenes (ISO, DOOM, VOXEL)

There is no 3D API underneath; all three bonus renderers are software
renderers written against the same SpriteKit primitives as the 2D game:

- **DOOM** raycasts 220 screen columns per frame against the live maze grid
  and draws each wall slice as a textured vertical strip, a one-column
  sub-rect of the wall texture stretched to the projected height, with a
  z-buffer so travelers and pickups (billboard sprites) clip correctly.
- **VOXEL** is a painter's-algorithm heightfield renderer drawing back to
  front; **ISO** projects the grid to isometric billboards.
- Static node trees are baked once with `view.texture(from:)` into a single
  sprite, so the per-frame cost stays at the slice/billboard draws.
- All three drive the real game systems (BossController, RoundState,
  MazeBuilder pickups); only the projection differs per scene.

## What SuperBox64-WasmKit does

WasmKit is the from-scratch browser runtime on the other side of the C ABI,
built with **zero Emscripten, no ads, and no fugly logo overlays**, just a
single hand-written `runtime.js` (and its 42 KB minified embedded variant):

- Instantiates the wasm (WASI or Embedded reactor), provides every `env`
  import (`gfx_* snd_* img_* eng_* tts_* win_* store_*`), and drives the game
  loop with `requestAnimationFrame` calling the wasm's `frame(dt)` export.
- Loads assets from `manifest.json` (images decoded to handles, audio to Web
  Audio buffers, fonts via FontFace), serving them over http or from a single
  inlined `bundle.js` for file:// play.
- Translates browser input (keyboard, mouse, multi-touch, gamepads via the
  Web Gamepad API) into the event queue the game polls, and handles
  fullscreen, pause-on-hidden-tab, and localStorage persistence.
- Ships the build helpers: `wasmweb_manifest` regenerates the asset manifest,
  `bundle.py` produces the self-contained All-in-One Web zip.

The split keeps the contract honest: the game and framework compile from one
Swift codebase for macOS and wasm, and everything browser-specific lives in
WasmKit behind the same 101-function ABI.

## Run

The `web/` folder ships three host pages:

| Page          | Use                                                            |
|---------------|----------------------------------------------------------------|
| `index.html`  | Iframe launcher (Play button, autoplay + fullscreen) over `local.html`. |
| `local.html`  | Self-contained `file://` play. Needs `bundle.js` (see below).  |
| `server.html` | HTTP deploy. Fetches `bossman.wasm` + `assets/` over the network. |

For an HTTP run:

```sh
cd web && python3 -m http.server 8080   # open http://localhost:8080/server.html
```

For a `file://` run (double-click `index.html`), generate the offline bundle
first; `bundle.py` inlines `bossman.wasm` and every asset as `data:` URLs into
`bundle.js` and shims `fetch()` so no server is needed:

```sh
python3 ../../WasmKit/scripts/bundle.py web bossman.wasm
```

The CI workflow `build-swift-wasm.yml` does exactly this and publishes
`Boss-Man-Web.zip` (`index.html` + `local.html` + `bundle.js` + `runtime.js`),
a single self-contained build that plays in any browser from `file://`.

In all cases the host page sets `window.WASMWEB` (logical render size, asset
root, wasm URL) and loads `runtime.js`; the runtime preloads the manifest
assets, runs `_initialize` + `boot`, then drives `frame(dtMs)` once per
`requestAnimationFrame` tick.

## Project layout

```
boss-man-spritekit-web/
├── Package.swift            SwiftPM manifest. Fetches SuperBox64Kit
│                            from GitHub; pulls SpriteKit + Box2DBridge +
│                            AppKit + GameKit + GameController + AVFoundation.
├── Sources/BossMan/         @_cdecl boot/frame entrypoints + symlinks to the
│                            shared ../../boss-man-spritekit-swift game source.
├── build.sh                 Clones wasmkit, swift build, wasm-opt, manifest,
│                            copies runtime.js.
└── web/
    ├── index.html           Iframe launcher (autoplay + fullscreen).
    ├── local.html           file:// play via bundle.js.
    ├── server.html          HTTP deploy page.
    ├── runtime.js           Copied from wasmkit by build.sh.
    ├── bossman.wasm         Build output.
    ├── manifest.json        Generated from assets by wasmweb_manifest.
    └── assets/              fonts, images, voice, levels.json.
```

## Differences vs the macOS build

| Thing                 | macOS Boss-Man                                  | Wasm port                                              |
|-----------------------|--------------------------------------------------|--------------------------------------------------------|
| Lifecycle             | `NSApplicationDelegate` + `NSWindow` + `SKView` | `boot`/`frame` wasm exports + kit-driven `SKView.tick` |
| Persistence           | `UserDefaults.standard`                          | `Persistence.*` → `store_get`/`store_set` (localStorage)|
| Keyboard input        | `NSEvent.keyCode` (macOS HID codes)              | `SKScene.keyDown(_ key: Int)` (SF key index from the kit) |
| Fullscreen            | `NSWindow.toggleFullScreen`                       | Canvas `requestFullscreen` (in `runtime.js`)            |
| Asset loading         | `Bundle.main.url(forResource:withExtension:)`     | `SKTexture(imageNamed:)` → kit asset table (manifest.json) |
| Audio                 | `SKAction.playSoundFileNamed` + `AVAudioEngine`   | Same — both routed through the kit's Web Audio path     |
| Game Center           | Real `GKLeaderboard` / `GKAchievement`            | Silent local stub from `import GameKit`                  |
| Gamepad               | `GCController.extendedGamepad`                   | Same API; the runtime auto-maps d-pad/A→Arrow/Space too |
