# Headless gameplay tests

Real-input smoke tests: puppeteer-core drives the system Chrome against the
wasm build (trusted keyboard events; DOM-dispatched events do not reach the
runtime, and virtual-time screenshots race the wasm load).

## Setup

```sh
npm install puppeteer-core
```

Serve a directory containing the wasm under test as `bossman.wasm` next to
`runtime-embedded-min.js` (or `runtime.js`), an `index.html` host page and
`assets/`:

```sh
python3 -m http.server 9120 --directory <dir>
```

## drive.js — boot + play smoke test

```sh
node drive.js http://localhost:9120/index.html out-prefix
```

Loads the title, presses Space to start, walks Pete with arrow keys, and
writes `out-prefix-{title,started,played}.png`. A played frame with the score
changed proves the contact pipeline end to end.

## drive-modes.js — all six game modes

```sh
node drive-modes.js http://localhost:9120/index.html outdir
```

Selects each mode by seeding `localStorage BossMan.mazeZoom` (0 wide, 1 zoom,
2 macro, 3 iso, 4 ray, 5 voxel) before load, starts the game, plays a scripted
run per mode (grid moves for 2D/ISO; forward/turn/fire plus a hold-reverse
regression for RAY/VOXEL), and writes four screenshots per mode plus
`modes-report.json` with console errors and a freeze probe.
