<img width="2560" height="1440" alt="Office Space" src="https://github.com/user-attachments/assets/a436e797-3fce-479e-8b31-defac2b0a0e9" />
<img width="2560" height="1440" alt="Ms. Pac-Man Walka Walka" src="https://github.com/user-attachments/assets/6a0bd808-9927-4d79-8b94-014fdb9f6392" />

# Boss-Man

The Video Game — runs on macOS 14.6 or later.
An *Office Space* inspired maze game built with SpriteKit and Swift.

## Download the DMG

https://github.com/macOS26/Boss-Man/releases

## Object of the Game

You are **PETE**, an office worker (blue shirt, orange tie) trapped in a 37×17 grid of cubicles. Each level, you must:

1. **Eat every glowing yellow dot** in the cubicle aisles.
2. **Visit the four office machines** (printer, fax machine, cover sheet stack, book binder) to assemble a TPS report.
3. **Drop the completed TPS report into a TPS Delivery Box** (the brown box) to bank the points.
4. **Avoid the four bosses** patrolling the office.
5. **Grab a Gold Disc** to flip the bosses into Blue Mode for a short window — then chase *them* down for bonus points.

Clear the dots, deliver at least one TPS report, and you advance to the next level.

## Controls

- **Arrow keys** or **WASD** — move PETE
- **Mouse / trackpad** — point-to-move (PETE walks toward the cursor)
- **Space** — start a new round / continue from the title screen
- **ESC** — return to title screen
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

Each boss has its own color, AI personality, and speed — modeled after Ms. Pac-Man's ghosts (Blinky / Pinky / Inky / Sue).

| Boss   | Shirt        | Tie                  | Behavior                                              | Speed |
|--------|--------------|----------------------|-------------------------------------------------------|-------|
| **BILL**  | 🟥 Red        | Black                | Direct chase (Blinky)                                 | 1.00× |
| **DOM**   | 🟪 Pink (75% α over white) | Purple + 40% black | Ambush 4 tiles ahead (Pinky)                          | 0.85× |
| **BOB**   | 🟦 Teal       | Blue + 20% black     | Flanker — pivots 2 tiles off PETE's path (Inky)       | 0.78× |
| **STAN**  | 🟧 Orange     | Red + 10% black      | Timid scatter — backs to corner when too close (Sue)  | 0.70× |

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
- Tunnels are auto-detected — paint a floor gap in the perimeter wall to create a tunnel pair.
- 24 bundled levels. Custom edits save to `~/Library/Application Support/Boss-Man/levels.json`.
- Shortcuts: `⌘S` save · `⌘Z` undo · `⇧⌘Z` redo · `⌘⌫` clear · `⌘C/⌘V` copy/paste level · `⌘P` playtest · `⌘R` reveal file · `← →` previous/next · `ESC` back.
- Autosaves every 60 s, on PREV/NEXT/ESC/PLAY, and on app quit (dirty-check via map hash).
- Duplicate boss types are allowed (e.g. two BOBs) and you can place more than 4 bosses per level.

## Visual Assets

<table>
  <tr>
    <td align="center"><img src="Boss-Man/Resources/red-stapler.png" width="160" alt="Red Stapler"/><br/><sub><code>Boss-Man/Resources/red-stapler.png</code><br/>Title-screen hero stapler.</sub></td>
    <td align="center"><img src="Boss-Man/Resources/shinyredstapler-emoji.png" width="120" alt="Shiny Red Stapler"/><br/><sub><code>Boss-Man/Resources/shinyredstapler-emoji.png</code><br/>Level-6 traveler sprite.</sub></td>
  </tr>
</table>

PETE, the four bosses, and life-icon stand-ins are drawn procedurally by `PixelPerson.swift` — no sprite sheets, no boss PNGs. The app icon lives in `Boss-Man/Resources/AppIcon.icon`.

## Building from Source

This repo holds two implementations of the game:

- **`Boss-Man/`** — the original macOS app, Swift + SpriteKit (this is what the DMG ships).
- **`boss-man-box2d-sfml/`** — a C++ port using **Box2D** for physics and **SFML** for rendering/audio.

### macOS prerequisites

- **Xcode** (Mac App Store) — needed for the Swift/SpriteKit version and provides the Apple toolchain.
- **Xcode Command Line Tools** — `xcode-select --install` (gives you `clang`, `git`, and the macOS SDK frameworks).
- **CMake** — `brew install cmake` (only needed for the C++/SFML version).

You do **not** need to install SFML, Box2D, or nlohmann/json by hand — the CMake build downloads and builds them automatically. The Marker Felt fonts and the stapler image are already bundled in the repo, so there's nothing else to extract.

> No Homebrew? Get it at https://brew.sh, or download CMake manually from https://cmake.org/download and add it to your `PATH`.

### Build the Swift / SpriteKit version (`Boss-Man/`)

Open it in Xcode and press **Run** (⌘R):

```sh
open Boss-Man/Boss-Man.xcodeproj
```

Or from the command line:

```sh
xcodebuild -project Boss-Man/Boss-Man.xcodeproj -scheme Boss-Man -configuration Release build
```

Requires macOS 14.6 or later.

### Build the C++ / Box2D + SFML version (`boss-man-box2d-sfml/`)

```sh
cd boss-man-box2d-sfml
cmake -B build
cmake --build build
```

The first `cmake -B build` downloads SFML 2.6, Box2D 2.4.1, and nlohmann/json via CMake FetchContent (needs an internet connection) and applies a small SFML patch so the window renders at native Retina resolution. Then run it from the project directory (so it finds `assets/`):

```sh
./build/boss-man-pc
```

Press **P** to play, **F** to toggle fullscreen, **ESC** for the title screen.

### Windows & Linux

Build notes for Windows and Linux are **coming soon**. The C++ version is written to be portable — SFML and Box2D are cross-platform, and the macOS-only pieces (CoreText emoji rasterization, native fullscreen) fall back to no-ops elsewhere — so it should build with CMake on those platforms with minor adjustments.

## Made with Agent!

- This arcade-style video game concept was created using **Agent**
- An autonomous agentic AI, for macOS 26.4.1 — https://github.com/macos26/agent
- Fine tuning using Claude Code, and Agent! I use use the right tool for the job.
- Software is deployed using Agent! including release notes and DMGs.
- Music, Graphics, Art, Sound Effects and Game Design by Todd Bruss
- (c) Todd Bruss, InkPen.IO, All Rights Reserved.
- Binaries are property of Todd Bruss, Source code is MIT.
- Box2D + SMFL + Cpp port also by Todd Bruss.
- It currently runs on Mac, but will be testing it on Windows and Linux soon.
