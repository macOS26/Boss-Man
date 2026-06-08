# SuperBox64 WASMKit

Run a game in the browser as **WebAssembly — without Emscripten**.

The JavaScript runtime in this repo drives the game loop, implements graphics on Canvas2D (with display-p3 wide color gamut on supporting browsers), audio on Web Audio API, input on DOM events and the Web Gamepad API, and persistence on localStorage. No watermarks. No loading screens. No third-party branding.

**Live demo:** [boss-man.us/play](https://boss-man.us/play)

**Reference game:** [github.com/macOS26/Boss-Man](https://github.com/macOS26/Boss-Man)

---

## What Is in This Repo

| Path | What it is |
|---|---|
| `runtime.js` | The entire JavaScript runtime (Canvas2D renderer, Web Audio mixer, DOM input, asset preloader, gamepad, localStorage persistence) |
| `shell.html` | Minimal host page — set `window.WASMWEB`, serve `runtime.js` next to it |
| `scripts/bundle.py` | Packages a finished wasm + manifest into a single-file `local.html` (all assets inlined as data: URLs for offline / file:/// use) |
| `build.sh` | Build helper for C/C++ games via the WASI SDK — adds the right flags, stack size, reactor model, and kit include path |
| `include/abi.h` | The raw C ABI every game talks through (`gfx_*`, `snd_*`, `key_*`, `evt_*`, `win_*`, `store_*`) |
| `include/SFML/` | Header-only SFML 2.6 compatibility shim so C++ SFML games compile without modification |
| `spritekit/` | [SuperBox64 SpriteKit](spritekit/README.md) — a Swift reimplementation of Apple's SpriteKit that compiles to WASM; the primary way to build games with this kit |

---

## Reactor Contract

The WASM binary is a **WASI Preview 1 reactor** that exports exactly three symbols:

| Export | When | What |
|---|---|---|
| `_initialize` | Once, first | libc/libc++ init and C++ global constructors |
| `boot()` | Once, after all assets preload | Create the game scene |
| `frame(dtMs: f64)` | Every `requestAnimationFrame` | Advance and render one frame |

Everything else (drawing, sound, input, persistence) is **imported** from the `env` module. See `include/abi.h` for the full contract.

---

## ABI Reference (`include/abi.h`)

### Graphics

| Function | Description |
|---|---|
| `gfx_clear(rgba)` | Clear the canvas to a color |
| `gfx_fill_rect(x, y, w, h, rgba)` | Filled rectangle |
| `gfx_stroke_rect(x, y, w, h, rgba, lw)` | Stroked rectangle |
| `gfx_fill_circle(cx, cy, r, rgba)` | Filled circle |
| `gfx_stroke_circle(cx, cy, r, rgba, lw)` | Stroked circle |
| `gfx_fill_path(pts, n, rgba)` | Filled polygon |
| `gfx_stroke_path(pts, n, rgba, lw)` | Stroked polyline |
| `gfx_draw_image(id, x, y, w, h, alpha)` | Draw a preloaded image |
| `gfx_draw_image_ex(id, sx,sy,sw,sh, dx,dy,dw,dh, alpha)` | Draw image with source crop |
| `gfx_set_transform(a,b,c,d,tx,ty)` | Set canvas 2D transform |
| `gfx_reset_transform()` | Reset to identity |
| `gfx_offscreen_begin(id, w, h, alpha)` | Start rendering to an offscreen canvas |
| `gfx_offscreen_end()` | Return to main canvas |
| `gfx_offscreen_draw(id, x, y, w, h, alpha)` | Draw offscreen canvas to main |

### Text

| Function | Description |
|---|---|
| `txt_measure(ptr, len, font_ptr, font_len, size) → width` | Measure text width |
| `txt_draw(ptr, len, x, y, font_ptr, font_len, size, rgba, align)` | Draw text |

### Sound

| Function | Description |
|---|---|
| `snd_play(id, volume, loop)` | Play a preloaded sound |
| `snd_stop(id)` | Stop a sound |
| `snd_set_volume(id, volume)` | Set playback volume |
| `snd_is_playing(id) → bool` | Query playback state |
| `snd_tts(ptr, len, rate, pitch, volume)` | Text-to-speech via Web Speech API |

### Input

| Function | Description |
|---|---|
| `key_pressed(keycode) → bool` | Is a keyboard key currently held |
| `key_just_pressed(keycode) → bool` | Was a key pressed this frame |
| `key_just_released(keycode) → bool` | Was a key released this frame |
| `mouse_x() → f64` | Mouse X in logical coordinates |
| `mouse_y() → f64` | Mouse Y in logical coordinates |
| `mouse_button(btn) → bool` | Is a mouse button held |
| `pad_axis(pad, axis) → f64` | Gamepad axis value |
| `pad_button(pad, btn) → bool` | Gamepad button state |

### Events

| Function | Description |
|---|---|
| `evt_poll(out_ptr) → type` | Poll the next input event off the queue |

### Window

| Function | Description |
|---|---|
| `win_width() → f64` | Logical canvas width |
| `win_height() → f64` | Logical canvas height |
| `win_dpr() → f64` | Device pixel ratio |
| `win_fullscreen_enter()` | Request fullscreen |
| `win_fullscreen_exit()` | Exit fullscreen |

### Persistence

| Function | Description |
|---|---|
| `store_set(key_ptr, key_len, val_ptr, val_len)` | Write a string to localStorage |
| `store_get(key_ptr, key_len, out_ptr, max_len) → len` | Read from localStorage |
| `store_del(key_ptr, key_len)` | Delete a localStorage entry |

---

## Host Page

Copy `shell.html`, set `window.WASMWEB`, and serve `runtime.js` alongside it:

```html
<script>
  window.WASMWEB = {
    logicalWidth: 1184,
    logicalHeight: 666,
    wasmUrl: 'game.wasm',
    assetRoot: 'assets',
    title: 'My Game'
  };
</script>
<script src="runtime.js"></script>
```

The runtime preloads every asset listed in `manifest.json` (fonts via `FontFace`, images via `ImageBitmap`, sounds via `AudioBuffer`, JSON as strings) before calling `boot()`, then runs the frame loop via `requestAnimationFrame`.

---

## Display-P3 Wide Color

On Safari, Chrome 104+, and WebKit-based WebViews, the runtime automatically negotiates a display-p3 Canvas2D context. Color components passed through the ABI are reinterpreted as P3 coordinates rather than sRGB, producing more vivid reds, greens, and yellows on wide-gamut displays. No game-side changes are needed.

---

## Using the Swift SpriteKit Layer

For games written in Swift using SpriteKit, see [`spritekit/`](spritekit/README.md). This is the recommended path for new games. The game's `import SpriteKit` resolves to the SuperBox64 reimplementation when building for WASM and Apple's native framework on macOS/iOS, from the same source.

---

## Using the C++ SFML Shim

For existing C++ games using SFML 2.6, point `-I include` at this repo's `include/` directory. The shim covers the common 2D subset: `sf::RenderWindow`, `sf::Sprite`, `sf::Texture`, `sf::Font`, `sf::Text`, `sf::Shape`, `sf::Sound`, `sf::Music`, `sf::Event`, `sf::Keyboard`, `sf::Mouse`.

Build via `build.sh`:

```bash
WASMWEB_OUT=web/game.wasm
WASMWEB_SRC_DIRS=(src)
WASMWEB_SFML=on
source ../superbox64-wasmkit/build.sh
wasmweb_build
```

---

## Related

- [superbox64-spritekit](https://github.com/macOS26/superbox64-spritekit) — the Swift SpriteKit package
- [Boss-Man](https://github.com/macOS26/Boss-Man) — the arcade game built with this engine, shipping on 6 platforms from one Swift source
