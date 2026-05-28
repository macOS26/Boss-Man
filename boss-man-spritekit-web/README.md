# Boss-Man · SpriteKit edition on WebAssembly

The macOS [Boss-Man](../boss-man-spritekit-swift) SpriteKit game ported to
WebAssembly via [SuperBox64 SpriteKit](../wasm-web-kit/spritekit) — Apple's
SpriteKit reimplemented in Swift, no Emscripten, no Apple frameworks. The
game's `import SpriteKit` lines work unchanged here because SuperBox64
SpriteKit vends a module named `SpriteKit` that the Swift compiler binds to
in place of Apple's framework.

The original macOS project is **not modified**; this folder is the parallel
wasm build. The two projects share a level grammar, a sprite vocabulary, and
a control scheme; the wasm port adapts the lifecycle (boot/frame instead of
`NSApplicationDelegate`), the persistence layer (`localStorage` via
`store_get`/`store_set` instead of `UserDefaults`), and the input model
(SF key codes from the kit's event queue instead of `NSEvent.keyCode`).

## Build

```sh
./build.sh                  # debug → web/bossman.wasm
./build.sh release          # release → web/bossman.wasm
```

The script wraps `swift build` with `TOOLCHAINS=org.swift.6.3.2-release` and
`xcrun --toolchain swift` so SwiftPM picks the swift.org clang the WASI SDK
was built against (Xcode's bundled clang has no wasm backend). Output ships
straight into `web/bossman.wasm` so the page is one local-server step away.

## Run

```sh
cd web && python3 -m http.server 8080
# open http://localhost:8080
```

The host page sets `window.WASMWEB` (logical render size, asset root, wasm
URL) and loads the kit's `runtime.js`; the runtime fetches `bossman.wasm`,
runs `_initialize` + `boot`, then drives `frame(dtMs)` once per
`requestAnimationFrame` tick.

## Project layout

```
boss-man-spritekit-web/
├── Package.swift            SwiftPM manifest. Depends on
│                            ../wasm-web-kit/spritekit by path; pulls
│                            SpriteKit + Box2DBridge + AppKit + GameKit +
│                            GameController + AVFoundation products.
├── Sources/BossMan/
│   ├── main.swift           @_cdecl boot/frame entrypoints. Presents
│   │                        TitleScene; tick() drives the frame loop.
│   ├── PhysicsCategory.swift   Collision bitmasks.
│   ├── MoveDirection.swift     Four-cardinal enum + SF-keyCode init.
│   ├── Strings.swift           Level grammar + font/action keys.
│   ├── Persistence.swift       Thin localStorage wrapper.
│   ├── TitleScene.swift        Title screen + stapler + prompt.
│   ├── LeaderboardPanel.swift  Post-it leaderboard.
│   ├── GameScene.swift         Maze play surface (port in progress).
│   └── LevelEditorScene.swift  Editor (port in progress).
├── build.sh                 Wraps swift build with TOOLCHAINS + wasm SDK.
└── web/
    ├── index.html           Hosting page; canvas + window.WASMWEB.
    ├── runtime.js → ../../wasm-web-kit/runtime.js
    └── assets/
        ├── manifest.json    Preloader-driven asset registration.
        └── images/red-stapler.png
```

## Port status

| Layer                       | Status                                         |
|-----------------------------|------------------------------------------------|
| Scaffold + boot/frame       | ✅ runs to title screen                        |
| Title scene + leaderboard   | ✅ layout + blink + stapler                    |
| Persistence (localStorage)  | ✅ via store_get / store_set                   |
| Level grammar tokens        | ✅ Strings.Tile mirrors original               |
| Gameplay (maze + Pete)      | ⏳ scaffolded; MazeBuilder + controllers next  |
| Boss AI + ContactRouter     | ⏳ next milestone                              |
| HUD + ScorePopup            | ⏳ wired after maze lands                      |
| Level editor                | ⏳ placeholder; needs grid edit + serialize    |
| Game Center / leaderboards  | ⚠ silent stub via the GameKit shim             |

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
