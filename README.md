<img width="1247" height="587" alt="image" src="https://github.com/user-attachments/assets/1bfd708b-f376-405a-91c4-01611dd7519c" />

<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/f7e9b5c5-5a45-4076-9e07-b0eee7f9edbe" />
<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/51c5220f-6ad9-4e0c-82ae-d6c610616f6e" />
<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/1ac48f6c-fe0e-4749-ae48-a5ff05275c6d" />




# Boss-Man

The office maze arcade game, runs on Mac, Windows, Linux, Web (mobile friendly), and Android. An *Office Space* inspired maze game built in Swift using **SuperBox64 SpriteKit** — an open source reimplementation of Apple's SpriteKit, compiled to WebAssembly via WASI Preview 1 and wrapped in a native WebView on every platform.

The C++ port is legacy. The future is Swift: one shared Swift codebase, one open source SpriteKit engine, six platforms. A 2D/3D simulated game engine is coming soon. See [The Tech](#the-tech-one-game-three-ports-one-framework) below.

## Download the DMG

Grab the latest macOS build, signed, notarized, and ready to play:

[github.com/macOS26/Boss-Man/releases](https://github.com/macOS26/Boss-Man/releases)

## Official Website

Screenshots, trailers, leaderboards, web and desktop version and more:

[boss-man.us](https://boss-man.us)

## Object of the Game

You are **PETE**, an office worker (blue shirt, orange tie) trapped in a 37x17 grid of cubicles. Each level, you must:

1. **Eat every glowing yellow dot** in the cubicle aisles.
2. **Visit the four office machines** (printer, fax machine, cover sheet stack, book binder) to assemble a TPS report.
3. **Drop the completed TPS report into a TPS Delivery Box** (the brown box) to bank the points.
4. **Avoid the four bosses** patrolling the office.
5. **Grab a Gold Disc** to flip the bosses into Blue Mode for a short window, then chase *them* down for bonus points.
6. **Pick up the Water Gun** power-up to shoot water pellets and knock back bosses.

Clear the dots, deliver at least one TPS report, and you advance to the next level.

## Controls

### Keyboard / Mouse
- **Arrow keys** or **WASD** to move PETE
- **Mouse / trackpad** to point-to-move (PETE walks toward the cursor)
- **Space** to start a new round or continue from the title screen
- **ESC** to return to the title screen
- **Tap / click** to fire the water gun when active

### On-Screen Controls
Tap the joystick icon on the title screen to cycle through five control modes:

| Mode | Description |
|------|-------------|
| **HIDDEN** | Swipe anywhere to move, tap to fire |
| **STICK LEFT** | Virtual joystick on the left side |
| **STICK RIGHT** | Virtual joystick on the right side |
| **DPAD LEFT** | D-pad on the left side |
| **DPAD RIGHT** | D-pad on the right side |

Physical gamepads and Apple Game Controller framework are also supported.

## Game Modes

Boss-Man ships **six distinct renderers**, unlocked by cycling the title screen. Each one is a love letter to a different era of game graphics, named after a character from *Office Space* or a cult classic film. Every mode runs the exact same game underneath: the same boss AI, Blue Mode, TPS report chain, gold discs, water gun, tunnels, travelers, and lives. Only the camera and renderer change. Collect dots, deliver reports, and avoid your bosses — whether you are doing it in flat 2D or walking the corridors in first person.

---

### 2D Modes — The Classic Era

Three top-down views of the full 37×17 cubicle grid, inspired by the golden age of maze arcade games.

#### WIDE — LUMBERGH (1980)

The whole office floor, all at once. Every aisle, every dot, every boss in full view. This is the purest form of the game: a direct descendant of the original Ms. Pac-Man cabinet perspective, where situational awareness is total and decisions happen fast. The HUD sits outside the play area, nothing scrolls, and the layout reads instantly. If you have ever played a maze arcade game, this view is immediately familiar.

#### ZOOM — TWO BOBS (1982)

A 1.5x zoom that locks onto PETE and scrolls smoothly as he moves. Inspired by **Jr. Pac-Man's** larger-than-screen mazes, ZOOM trades the full-map overview for a closer, more intimate view of the corridors. You can still read ahead a few tiles in every direction, but the bosses can sneak up from just off screen. The scrolling camera makes the office feel bigger and more threatening.

#### MACRO — MILTON (1983)

A 2x zoom with a compact strip HUD tucked above the play area. The biggest, most cinematic view of the office. The dots fill the screen, the cubicle walls tower over PETE, and the bosses are large enough to read their expressions. MACRO is the closest the 2D modes get to the experience of being inside the maze. Inspired by the close-focus style of late-arcade and early home-console maze games.

---

### 3D Bonus Modes — The Revolution Era

Three fully realized 3D renderers that replay thirty years of graphics history, each built from scratch on top of the identical game logic. Every 3D mode includes a **live top-down minimap** (with a PETE arrow that throbs in his direction of travel) so you always know where you are. All three modes drive the real `BossController`, `RoundState`, `MazeBuilder`, `GoldDiscTimer`, and `WaterGunState` — nothing is hand-rolled for the bonus view.

#### ISO — WONDERLAND (1985)

The office reimagined as an isometric diorama. The maze is projected onto a classic 2:1 diamond grid, a technique popularized by games like **Zaxxon**, **Q*bert**, and the British home-computer adventure games of the mid-1980s. Cubicle walls are extruded as solid blocks, pellets and pickups float at their proper heights, and PETE and the bosses walk the isometric floor as billboarded pixel-person sprites. The perspective is fixed at a 30-degree angle, giving the office a clean architectural feel. It is the mode that answers the question: what if Boss-Man shipped in 1985?

#### RAY — SEVERANCE (1993)

First-person. You are Pete, walking through the office corridors. The walls are rendered with a **Wolfenstein / DOOM-style DDA raycaster**: each screen column is a ray shot into the 3D scene, the nearest wall face is found, and the column is filled with a perspective-scaled strip. RAY adds the full-face projection treatment from the Swift master: wall faces are projected as per-face trapezoid quads (not raw column strips), clipped at the near plane, depth-sorted, and fog-blended against the level's cubicle color. A distance-based fog darkens far walls and the gray cubicle-window insets add depth. Pellets, gold discs, bosses, and the traveler are all projected as depth-sorted billboards that interleave correctly with the wall faces. The ceiling is a tiled drop-panel pattern lit by flickering fluorescent tubes — the unmistakable office overhead that makes every hallway feel like a Initech floor. The floor is a perspective-correct checker. The era is unmistakable: 1993 was the year id Software changed everything.

#### VOXEL — LABYRINTH (1994)

Column-by-column voxel painting, the technique that powered **NovaLogic's Comanche** helicopter series. The world is not a polygon mesh and there is no raycaster: the renderer walks the camera frustum column by column, projecting each wall face as a depth-correct quad using the exact same face-corner projection math as the Swift master, then stacking voxel slabs from the floor up. A gradient sky dome and sun-glow light shafts fill the upper half of the screen. The floor checker uses perspective-correct distancing, giving the corridors a convincing sense of depth without a z-buffer. VOXEL is the mode that answers the question: what if the office maze was a combat zone rendered by a 1994 terrain engine? The Comanche inspiration is unmistakable in the earth-toned depth shading and the way solid geometry rises out of the floor.

## Lives

- Start with **3 lives**, capped at **5**.
- Every TPS report you deliver grants **+1 life** (until you hit the cap).
- Lose a life when a boss catches you outside of Blue Mode.
- Lose all your lives → game over.

## TPS Reports

To assemble a report you must visit every required machine on the floor:

| Machine | Emoji |
|---------|:-----:|
| TPS Printer | 🖨️ |
| TPS Fax Machine | 📠 |
| TPS Cover Sheet | 📄 |
| TPS Book Binder | 📚 |

Once all four are checked off, walk over the **TPS Delivery Box** (📦) to deliver the report. The HUD shows checkmarks for completed items and X marks for missing ones.

- Report value scales with the level: `level x 100 + 100` points.
- Delivery awards **+1 life** (up to the 5-life cap).
- Getting caught by a boss before delivering wipes the in-progress report.

## Bosses

Each boss has its own color, AI personality, and speed, modeled after Ms. Pac-Man's ghosts (Blinky / Pinky / Inky / Sue). Bosses only hunt when within 3 tiles of PETE (Chebyshev distance), so the maze always has safe zones.

| Boss | Shirt | Tie | Behavior | Speed |
|------|-------|-----|----------|-------|
| **BILL** | Red | Black | Direct chase (Blinky) | 1.00x |
| **DOM** | Pink (75% alpha over white) | Purple + 40% black | Ambush 4 tiles ahead (Pinky) | 0.85x |
| **BOB** | Teal | Blue + 20% black | Flanker, pivots 2 tiles off PETE's path (Inky) | 0.78x |
| **STAN** | Orange | Red + 10% black | Timid scatter, backs to corner when too close (Sue) | 0.70x |

On every 12th level (12, 24, ...) the entire roster turns **all-black** (MIB theme) and wears sunglasses.

### Blue Mode

Grab a **Gold Disc** (4 per floor) and all active bosses flip into Blue Mode for ~20 seconds:

- Shirt turns systemBlue + 20% black
- Tie fill turns systemYellow, outline turns RGB yellow
- Eyes turn systemBlue + 50% black
- Bosses flee from PETE
- Catch them for **100 → 200 → 400 → 800** points (streaked per Gold Disc)
- In 3D modes, bosses show their point value when in flee mode instead of their name

A boss caught three times in a single Blue Mode is permanently rebuilt at its spawn corner.

## Water Gun

A **Water Gun** power-up tile appears on some floors. Pick it up to enter water gun mode:

- Gain **8 pellets** on first pickup; revisiting the tile reloads to 8.
- **Tap / click / fire button** to shoot a pellet in PETE's direction of travel.
- Pellets knock back bosses on contact (a splash effect plays).
- The HUD shows the remaining pellet count while the gun is active.
- In the 3D modes, a water droplet billboard flies through the corridor toward any boss in its path.
- The water gun carries over between floors; pellet count persists until depleted.

## Travelers

A traveler enters the maze every ~30 seconds from the right tunnel and wanders to the left tunnel. Catch one for bonus points. The traveler rotates by level (cycles every 12 levels):

| Level | Traveler | Points |
|------:|----------|-------:|
| 1 | Fish | 100 |
| 2 | Donut | 200 |
| 3 | Coffee | 400 |
| 4 | Soda Cup | 800 |
| 5 | Apple | 1,000 |
| 6 | **Shiny Red Stapler** (PNG sprite) | 2,000 |
| 7 | Watermelon | 3,000 |
| 8 | Waffle | 4,000 |
| 9 | Ice Cream | 5,000 |
| 10 | Cake | 6,000 |
| 11 | Eyes | 7,000 |
| 12 | Big Eye | 8,000 |
| 13+ | Cycle repeats (with harder mazes) | ... |

The HUD's top-right "trail" shows which travelers have appeared so far this cycle; the leftmost is the current level's traveler.

## Level Editor

Press the **LEVEL EDITOR** button from the title screen to design your own floors:

- 15-tile palette: floor, dot, wall, hideout, the four machines, brown box, gold disc, PETE spawn, and BILL/DOM/BOB/STAN spawns.
- Left-click paints the selected tile; right-click toggles dot/wall (any other tile → dot).
- Tunnels are auto-detected; paint a floor gap in the perimeter wall to create a tunnel pair.
- 24 bundled levels. Custom edits save to `~/Library/Application Support/Boss-Man/levels.json`.
- Shortcuts: `Cmd+S` save · `Cmd+Z` undo · `Shift+Cmd+Z` redo · `Cmd+Delete` clear · `Cmd+C/Cmd+V` copy/paste level · `Cmd+P` playtest · `Cmd+R` reveal file · `Left/Right` previous/next · `ESC` back.
- Autosaves every 60 s, on PREV/NEXT/ESC/PLAY, and on app quit (dirty-check via map hash).
- Duplicate boss types are allowed (two BOBs) and you can place more than 4 bosses per level.
- Hideout tiles must be interior single-pellet alcoves (3 walls + 1 pellet + wall behind), minimum 5 per floor.

PETE, the four bosses, and life-icon stand-ins are drawn procedurally by `PixelPerson.swift`. No sprite sheets, no boss PNGs. The app icon lives in `Boss-Man/Resources/AppIcon.icon`.

## The Tech: One Game, One Framework, Six Platforms

Boss-Man is the proving ground for **SuperBox64 SpriteKit** — a custom open source reimplementation of Apple's closed SpriteKit framework, compiled to WebAssembly (WASI Preview 1) and wrapped in a native WebView on every platform.

| Port | Folder | Stack | Targets |
|------|--------|-------|---------|
| **Swift / SpriteKit** (master) | `boss-man-spritekit-swift/` | Swift + Apple SpriteKit | macOS (signed, notarized DMG) |
| **Swift / SuperBox64 SpriteKit** | `boss-man-spritekit-web/` | the *same* Swift, compiled to WASM | browser, macOS/Windows/Linux/Android WebView |
| **C++ / Box2D + SFML** (legacy) | `boss-man-box2d-sfml-cpp/` | C++17, Box2D 2.4.1, SFML 2.6 | macOS, Windows, Linux, Android, browser |

The Swift macOS project is the single source of truth. The Swift WASM port does not fork the game: 32 of its 33 source files are symlinks straight back to the macOS master, so both builds compile identical Swift. The only port-specific file is `main.swift` (the wasm `boot`/`frame` entry points in place of the macOS `NSApplicationDelegate`). The goal is 100% common game source, with every platform difference pushed down into the framework instead of forked into the game.

A fully simulated 2D/3D game engine built on SuperBox64 SpriteKit is in development.

### wasm-web-kit

`wasm-web-kit/` is a hand-built WASM runtime that ships your game with zero third-party baggage. No Emscripten loading screens, no spinning gear logo, no watermarks, no injected ads, no forced branding on your title screen. Emscripten was built to port C code to the web in a hurry — it solves that problem by pulling in an entire POSIX runtime, a custom linker, and a runtime shell that announces itself. wasm-web-kit solves a different problem: shipping a polished commercial game that looks like it belongs on the platform.

The game is compiled with the WASI SDK (`--target=wasm32-wasip1`, WASI Preview 1) and driven by a lean hand-written JavaScript runtime (`runtime.js`) that implements exactly what a game needs and nothing more: graphics on Canvas2D, audio on Web Audio, input on DOM events and the Web Gamepad API, persistence on localStorage. You get a single `runtime.js`, a single `bossman.wasm`, and your own `index.html`. No black box. No phone home. No logo that is not yours.

The wasm module is a WASI reactor exporting three functions: `_initialize` (libc init), `boot()` (after assets preload), and `frame(dtMs)` (once per `requestAnimationFrame`). Everything else the game imports from a single clean ABI (`include/abi.h`). Two consumer layers sit on top:

- **C++ SFML shim.** A header-only `sf::` compatibility layer (`Sprite`/`Texture`, `Font`/`Text`, `RenderWindow`, `Event`/`Keyboard`/`Mouse`, sound, shapes). Point `-I include` at it and an SFML game compiles mostly unchanged with no Emscripten dependency.
- **SuperBox64 SpriteKit.** See below.

### SuperBox64 SpriteKit

Most cross-platform solutions for Apple games ask you to rewrite your game, swap your framework, learn a new API, or accept a lowest-common-denominator engine with its own rendering model and its own opinions about your code. SuperBox64 SpriteKit does none of that.

`wasm-web-kit/spritekit/` is a from-scratch open source Swift reimplementation of Apple's closed SpriteKit API (`SKScene`, `SKNode`, `SKSpriteNode`, `SKLabelNode`, `SKShapeNode`, `SKAction`, `SKPhysicsBody`, `SKPhysicsWorld`, `SKView`, `SKCameraNode`, and more), running on the wasm-web-kit runtime. Physics is provided by Box2D 2.4.1 (the "Box" in SuperBox64). It ships as a SwiftPM package that vends a module literally named `SpriteKit`, so a game's `import SpriteKit` resolves to this implementation instead of Apple's, with zero changes at the call site. Drop-in shims for `AppKit`, `UIKit`, `Cocoa`, `GameKit`, `GameplayKit`, `GameController`, and `AVFoundation` round out the surface area.

The result: the exact same Swift source that runs as a signed notarized macOS app compiles to a WASI Preview 1 wasm binary that runs in any modern browser and inside native WebViews on Windows, Linux, and Android. No rewrites. No forks. No Emscripten watermarks. No logo you did not design. Your game, your brand, everywhere.

## What We're Building Now

- **SuperBox64 SpriteKit as a standalone open source engine.** The same Swift SpriteKit reimplementation that ships Boss-Man on six platforms is being hardened into a general-purpose engine any SpriteKit game can drop in.
- **2D/3D simulated game engine.** A full simulated rendering pipeline — 2D and 3D — built on top of SuperBox64 SpriteKit. Coming soon.
- **100% common Swift source.** 32 of 33 game files are already symlinked between macOS and wasm. The remaining work is pushing the last platform seam into the framework.
- **Framework-first fixes.** When a port is missing something, the fix lands in wasm-web-kit (the SpriteKit reimplementation), not in a per-game workaround, so the next game inherits it.
- **Voxel far-field fidelity.** The VOXEL mode has a known far-field flaw (jittery blocks and see-through gaps at distance). Live iteration needed.

## Run Everywhere on Anything

Apple's SpriteKit is a walled-garden framework. A game written with `import SpriteKit` normally runs only on Apple platforms. Boss-Man is the proving ground for breaking that lock-in without rewriting the game, without switching engines, and without shipping someone else's branding on your title screen.

The conventional answer is Emscripten: compile your C/C++ with a toolchain that wraps your game in its own runtime shell, injects a loading screen with its own logo, and ships a black-box environment you did not write. SuperBox64 SpriteKit takes the opposite approach. Because it vends a Swift module literally named `SpriteKit`, the exact same Swift source that builds a signed notarized macOS app also compiles to a clean WASI Preview 1 wasm binary. No watermarks. No loading gear. No ads. No branding that is not yours. Just your game, running in any modern browser or native WebView, with a runtime you can read and own.

Thirty-two of thirty-three game files are already one shared source between the macOS and wasm builds — this is not a theory, it is the current shipping build. The runtime adapts the lifecycle (`boot`/`frame`), persistence (localStorage), input (SF key codes), and audio (Web Audio) so the game never has to.

The bigger payoff is a repeatable path to lift any existing SpriteKit game out of the Apple walled garden and ship it cross-platform from a single codebase, cleanly, with no third-party engine in the critical path. Write once for Apple, run everywhere on anything.

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
- **SuperBox64 SpriteKit** — an open source Apple-SpriteKit reimplementation in Swift, compiled to WASM via WASI Preview 1, built from the ground up with no Emscripten.
- **wasm-web-kit** — the WASM runtime and native WebView wrappers that ship the Swift engine to every platform.
- Legacy **Box2D + SFML + C++** port, written by Todd Bruss.
- Original music, graphics, art, sound effects, and game design, all by Todd Bruss.

## Honest Licensing
- Source code is **MIT**. Fork it, learn from it, build with it.
- Binaries remain the property of Todd Bruss.

---

*Copyright 2026 Todd Bruss. [boss-man.us](https://boss-man.us). All rights reserved.*

**Ready to play? Pick your platform and dive in.**
