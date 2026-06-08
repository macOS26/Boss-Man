<img width="1247" height="587" alt="image" src="https://github.com/user-attachments/assets/1bfd708b-f376-405a-91c4-01611dd7519c" />

<img width="2561" height="1440" alt="image" src="https://github.com/user-attachments/assets/622014ae-e4b9-431b-b63b-8ea3adc68228" />


# Boss-Man

The office maze arcade game, runs on Mac, Windows, Linux, Web (mobile friendly), and Android. An *Office Space* inspired maze game built in Swift and ported to C++. One interesting aspect is we are actively creating two WebAssembly game engines for Swift and C++. Swift focuses on porting SpriteKit to the web, branded **SuperBox64 SpriteKit**, and our C++ port focuses on using existing C/C++ code with minimal to no code changes. Both WASM game engines use WASI Preview 1.

It runs far beyond the Mac: one shared codebase ships to the browser as WebAssembly (via SuperBox64 SpriteKit) and to Windows, Linux, Android, and the web through a C++ port. See [The Tech](#the-tech-one-game-three-ports-one-framework) below.

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

## The Tech: One Game, Three Ports, One Framework

Boss-Man ships from three codebases that stay in lockstep, plus the framework that makes the web and wasm builds possible.

| Port | Folder | Stack | Targets |
|------|--------|-------|---------|
| **Swift / SpriteKit** (master) | `boss-man-spritekit-swift/` | Swift + Apple SpriteKit | macOS (the signed, notarized DMG) |
| **Swift / WebAssembly** | `boss-man-spritekit-web/` | the *same* Swift, compiled to wasm | any modern browser |
| **C++ / Box2D + SFML** | `boss-man-box2d-sfml-cpp/` | C++17, Box2D 2.4.1, SFML 2.6 | macOS, Windows, Linux, Android, browser |

The Swift macOS project is the single source of truth. The Swift WASM port does not fork the game: 32 of its 33 source files are symlinks straight back to the macOS master, so both builds compile identical Swift. The only port-specific file is `main.swift` (the wasm `boot`/`frame` entry points in place of the macOS `NSApplicationDelegate`). The goal is 100% common game source, with every platform difference pushed down into the framework instead of forked into the game.

### wasm-web-kit

`wasm-web-kit/` runs a native game in the browser as WebAssembly **without Emscripten**. The game is compiled with the WASI SDK clang (`--target=wasm32-wasip1`, WASI Preview 1) and driven by a small hand-written JavaScript runtime (`runtime.js`) that implements graphics on Canvas2D, audio on Web Audio, input on DOM events plus the Web Gamepad API, and persistence on localStorage. No Emscripten, no third-party engine, no branding. You ship your own `index.html`.

The wasm module is a WASI reactor that exports three functions the runtime calls: `_initialize` (libc and C++ constructors), `boot()` (after assets preload), and `frame(dtMs)` (once per `requestAnimationFrame`). Everything else the game imports from a single `env` ABI (`include/abi.h`). Two consumer layers sit on that one ABI:

- **C++ SFML shim.** A header-only `sf::` compatibility layer (shapes, `Sprite`/`Texture`, `Font`/`Text`, `RenderWindow`, `Event`/`Keyboard`/`Mouse`, sound). Point `-I include` at it and an SFML game compiles mostly unchanged. This is how the C++ port reaches the web.
- **SuperBox64 SpriteKit.** See below.

### SuperBox64 SpriteKit

`wasm-web-kit/spritekit/` is a from-scratch Swift reimplementation of Apple's closed SpriteKit (`SKScene`, `SKNode`, `SKSpriteNode`, `SKLabelNode`, `SKShapeNode`, `SKAction`, `SKPhysicsBody`, `SKPhysicsWorld`, `SKView`, `SKCameraNode`, and more), running on the wasm-web-kit runtime with physics provided by Box2D 2.4.1 (the `Box2DBridge` target, the "Box" in SuperBox64). It is a SwiftPM package that vends a module literally named `SpriteKit`, so a game's `import SpriteKit` binds to this reimplementation instead of Apple's framework, with no edits at the call site. It ships matching drop-in shims for `AppKit`, `UIKit`, `Cocoa`, `GameKit`, `GameplayKit`, `GameController`, and `AVFoundation`. That is what lets the macOS Swift game compile to wasm unchanged.

## What We're Building Now

- **100% common Swift source.** 32 of 33 game files are already symlinked between macOS and wasm. The remaining work is pushing the last platform seam into the framework.
- **Cross-platform parity.** A steady stream of sync passes keeps the C++ and wasm ports faithful to the Apple master, down to boss speeds, animation timing, and pixel-level visuals. Recent ports: per-entity boss freeze fix with Chebyshev 3-tile gate, minimap Pete arrow with throb and directional offset, IsoScene arrow (was missing), all applied across Doom/Voxel/Iso in C++.
- **Native Android** via the NDK (SFML `NativeActivity`, drag to steer and tap to fire), built in CI into a downloadable APK.
- **Framework-first fixes.** When a port is missing something, the fix lands in wasm-web-kit (the SpriteKit reimplementation or the SFML shim), not in a per-game workaround, so the next game inherits it.
- **Voxel far-field fidelity.** The VOXEL mode has a known far-field flaw (jittery blocks and see-through gaps at distance) in both Swift and C++. Live iteration needed.

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
