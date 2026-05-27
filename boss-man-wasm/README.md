# Boss-Man — WebAssembly build

Browser build of the Box2D + SFML C++ game, compiled to WebAssembly with
Emscripten. It does **not** copy the game code: `CMakeLists.txt` compiles the
same sources from `../boss-man-box2d-sfml-cpp/src`, so the native and web builds
never drift. The only platform differences live behind `#ifdef __EMSCRIPTEN__`
(the main loop) and in the SFML backend choice (below).

## Build

Requires the [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html):

```sh
# one-time: install + activate emsdk, then `source ./emsdk_env.sh`
emcmake cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Output: `build/index.html`, `index.js`, `index.wasm`. Serve over HTTP (not
`file://`) to run:

```sh
cd build && python3 -m http.server 8080   # then open http://localhost:8080
```

## How it works

- **Box2D, nlohmann/json** — pure C++, compile to wasm unchanged.
- **Assets** — embedded into the wasm via CMRC (the same `assets/` the native
  build embeds), so there are no extra files to fetch.
- **Main loop** — `Game::run()` uses `emscripten_set_main_loop()` on the web
  (browsers can't block) and the normal `while` loop natively.
- **SFML** — stock SFML has no Emscripten support, so this pulls
  [VRSFML](https://github.com/vittorioromeo/VRSFML), the Emscripten-ready fork.

## Status / known iteration points

This is the scaffold. Expect to iterate on:

1. **VRSFML API drift** — VRSFML has evolved from the SFML 2.6 API the shared
   src targets; some calls (target names, a few signatures) may need small
   tweaks. Watch the first CI build log for the specific errors.
2. **Audio** — SFML audio maps to OpenAL → WebAudio under Emscripten; most
   likely to need attention (autoplay policy: audio starts after a user click).
3. **Fonts/emoji** — embedded PNG emoji work; the CoreText fallback is macOS
   only and already compiled out for non-Apple/web.

The native Windows/Mac/Linux builds are unaffected by anything in this folder.
