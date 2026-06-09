# Boss-Man · SpriteKit edition on WebAssembly

The macOS [Boss-Man](../boss-man-spritekit-swift) SpriteKit game compiled to
WebAssembly via [SuperBox64 SpriteKit](https://github.com/macOS26/superbox64-spritekit),
Apple's SpriteKit reimplemented in Swift, no Emscripten, no Apple frameworks.
The game's `import SpriteKit` lines work unchanged here because SuperBox64
SpriteKit vends a module named `SpriteKit` that the Swift compiler binds to
in place of Apple's framework. The runtime (Canvas2D renderer, Web Audio mixer,
DOM input, asset preloader) ships from
[superbox64-wasmkit](https://github.com/macOS26/superbox64-wasmkit).

The same Swift source drives the macOS app and this wasm build; the platform
differences (boot/frame lifecycle, `localStorage` persistence, SF key codes)
live in the framework, not the game.

## Build

```sh
./build.sh                  # debug   → web/bossman.wasm
./build.sh release          # release → web/bossman.wasm (wasm-opt -Oz)
```

`build.sh`:

1. Uses the [superbox64-wasmkit](https://github.com/macOS26/superbox64-wasmkit)
   sibling checkout at `../../superbox64-wasmkit` (its own repo, next to this
   one), cloning it there if not already present.
2. Runs `swift build` with `TOOLCHAINS=org.swift.6.3.2-release` and
   `xcrun --toolchain swift` so SwiftPM picks the swift.org clang the WASI SDK
   was built against (Xcode's bundled clang has no wasm backend). The
   superbox64-spritekit dependency is fetched from GitHub by SwiftPM.
3. Optimizes the release binary with `wasm-opt -Oz` into `web/bossman.wasm`.
4. Sources the kit's `build.sh` and calls `wasmweb_manifest` to regenerate
   `web/manifest.json` from `web/assets`.
5. Copies the kit's `runtime.js` into `web/`.

## Build sizes

Physics is Box2D v3 (pure C, vendored in superbox64-spritekit as `CBox2D`,
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

Activity Monitor on the notarized Boss-Man-wk.app running the Embedded wasm:

| Process | RAM |
|---|---|
| bossman://app (WKWebView content) | 168.1 MB |
| Boss-Man-wk Graphics and Media | 90.4 MB |
| Boss-Man-wk (host app) | 26.1 MB |
| Boss-Man-wk Networking | 6.0 MB |
| **Total** | **~290 MB** |

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
python3 ../../superbox64-wasmkit/scripts/bundle.py web bossman.wasm
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
├── Package.swift            SwiftPM manifest. Fetches superbox64-spritekit
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
