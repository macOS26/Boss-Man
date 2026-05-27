# wasm-web-kit

Run a C/C++ game in the browser as **WebAssembly — without Emscripten**.

The game is compiled with the [WASI SDK](https://github.com/WebAssembly/wasi-sdk)
(`clang --target=wasm32-wasip1`) and driven by a small hand-rolled JavaScript
runtime that implements graphics on **Canvas2D**, audio on **WebAudio**, and
input on **DOM events**. No Emscripten, no third-party game engine, no branding —
you ship your own `index.html`.

## How it fits together

```
your C/C++ game  ──(WASI SDK clang)──▶  game.wasm  ◀──(loads)──  runtime.js
        │                                                            │
        └── calls the ABI (include/abi.h): ───────────────▶ implemented on
            gfx_* / txt_* / snd_* / key/mouse/evt / win_* / store_*   Canvas2D + WebAudio + DOM
```

Your module is a **WASI reactor** that exports three functions the runtime calls:

| export | when | does |
|---|---|---|
| `_initialize` | once, first | libc/libc++ init + C++ global constructors |
| `boot()` | once, after assets preload | create your game |
| `frame(double dtMs)` | every `requestAnimationFrame` | advance + render one frame |

Everything else (drawing, sound, input, persistence) the game **imports** from the
`env` module — see [`include/abi.h`](include/abi.h) for the full contract.

## Two ways to use it

**1. SFML 2.6 game (drop-in).** The kit ships a header-only `sf::` compatibility
layer (`include/SFML/...`) covering the common 2D subset (shapes, `Sprite`/
`Texture`, `Font`/`Text`, `RenderWindow`/`RenderTexture`, `Transform`/
`RenderStates`/`BlendMode`, `Event`/`Keyboard`/`Mouse`, `SoundBuffer`/`Sound`/
`Music`). Point `-I include` at it and your SFML game compiles mostly unchanged.
Provide `boot()`/`frame()` (split your blocking `run()` loop into one-frame
`tick()`s — see the BOSS-MAN example).

**2. Any C/C++ game (raw ABI).** Set `WASMWEB_SFML=off` and call the `abi.h`
functions directly (`gfx_fill_rect`, `gfx_draw_image`, `snd_play`, `key_pressed`,
`evt_poll`, …). No SFML needed.

## Build

From your game's build script:

```bash
WASMWEB_OUT=web/game.wasm
WASMWEB_SRC_DIRS=(src)                 # scanned for *.cpp / *.c
WASMWEB_EXTRA_SRCS=(deps/foo.cpp)      # explicit extra sources
WASMWEB_INCLUDES=(src deps/include)    # extra -I dirs
WASMWEB_DEFINES=(MY_WEB_BUILD)         # extra -D
WASMWEB_EXCEPTIONS=off                 # WASI libc++ is legacy-EH; off is default
WASMWEB_SFML=on                        # link the sf:: layer (off = raw ABI)
WASMWEB_ASSETS=assets                  # optional: auto-generate manifest.json
WASMWEB_MANIFEST=web/manifest.json
source ../wasm-web-kit/build.sh
wasmweb_build
```

`build.sh` adds the WASI flags, an 8 MiB stack (deep solvers/recursion need it),
the reactor model, and the kit include path; then links `game.wasm`.

## Host page

Copy [`shell.html`](shell.html), set `window.WASMWEB` (logical size, `wasmUrl`,
`assetRoot`, `title`), and serve `runtime.js` next to it. The runtime preloads
everything in `manifest.json` (fonts → `FontFace`, images → `ImageBitmap`, sounds
→ `AudioBuffer`, text → strings) **before** calling `boot()`, then runs the frame
loop. The canvas backing store is sized to the display × `devicePixelRatio` and
the logical coordinate space is scaled into it (crisp at any size; letterboxed in
fullscreen via `object-fit: contain`).

### Asset layout convention (for auto-manifest)

```
assets/
  fonts/*.ttf|otf      images/*.png|jpg      emoji/*.png
  voice/*.wav          sfx/*.wav|ogg         *.json   (e.g. levels.json)
```

Assets resolve by **basename** (no extension), so `loadFromFile("a/b/foo.png")`
finds the preloaded `foo`. SFX that the game synthesizes at runtime
(`sf::SoundBuffer::loadFromSamples`) need no files — the PCM is uploaded straight
to a WebAudio buffer.

## Notes / limits

- **Exceptions off by default.** The WASI sysroot's libc++ uses legacy EH, which
  can't link with `-fwasm-exceptions`. Keep `-fno-exceptions`; for JSON etc. use
  non-throwing APIs (`nlohmann::json::parse(s, nullptr, false)` + `-DJSON_NOEXCEPTION`).
- `sf::View` is identity on web (the canvas *is* the logical surface);
  `mapPixelToCoords` returns the input.
- `sf::Image` holds CPU RGBA (works for `create`/`getPixel`), but `loadFromFile`
  into an `Image` returns false — load images as `Texture`/`Sprite` instead.

## Reference implementation

[`../boss-man-web`](../boss-man-web) builds BOSS-MAN (Box2D + SFML 2.6, ~60 source
files) to the web through this kit — its `build-web.sh` and `web/index.html` are a
complete worked example.
