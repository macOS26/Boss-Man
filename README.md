<img width="1247" height="587" alt="image" src="https://github.com/user-attachments/assets/1bfd708b-f376-405a-91c4-01611dd7519c" />

<img width="2560" height="1440" alt="Ms. Pac-Man Walka Walka" src="https://github.com/user-attachments/assets/6a0bd808-9927-4d79-8b94-014fdb9f6392" />

# Boss-Man

The Video Game, native on macOS 14.6 or later. An *Office Space* inspired maze game built in Swift with SpriteKit.

It now runs far beyond the Mac: one shared codebase ships to the browser as WebAssembly (via SuperBox64 SpriteKit) and to Windows, Linux, Android, and the web through a C++ port. See [The Tech](#the-tech-one-game-three-ports-one-framework) below.

## Download the DMG

Grab the latest macOS build, signed, notarized, and ready to play:

[github.com/macOS26/Boss-Man/releases](https://github.com/macOS26/Boss-Man/releases)

## Official Website

Screenshots, trailers, leaderboards, web and deskop version and more:

[boss-man.us](https://boss-man.us)

## Object of the Game

You are **PETE**, an office worker (blue shirt, orange tie) trapped in a 37×17 grid of cubicles. Each level, you must:

1. **Eat every glowing yellow dot** in the cubicle aisles.
2. **Visit the four office machines** (printer, fax machine, cover sheet stack, book binder) to assemble a TPS report.
3. **Drop the completed TPS report into a TPS Delivery Box** (the brown box) to bank the points.
4. **Avoid the four bosses** patrolling the office.
5. **Grab a Gold Disc** to flip the bosses into Blue Mode for a short window, then chase *them* down for bonus points.

Clear the dots, deliver at least one TPS report, and you advance to the next level.

## Controls

- **Arrow keys** or **WASD** to move PETE
- **Mouse / trackpad** to point-to-move (PETE walks toward the cursor)
- **Space** to start a new round, or continue from the title screen
- **ESC** to return to the title screen
- Joystick and DPAD support coming soon

## Lives

- Start with **3 lives**, capped at **5**.
- Every TPS report you deliver grants **+1 life** (until you hit the cap).
- Lose a life when a boss catches you outside of Blue Mode.
- Lose all your lives → game over.

## TPS Reports

To assemble a report you must visit every required machine on the floor:

| Machine          | Emoji |
|------------------|:-----:|
| TPS Printer      | 🖨️    |
| TPS Fax Machine  | 📠    |
| TPS Cover Sheet  | 📄    |
| TPS Book Binder  | 📚    |

Once all four are checked off, walk over the **TPS Delivery Box** (📦) to deliver the report. The HUD shows ✅ for completed items and ❌ for missing ones.

- Report value scales with the level: `level × 100 + 100` points.
- Delivery awards **+1 life** (up to the 5-life cap).
- Getting caught by a boss before delivering wipes the in-progress report.

## Bosses

Each boss has its own color, AI personality, and speed, modeled after Ms. Pac-Man's ghosts (Blinky / Pinky / Inky / Sue).

| Boss   | Shirt        | Tie                  | Behavior                                              | Speed |
|--------|--------------|----------------------|-------------------------------------------------------|-------|
| **BILL**  | 🟥 Red        | Black                | Direct chase (Blinky)                                 | 1.00× |
| **DOM**   | 🟪 Pink (75% α over white) | Purple + 40% black | Ambush 4 tiles ahead (Pinky)                          | 0.85× |
| **BOB**   | 🟦 Teal       | Blue + 20% black     | Flanker, pivots 2 tiles off PETE's path (Inky)       | 0.78× |
| **STAN**  | 🟧 Orange     | Red + 10% black      | Timid scatter, backs to corner when too close (Sue)  | 0.70× |

On every 12th level (12, 24, …) the entire roster turns **all-black** (MIB theme) and wears sunglasses.

### Blue Mode

Grab a **Gold Disc** 🟡 (4 per floor) and all active bosses flip into Blue Mode for ~20 seconds:

- Shirt → systemBlue + 20% black
- Tie fill → systemYellow, outline → RGB yellow
- Eyes → systemBlue + 50% black
- Bosses flee from PETE
- Catch them for **100 → 200 → 400 → 800** points (streaked per Gold Disc)

A boss caught three times in a single Blue Mode is permanently rebuilt at its spawn corner.

## Travelers

A traveler enters the maze every ~30 seconds from the right tunnel and wanders to the left tunnel. Catch one for bonus points. The traveler rotates by level (cycles every 12 levels):

| Level | Traveler                              | Points |
|------:|---------------------------------------|------:|
| 1     | 🐟 Fish                                | 100    |
| 2     | 🍩 Donut                               | 200    |
| 3     | ☕️ Coffee                              | 400    |
| 4     | 🥤 Soda Cup                            | 800    |
| 5     | 🍎 Apple                               | 1,000  |
| 6     | <img src="Boss-Man/Resources/shinyredstapler-emoji.png" width="32" alt="Shiny Red Stapler"/> **Shiny Red Stapler** (PNG sprite) | 2,000  |
| 7     | 🍉 Watermelon                          | 3,000  |
| 8     | 🧇 Waffle                              | 4,000  |
| 9     | 🍦 Ice Cream                           | 5,000  |
| 10    | 🍰 Cake                                | 6,000  |
| 11    | 👀 Eyes                                | 7,000  |
| 12    | 👁️ Big Eye                             | 8,000  |
| 13+   | Cycle repeats (with harder mazes)      | …      |

The HUD's top-right "trail" shows which travelers have appeared so far this cycle; the leftmost is the current level's traveler.

## Level Editor

Press the **LEVEL EDITOR** button from the title screen to design your own floors:

- 15-tile palette: floor, dot, wall, hideout, the four machines, brown box, gold disc, PETE spawn, and BILL/DOM/BOB/STAN spawns.
- Left-click paints the selected tile; right-click toggles dot↔wall (any other tile → dot).
- Tunnels are auto-detected, paint a floor gap in the perimeter wall to create a tunnel pair.
- 24 bundled levels. Custom edits save to `~/Library/Application Support/Boss-Man/levels.json`.
- Shortcuts: `⌘S` save · `⌘Z` undo · `⇧⌘Z` redo · `⌘⌫` clear · `⌘C/⌘V` copy/paste level · `⌘P` playtest · `⌘R` reveal file · `← →` previous/next · `ESC` back.
- Autosaves every 60 s, on PREV/NEXT/ESC/PLAY, and on app quit (dirty-check via map hash).
- Duplicate boss types are allowed (e.g. two BOBs) and you can place more than 4 bosses per level.

PETE, the four bosses, and life-icon stand-ins are drawn procedurally by `PixelPerson.swift`, no sprite sheets, no boss PNGs. The app icon lives in `Boss-Man/Resources/AppIcon.icon`.

## The Tech: One Game, Three Ports, One Framework

Boss-Man ships from three codebases that stay in lockstep, plus the framework that makes the web and wasm builds possible.

| Port | Folder | Stack | Targets |
|------|--------|-------|---------|
| **Swift / SpriteKit** (master) | `boss-man-spritekit-swift/` | Swift + Apple SpriteKit | macOS (the signed, notarized DMG) |
| **Swift / WebAssembly** | `boss-man-spritekit-web/` | the *same* Swift, compiled to wasm | any modern browser |
| **C++ / Box2D + SFML** | `boss-man-box2d-sfml-cpp/` | C++17, Box2D 2.4.1, SFML 2.6 | macOS, Windows, Linux, Android, browser |

The Swift macOS project is the single source of truth. The Swift WASM port does not fork the game: 32 of its 33 source files are symlinks straight back to the macOS master, so both builds compile the identical Swift. The only port-specific file is `main.swift` (the wasm `boot`/`frame` entry points in place of the macOS `NSApplicationDelegate`). The goal is 100% common game source, with every platform difference pushed down into the framework instead of forked into the game.

### wasm-web-kit

`wasm-web-kit/` runs a native game in the browser as WebAssembly **without Emscripten**. The game is compiled with the WASI SDK clang (`--target=wasm32-wasip1`, WASI Preview 1) and driven by a small hand-written JavaScript runtime (`runtime.js`) that implements graphics on Canvas2D, audio on Web Audio, input on DOM events plus the Web Gamepad API, and persistence on localStorage. No Emscripten, no third-party engine, no branding. You ship your own `index.html`.

The wasm module is a WASI reactor that exports three functions the runtime calls: `_initialize` (libc and C++ constructors), `boot()` (after assets preload), and `frame(dtMs)` (once per `requestAnimationFrame`). Everything else the game imports from a single `env` ABI (`include/abi.h`). Two consumer layers sit on that one ABI:

- **C++ SFML shim.** A header-only `sf::` compatibility layer (shapes, `Sprite`/`Texture`, `Font`/`Text`, `RenderWindow`, `Event`/`Keyboard`/`Mouse`, sound). Point `-I include` at it and an SFML game compiles mostly unchanged. This is how the C++ port reaches the web.
- **SuperBox64 SpriteKit.** See below.

### SuperBox64 SpriteKit

`wasm-web-kit/spritekit/` is a from-scratch Swift reimplementation of Apple's closed SpriteKit (`SKScene`, `SKNode`, `SKSpriteNode`, `SKLabelNode`, `SKShapeNode`, `SKAction`, `SKPhysicsBody`, `SKPhysicsWorld`, `SKView`, `SKCameraNode`, and more), running on the wasm-web-kit runtime with physics provided by Box2D 2.4.1 (the `Box2DBridge` target, the "Box" in SuperBox64). It is a SwiftPM package that vends a module literally named `SpriteKit`, so a game's `import SpriteKit` binds to this reimplementation instead of Apple's framework, with no edits at the call site. It ships matching drop-in shims for `AppKit`, `UIKit`, `Cocoa`, `GameKit`, `GameplayKit`, `GameController`, and `AVFoundation`. That is what lets the macOS Swift game compile to wasm unchanged.

## What We're Building Now

- **A full-screen GAME OVER combo screen**, just landed across all three ports: the local top-10 leaderboard, an on-screen A-Z / 0-9 keyboard for name entry when your score qualifies (tap on mobile, type on desktop), and big PLAY and ESC buttons. Mobile-first, and on the Swift side it is a single shared file (`GameOverScreen.swift`) driving both macOS and the web.
- **Driving the Swift game to 100% common source.** Already 32 of 33 files shared; the remaining work is pushing the last platform seams into the framework.
- **Cross-platform parity.** A steady stream of sync passes keeps the C++ and wasm ports faithful to the Apple master, down to boss speeds, animation timing, and pixel-level visuals.
- **Native Android** via the NDK (SFML `NativeActivity`, drag to steer and tap to fire), built in CI into a downloadable APK.
- **Framework-first fixes.** When a port is missing something, the fix lands in wasm-web-kit (the SpriteKit reimplementation or the SFML shim), not in a per-game workaround, so the next game inherits it.

## Run Everywhere on Anything

Apple's SpriteKit is a walled-garden framework. A game written with `import SpriteKit` normally runs only on Apple platforms, because it leans on Apple's closed frameworks and toolchain. Boss-Man is the proving ground for breaking that lock-in without rewriting the game.

The mechanism is SuperBox64 SpriteKit. Because it vends a module named `SpriteKit`, the exact same Swift source compiles two ways: against Apple's frameworks it is a native macOS app; against SuperBox64 it is a WASI Preview 1 wasm binary that runs in any browser, with the runtime adapting the lifecycle (`boot`/`frame`), persistence (localStorage), input (SF key codes), and audio (Web Audio). Thirty-two of thirty-three game files are already one shared source between the two builds, so this is not a theory, it is the current build.

Alongside the Swift path, the C++ port over the same framework's SFML shim extends the reach further: desktop (a universal signed and notarized macOS app, a static Windows .exe, a Linux .deb), the browser again, and native Android. One title, authored once against the Apple master, kept in lockstep everywhere.

The bigger payoff, and the project's north star, is a repeatable path to lift any existing SpriteKit game out of the Apple walled garden and run it cross-platform from a single codebase. Write once for Apple, run everywhere on anything.

## Building from Source

### Prerequisites

- **Xcode** plus the **Command Line Tools** (`xcode-select --install`) for the Swift / SpriteKit build and the Apple toolchain.
- **CMake** (`brew install cmake`) for the C++ build. It downloads and builds SFML 2.6, Box2D 2.4.1, and nlohmann/json for you, and embeds the assets into the binary.
- **swiftly** with the Swift 6.3.2 toolchain and the matching WebAssembly SDK (`swift-6.3.2-RELEASE_wasm`) for the Swift WASM build.
- A **WASI SDK** for the C++ WASM build.

> No Homebrew? Get it at https://brew.sh, or download CMake manually from https://cmake.org/download and add it to your `PATH`.

### Swift / SpriteKit, macOS (the master)

```sh
open boss-man-spritekit-swift/Boss-Man.xcodeproj
```

Select the **Boss-Man** scheme and press Run (Cmd-R), or from the command line:

```sh
xcodebuild -project boss-man-spritekit-swift/Boss-Man.xcodeproj -scheme Boss-Man -configuration Release build
```

Requires macOS 14.6 or later.

### Swift / WebAssembly

```sh
cd boss-man-spritekit-web
./build.sh release        # release -> web/bossman.wasm
cd web && python3 -m http.server 8080
# open http://localhost:8080
```

`build.sh` wraps `swift build` with `TOOLCHAINS=org.swift.6.3.2-release` and the `swift-6.3.2-RELEASE_wasm` SDK (via `xcrun --toolchain swift`, because Xcode's bundled clang has no wasm backend), publishes `web/bossman.wasm`, and regenerates an inlined `bundle.js` so `web/local.html` also runs straight from `file://` with no server.

### C++ / Box2D + SFML, desktop (macOS, Windows, Linux)

```sh
cd boss-man-box2d-sfml-cpp
cmake -B build
cmake --build build
```

The first configure downloads SFML 2.6, Box2D 2.4.1, and nlohmann/json via CMake FetchContent (needs an internet connection). Then run it:

```sh
open build/Boss-Man-mac.app     # macOS (.app bundle)
./build/Boss-Man                # Linux / Windows (Boss-Man.exe)
```

Press **P** to play, **F** to toggle fullscreen, **ESC** for the title.

### C++ / Android (NDK)

```sh
cd boss-man-box2d-sfml-cpp/android
gradle assembleDebug            # -> app/build/outputs/apk/debug/*.apk
```

The game builds as a native `NativeActivity` (`libsfml-game.so`) for arm64-v8a, armeabi-v7a, and x86_64 (NDK 26.3.11579264, CMake 3.22.1, minSdk 24, target 34). CI does the same in `.github/workflows/build-android.yml` and publishes `Boss-Man-Android.apk`.

### C++ / WebAssembly

```sh
cd boss-man-box2d-sfml-cpp && cmake -B build    # populate Box2D + json sources once
cd ../boss-man-web && ./build-web.sh            # -> web/boss.wasm
```

Like the Swift WASM port, this is WASI Preview 1 with **no Emscripten**: the WASI SDK clang compiles the same `src/` tree (`--target=wasm32-wasip1`, reactor model), swapping real SFML for the wasm-web-kit SFML shim while still compiling real Box2D. Open `boss-man-web/web/index.html` directly (the inlined bundle works from `file://`), or serve the `web/` folder with any static server.

## Crafted by One, Amplified by AI
- Designed, coded, and shipped using **Agent**, an autonomous agentic AI for macOS 26.4.1. [github.com/macos26/agent](https://github.com/macos26/agent)
- Fine-tuned with **Claude Code** alongside Agent. The right tool for the right job, every time.
- Releases, DMGs, and notes all deployed by Agent itself. The future of indie shipping.

## Built from Scratch
- Custom **Box2D + SFML + C++** port, written by Todd Bruss.
- The **wasm-web-kit** framework and **SuperBox64 SpriteKit** (an Apple-SpriteKit reimplementation in Swift), built from the ground up, no Emscripten.
- Original music, graphics, art, sound effects, and game design, all by Todd Bruss.

## Honest Licensing
- Source code is **MIT**. Fork it, learn from it, build with it.
- Binaries remain the property of Todd Bruss.

---

*Copyright 2026 Todd Bruss. [boss-man.us](https://boss-man.us). All rights reserved.*

**Ready to play? Pick your platform and dive in.**
