// wasm-web-kit runtime. Hand-rolled, no Emscripten: loads a wasm32-wasi module
// built with the WASI SDK, provides the WASI preview1 syscalls the binary
// references, and implements the include/abi.h `env` contract on Canvas2D +
// WebAudio + DOM input. The module is a reactor exporting _initialize/boot/frame.
//
// The host page sets window.WASMWEB = { logicalWidth, logicalHeight, wasmUrl,
// assetRoot, canvasId, title } before loading this script (see shell.html), so
// the same runtime drives any C/C++ game.

'use strict';

// ============================================================================
// sf::Keyboard::Key  ->  DOM mapping
// ----------------------------------------------------------------------------
// SFML 2.6 sf::Keyboard::Key enum numeric values (fixed by the SFML ABI). The
// C++ Window/Event.hpp web shim passes these same integers to key_pressed() and
// stamps them into KeyPressed/KeyReleased events. Keep this table in lockstep
// with that header. We map only the keys BOSS-MAN actually uses; everything
// else returns "not pressed".
//
//   Letters:  A=0 B=1 C=2 D=3 E=4 F=5 ... P=15 R=17 S=18 V=21 W=22 Z=25
//   Num row:  Num0=26 Num1=27 ... Num9=35
//   Escape=36  Space=57  BackSpace=59
//   Left=71  Right=72  Up=73  Down=74
//   Numpad0=75 Numpad1=76 ... Numpad8=83
// (Full enum: https://www.sfml-dev.org/documentation/2.6.1/Keyboard_8hpp.html)
// ============================================================================
// Ramer-Douglas-Peucker polyline simplification (used by img_polygon_from_alpha).
// Drops vertices whose perpendicular distance to the chord is below `epsilon`.
function rdpSimplify(points, epsilon) {
  if (points.length < 3) return points.slice();
  const sqr = (a) => a * a;
  const distSq = (p, a, b) => {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    if (dx === 0 && dy === 0) return sqr(p[0] - a[0]) + sqr(p[1] - a[1]);
    const t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx*dx + dy*dy);
    const tt = Math.max(0, Math.min(1, t));
    return sqr(p[0] - (a[0] + tt * dx)) + sqr(p[1] - (a[1] + tt * dy));
  };
  const eps2 = epsilon * epsilon;
  const keep = new Uint8Array(points.length);
  keep[0] = 1; keep[points.length - 1] = 1;
  const stack = [[0, points.length - 1]];
  while (stack.length) {
    const [s, e] = stack.pop();
    let maxD = 0, maxI = -1;
    for (let i = s + 1; i < e; i++) {
      const d = distSq(points[i], points[s], points[e]);
      if (d > maxD) { maxD = d; maxI = i; }
    }
    if (maxD > eps2 && maxI > 0) {
      keep[maxI] = 1;
      stack.push([s, maxI], [maxI, e]);
    }
  }
  const out = [];
  for (let i = 0; i < points.length; i++) if (keep[i]) out.push(points[i]);
  return out;
}

const SF_KEY = {
  // SFML enum order: A..Z = 0..25, Num0..Num9 = 26..35. Filling the map
  // out fully so games can read full alphanumeric input (username entry,
  // level editor letter palette, etc.) — partial map used to drop B/G/H/...
  // and Return on the floor.
  0: 'KeyA',  1: 'KeyB',  2: 'KeyC',  3: 'KeyD',  4: 'KeyE',  5: 'KeyF',
  6: 'KeyG',  7: 'KeyH',  8: 'KeyI',  9: 'KeyJ', 10: 'KeyK', 11: 'KeyL',
  12: 'KeyM', 13: 'KeyN', 14: 'KeyO', 15: 'KeyP', 16: 'KeyQ', 17: 'KeyR',
  18: 'KeyS', 19: 'KeyT', 20: 'KeyU', 21: 'KeyV', 22: 'KeyW', 23: 'KeyX',
  24: 'KeyY', 25: 'KeyZ',
  26: 'Digit0', 27: 'Digit1', 28: 'Digit2', 29: 'Digit3', 30: 'Digit4',
  31: 'Digit5', 32: 'Digit6', 33: 'Digit7', 34: 'Digit8', 35: 'Digit9',
  36: 'Escape',
  57: 'Space',
  58: 'Enter',
  59: 'Backspace',
  71: 'ArrowLeft', 72: 'ArrowRight', 73: 'ArrowUp', 74: 'ArrowDown',
  75: 'Numpad0', 76: 'Numpad1', 77: 'Numpad2', 78: 'Numpad3', 79: 'Numpad4',
  80: 'Numpad5', 81: 'Numpad6', 82: 'Numpad7', 83: 'Numpad8',
};

// Reverse map: DOM KeyboardEvent.code -> sf::Keyboard code. Built from SF_KEY so
// keydown/keyup can record presses and stamp events with the right enum int.
const DOM_TO_SF = (() => {
  const m = new Map();
  for (const k of Object.keys(SF_KEY)) m.set(SF_KEY[k], Number(k));
  return m;
})();

// ============================================================================
// sf::Event::EventType  ->  integer (SFML 2.6 order, fixed by the ABI)
// ----------------------------------------------------------------------------
//   Closed=0 Resized=1 LostFocus=2 GainedFocus=3 TextEntered=4
//   KeyPressed=5 KeyReleased=6 MouseWheelMoved=7 MouseWheelScrolled=8
//   MouseButtonPressed=9 MouseButtonReleased=10 MouseMoved=11 ...
// evt_poll fills {type,a,b,c,d}:
//   KeyPressed/KeyReleased:   a=sfKeyCode b=shift(0/1) c=system/cmd(0/1) d=0
//   MouseButtonPressed/Released: a=button(0=L,1=R) b=x c=y d=0
//   MouseMoved:               a=x b=y
//   Resized:                  a=width b=height
//   Closed:                   (no payload)
// ============================================================================
const EVT = {
  Closed: 0, Resized: 1, LostFocus: 2, GainedFocus: 3, TextEntered: 4,
  KeyPressed: 5, KeyReleased: 6, MouseWheelMoved: 7, MouseWheelScrolled: 8,
  MouseButtonPressed: 9, MouseButtonReleased: 10, MouseMoved: 11,
};

// Per-game configuration. The host page sets window.WASMWEB before loading this
// script; anything omitted falls back to these defaults. This is what makes the
// runtime reusable for any C/C++ game (not just BOSS-MAN).
const CFG = Object.assign({
  logicalWidth: 1184,     // the game's fixed logical render width
  logicalHeight: 666,     // ...and height (backing store keeps this aspect)
  wasmUrl: 'game.wasm',   // reactor module exporting _initialize/boot/frame
  assetRoot: '../assets', // where preloaded assets + manifest.json live
  canvasId: 'game',       // <canvas> element id
  title: null,            // optional document.title
}, (typeof window !== 'undefined' && window.WASMWEB) || {});

const LOGICAL_W = CFG.logicalWidth;
const LOGICAL_H = CFG.logicalHeight;

// iOS Safari only lets Web Speech run inside a user gesture, so event-driven game
// voice lines never play reliably. Disable TTS (and its priming) on iOS entirely.
const IS_IOS = typeof navigator !== 'undefined' &&
  (/iP(hone|od|ad)/.test(navigator.userAgent) ||
   (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1));

// Asset roots, relative to web/index.html.
const ASSET_ROOT = CFG.assetRoot;

class Runtime {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d', { alpha: false });

    this.wasmMemory = null;
    this.exports = null;
    this.textDecoder = new TextDecoder('utf-8');
    this.textEncoder = new TextEncoder();

    // ---- graphics targets ----
    // targets[0] is the main canvas context. targets[h>0] are offscreen
    // canvases minted by rt_create. Each entry: { canvas, ctx }.
    this.targets = [{ canvas, ctx: this.ctx }];
    this.curTarget = 0;

    // gfx_set_text_baseline persists the canvas2D textBaseline used by
    // gfx_draw_text. Default 2 = 'top' so callers that never call the new
    // ABI get the historic behaviour. SK .center alignment sets it to 1
    // ('middle') so emoji glyphs centre on their anchor.
    this._textBaselineMode = 2;

    // TTS voice preference. tts_set_preferred_voices feeds these; the
    // picker resolves to a real SpeechSynthesisVoice on first tts_speak
    // and caches the result. Robotic / novelty voices excluded.
    this._ttsPreferred = [];
    this._ttsRobotic = [];
    this._ttsFemale = [];
    this._ttsVoice = null;
    this._ttsPending = [];
    if (typeof speechSynthesis !== 'undefined') {
      // Kick the voice list — Chrome only populates on first access.
      speechSynthesis.getVoices();
      // Opt-in test helpers (no auto console output): window.bossmanVoices()
      // lists voices on demand; window.bossmanTry('name') speaks a sample.
      window.bossmanVoices = () => speechSynthesis.getVoices().map((x) => ({ name: x.name, lang: x.lang, default: x.default }));
      window.bossmanTry = (frag, text) => {
        const x = speechSynthesis.getVoices().find((y) => (y.name || '').toLowerCase().includes((frag || '').toLowerCase()));
        const u = new SpeechSynthesisUtterance(text || 'Did you get the memo about the TPS reports?');
        if (x) u.voice = x;
        u.rate = 0.85; u.pitch = 0.55;
        speechSynthesis.speak(u);
        return x ? x.name : '(no match — default voice)';
      };
      // Voices populate asynchronously on every browser; reset cache and
      // flush any utterances that were queued while it was still empty.
      speechSynthesis.onvoiceschanged = () => {
        this._ttsVoice = null;
        const v = this._pickTTSVoice();
        if (!v || !this._ttsPending.length) return;
        const pending = this._ttsPending; this._ttsPending = [];
        for (const u of pending) {
          u.voice = v;
          try { speechSynthesis.speak(u); } catch (_e) {}
        }
      };
    }

    // ---- handle tables (1-based; 0 means "not loaded/none") ----
    this.images = [null];   // each: { source, width, height }  source = drawable
    this.shaders = [null];  // each: { program, uniformLocs, srcText }
    this.engineNodes = [];  // AVAudioEngine nodes (player/mixer)
    this.glCanvas = null;   // hidden WebGL2 offscreen canvas (lazily created)
    this.gl = null;         // WebGL2 context (lazily created)
    this.glQuadVAO = null;  // shared full-quad VAO for shader/lighting passes
    this.glTexFromImage = new Map();   // imgId -> WebGLTexture cache
    this.fonts = [null];    // each: family string ; index 0 is implicit default
    this.sounds = [null];   // each: AudioBuffer
    this.imageByName = new Map();
    this.soundByName = new Map();
    this.fontByName = new Map();
    this.texts = new Map();   // text assets (levels.json, ...) for asset_text

    // ---- audio ----
    this.audioCtx = null;
    this.voices = new Map();   // voice handle -> { source, gain, base, state }
    this.nextVoice = 1;
    this.duckFactor = 1;       // 1 = normal; <1 ducks music/SFX while a TTS voice speaks

    // ---- input ----
    this.pressed = new Set();        // DOM codes currently down
    this.mouseDown = [false, false]; // [left, right]
    this.mouseX = 0;
    this.mouseY = 0;

    // logical->backing-store transform (set by layout())
    this.baseScale = 1;
    this.offX = 0;
    this.offY = 0;
    this.events = [];                // queued {type,a,b,c,d}

    // Gamepad / USB arcade joystick state. We poll navigator.getGamepads()
    // once per frame and remember the previous button states so we can detect
    // edges and emit synthetic keydown/keyup events when key-mapping is on.
    this.gpEnabled = true;          // master poll switch
    this.gpMapToKeys = true;        // synthesize arrow/space keys from d-pad/stick
    this.gpAxisDeadzone = 0.35;     // threshold above which a stick "presses" a direction
    this.gpPrev = [null, null, null, null];   // last frame's {buttons:[0/1], axesDir:{up,down,left,right}}

    // default font handle 0 maps to a monospace stack
    this.defaultFontFamily = 'JetBrainsMono-Bold, ui-monospace, Menlo, monospace';
  }

  // --------------------------------------------------------------------------
  // memory helpers (re-create the view each call: wasm memory may have grown)
  // --------------------------------------------------------------------------
  dv() { return new DataView(this.wasmMemory.buffer); }
  u8(ptr, len) { return new Uint8Array(this.wasmMemory.buffer, ptr, len); }
  cstr(ptr, len) { return this.textDecoder.decode(this.u8(ptr, len)); }

  // ==========================================================================
  // WASI preview1 (only what the binary imports)
  // ==========================================================================
  wasiImports() {
    const WASI_EBADF = 8;
    return {
      fd_write: (fd, iovsPtr, iovsLen, nwrittenPtr) => {
        const dv = this.dv();
        const parts = [];
        let total = 0;
        for (let i = 0; i < iovsLen; i++) {
          const base = iovsPtr + i * 8;
          const ptr = dv.getUint32(base, true);
          const len = dv.getUint32(base + 4, true);
          parts.push(this.textDecoder.decode(this.u8(ptr, len)));
          total += len;
        }
        const text = parts.join('').replace(/\n$/, '');
        if (text.length) (fd === 2 ? console.error : console.log)('[wasm] ' + text);
        dv.setUint32(nwrittenPtr, total, true);
        return 0;
      },
      fd_read: (_fd, _iovsPtr, _iovsLen, nreadPtr) => {
        this.dv().setUint32(nreadPtr, 0, true);
        return 0;
      },
      fd_close: () => 0,
      fd_seek: (_fd, _offLo, _offHi, _whence, newOffsetPtr) => {
        // write a zeroed 64-bit offset so callers never read garbage
        const dv = this.dv();
        dv.setUint32(newOffsetPtr, 0, true);
        dv.setUint32(newOffsetPtr + 4, 0, true);
        return 0;
      },
      fd_prestat_get: () => WASI_EBADF,
      fd_prestat_dir_name: () => WASI_EBADF,
      fd_fdstat_get: (_fd, statPtr) => {
        // zero the fdstat (24 bytes) so libc sees a benign descriptor
        const dv = this.dv();
        for (let i = 0; i < 24; i++) dv.setUint8(statPtr + i, 0);
        return 0;
      },
      environ_sizes_get: (countPtr, sizePtr) => {
        const dv = this.dv();
        dv.setUint32(countPtr, 0, true);
        dv.setUint32(sizePtr, 0, true);
        return 0;
      },
      environ_get: () => 0,
      args_sizes_get: (countPtr, sizePtr) => {
        const dv = this.dv();
        dv.setUint32(countPtr, 0, true);
        dv.setUint32(sizePtr, 0, true);
        return 0;
      },
      args_get: () => 0,
      // No virtual filesystem: opening any path fails with ENOENT(44). The Swift
      // runtime references path_open but does not actually open files here.
      path_open: () => 44,
      clock_time_get: (_id, _precision, timePtr) => {
        const ns = BigInt(Math.round(performance.now() * 1e6));
        this.dv().setBigUint64(timePtr, ns, true);
        return 0;
      },
      // Clock resolution in nanoseconds. The Swift concurrency runtime (linked
      // the moment any @MainActor executor code runs, e.g. MainActor.assumeIsolated)
      // imports this; report performance.now()'s ~1us granularity.
      clock_res_get: (_id, resPtr) => {
        this.dv().setBigUint64(resPtr, 1000n, true);
        return 0;
      },
      random_get: (ptr, len) => {
        const bytes = this.u8(ptr, len);
        crypto.getRandomValues(bytes);
        return 0;
      },
      proc_exit: (code) => { throw new Error('wasm proc_exit(' + code + ')'); },
      poll_oneoff: (_in, _out, _nsub, neventsPtr) => {
        this.dv().setUint32(neventsPtr, 0, true);
        return 0;
      },
      sched_yield: () => 0,
    };
  }

  // ==========================================================================
  // env imports (platform/web/abi.h)
  // ==========================================================================
  envImports() {
    return {
      // C++ exception runtime stubs. With -fno-exceptions on Box2DBridge
      // these shouldn't be reached, but they keep wasm instantiation alive
      // if a stray throw slips in (third-party C++ deps, etc.). __cxa_throw
      // surfaces with a console error + JS throw so a real C++ throw still
      // becomes visible in DevTools.
      __cxa_allocate_exception: (_size) => 0,
      __cxa_throw: (_ptr, _type, _dtor) => {
        console.error('[boss] __cxa_throw reached — uncaught C++ exception in wasm');
        throw new Error('uncaught C++ exception from wasm');
      },

      // ---- logging ----
      js_log: (ptr, len) => {
        console.log('%c[boss] ' + this.cstr(ptr, len), 'color:#e6b800');
      },

      // ---- target + transform/blend ----
      gfx_target: (target) => {
        this.curTarget = (target > 0 && target < this.targets.length) ? target : 0;
      },
      gfx_clear: (rgba) => {
        const c = this.ctx2d();
        c.setTransform(1, 0, 0, 1, 0, 0);
        c.globalAlpha = 1;
        c.globalCompositeOperation = 'source-over';
        c.fillStyle = this.css(rgba);
        c.fillRect(0, 0, c.canvas.width, c.canvas.height);
        // The screen target draws in logical (1184x644) coords scaled up to the
        // hi-res backing store (crisp at any size, letterboxed). Render textures
        // are logical-sized, so they stay at identity.
        if (this.curTarget === 0) c.setTransform(this.baseScale, 0, 0, this.baseScale, this.offX, this.offY);
      },
      gfx_save: () => this.ctx2d().save(),
      gfx_restore: () => this.ctx2d().restore(),
      gfx_translate: (x, y) => this.ctx2d().translate(x, y),
      gfx_snap_translation: () => {
        // Round the live transform's translation to whole device pixels. The
        // scale stays fractional (full-res), but a scrolling camera now shifts
        // content by whole pixels, so a repeating tile grid keeps a constant
        // sub-pixel phase instead of shimmering on low-DPR desktops.
        const c = this.ctx2d();
        const m = c.getTransform();
        m.e = Math.round(m.e);
        m.f = Math.round(m.f);
        c.setTransform(m);
      },
      gfx_scale: (sx, sy) => this.ctx2d().scale(sx, sy),
      gfx_rotate: (deg) => this.ctx2d().rotate(deg * Math.PI / 180),
      gfx_set_alpha: (a) => { this.ctx2d().globalAlpha = a; },
      gfx_set_blend: (mode) => {
        const c = this.ctx2d();
        switch (mode) {
          case 1: c.globalCompositeOperation = 'lighter'; break;
          case 2: c.globalCompositeOperation = 'multiply'; break;
          case 3: c.globalCompositeOperation = 'source-over'; c.globalAlpha = 1; break;
          default: c.globalCompositeOperation = 'source-over'; break;
        }
      },

      // ---- primitives ----
      gfx_fill_rect: (x, y, w, h, rgba) => {
        const c = this.ctx2d();
        c.fillStyle = this.css(rgba);
        c.fillRect(x, y, w, h);
      },
      gfx_stroke_rect: (x, y, w, h, thickness, rgba) => {
        const c = this.ctx2d();
        c.lineWidth = thickness;
        c.strokeStyle = this.css(rgba);
        c.strokeRect(x, y, w, h);
      },
      gfx_fill_circle: (cx, cy, r, rgba) => {
        const c = this.ctx2d();
        c.fillStyle = this.css(rgba);
        c.beginPath();
        c.arc(cx, cy, r, 0, Math.PI * 2);
        c.fill();
      },
      gfx_stroke_circle: (cx, cy, r, thickness, rgba) => {
        const c = this.ctx2d();
        c.lineWidth = thickness;
        c.strokeStyle = this.css(rgba);
        c.beginPath();
        c.arc(cx, cy, r, 0, Math.PI * 2);
        c.stroke();
      },
      gfx_fill_poly: (xyPtr, npts, rgba) => {
        if (npts < 2) return;
        const c = this.ctx2d();
        const dv = this.dv();
        c.fillStyle = this.css(rgba);
        c.beginPath();
        c.moveTo(dv.getFloat32(xyPtr, true), dv.getFloat32(xyPtr + 4, true));
        for (let i = 1; i < npts; i++) {
          c.lineTo(dv.getFloat32(xyPtr + i * 8, true), dv.getFloat32(xyPtr + i * 8 + 4, true));
        }
        c.closePath();
        c.fill();
      },
      gfx_stroke_poly: (xyPtr, npts, closed, thickness, rgba) => {
        if (npts < 2) return;
        const c = this.ctx2d();
        const dv = this.dv();
        c.strokeStyle = this.css(rgba);
        c.lineWidth = thickness;
        c.lineJoin = 'round';
        c.beginPath();
        c.moveTo(dv.getFloat32(xyPtr, true), dv.getFloat32(xyPtr + 4, true));
        for (let i = 1; i < npts; i++) {
          c.lineTo(dv.getFloat32(xyPtr + i * 8, true), dv.getFloat32(xyPtr + i * 8 + 4, true));
        }
        if (closed) c.closePath();
        c.stroke();
      },

      // ---- textured quad ----
      gfx_draw_image: (img, sx, sy, sw, sh, dx, dy, dw, dh, rgba) => {
        const rec = this.images[img];
        if (!rec) return;
        const c = this.ctx2d();
        const a = (rgba & 0xFF) / 255;
        const prevAlpha = c.globalAlpha;
        c.globalAlpha = prevAlpha * a;
        try {
          // sw or sh < 0 is our "use the full source" sentinel — SKSpriteNode
          // passes -1/-1 when no sub-rect is set, and the 9-arg drawImage
          // throws on negative source dimensions, so we route to the 5-arg
          // form (dst-only). Before this fix, the catch below silently ate
          // the throw and the sprite rendered as nothing.
          if (sw < 0 || sh < 0) {
            c.drawImage(rec.source, dx, dy, dw, dh);
          } else {
            c.drawImage(rec.source, sx, sy, sw, sh, dx, dy, dw, dh);
          }
        } catch (_e) { /* zero-size src/dst */ }
        c.globalAlpha = prevAlpha;
      },

      // ---- text ----
      txt_width: (font, ptr, len, sizePx, letterSpacing) => {
        const c = this.ctx2d();
        const s = this.cstr(ptr, len);
        this.applyFont(c, font, sizePx, letterSpacing);
        let w = c.measureText(s).width;
        if (!this.hasLetterSpacing && letterSpacing) {
          w += letterSpacing * Math.max(0, [...s].length - 1);
        }
        return Math.ceil(w);
      },
      gfx_set_text_baseline: (mode) => {
        // Persisted on the Game so a draw call can read it back. 0=alphabetic,
        // 1=middle (visual centre — what SK .center wants), 2=top, 3=bottom.
        // Defaults back to 'top' after every draw to preserve historic
        // behaviour for callers that don't touch it.
        this._textBaselineMode = mode | 0;
      },
      gfx_draw_text: (font, ptr, len, x, y, sizePx, rgba, letterSpacing) => {
        const c = this.ctx2d();
        const s = this.cstr(ptr, len);
        this.applyFont(c, font, sizePx, letterSpacing);
        c.textAlign = 'left';
        c.fillStyle = this.css(rgba);
        const mode = this._textBaselineMode | 0;
        // Visual centring (mode 1): Canvas2D 'middle' uses the em-box
        // geometric centre, but emoji glyphs sit a couple of pixels above
        // the em centre, so they read as too-high. Compute the actual ink
        // bounds via measureText and offset the alphabetic baseline so
        // the visible-glyph centroid lands on the requested y.
        if (mode === 1) {
          c.textBaseline = 'alphabetic';
          const m = c.measureText(s);
          const ascent = m.actualBoundingBoxAscent || sizePx * 0.8;
          const descent = m.actualBoundingBoxDescent || sizePx * 0.2;
          const yb = y + (ascent - descent) / 2;
          if (this.hasLetterSpacing || !letterSpacing) {
            c.fillText(s, x, yb);
          } else {
            let cx = x;
            for (const ch of s) {
              c.fillText(ch, cx, yb);
              cx += c.measureText(ch).width + letterSpacing;
            }
          }
          return;
        }
        c.textBaseline =
          mode === 2 ? 'top' :
          mode === 3 ? 'bottom' :
          mode === 0 ? 'alphabetic' : 'top';
        if (this.hasLetterSpacing || !letterSpacing) {
          c.fillText(s, x, y);
        } else {
          let cx = x;
          for (const ch of s) {
            c.fillText(ch, cx, y);
            cx += c.measureText(ch).width + letterSpacing;
          }
        }
      },

      // ---- images / fonts / render textures ----
      img_by_name: (ptr, len) => {
        const name = this.cstr(ptr, len);
        return this.lookupImage(name);
      },
      img_from_rgba: (ptr, w, h) => {
        const bytes = this.u8(ptr, w * h * 4).slice();
        const cv = document.createElement('canvas');
        cv.width = w; cv.height = h;
        const cc = cv.getContext('2d');
        const id = new ImageData(new Uint8ClampedArray(bytes.buffer), w, h);
        cc.putImageData(id, 0, 0);
        this.images.push({ source: cv, width: w, height: h });
        return this.images.length - 1;
      },
      img_width: (img) => { const r = this.images[img]; return r ? r.width : 0; },
      img_height: (img) => { const r = this.images[img]; return r ? r.height : 0; },
      font_by_name: (ptr, len) => {
        const name = this.cstr(ptr, len);
        return this.lookupFont(name);
      },
      asset_exists: (ptr, len) => {
        const name = this.cstr(ptr, len);
        const base = this.basename(name);
        const has = (m) => m.has(name) || m.has(base);
        return (has(this.soundByName) || has(this.imageByName) ||
                has(this.fontByName) || this.texts.has(name) || this.texts.has(base)) ? 1 : 0;
      },
      asset_text: (ptr, nlen, bufPtr, cap) => {
        const name = this.cstr(ptr, nlen);
        const s = this.texts.get(name);
        if (s === undefined) return -1;
        const bytes = this.textEncoder.encode(s);
        if (cap > 0 && bufPtr) {
          const n = Math.min(bytes.length, cap);
          this.u8(bufPtr, n).set(bytes.subarray(0, n));
        }
        return bytes.length;
      },
      rt_create: (w, h) => {
        const cv = document.createElement('canvas');
        cv.width = w; cv.height = h;
        const cc = cv.getContext('2d');
        this.targets.push({ canvas: cv, ctx: cc });
        return this.targets.length - 1;
      },
      rt_image: (rt) => {
        const t = this.targets[rt];
        if (!t) return 0;
        if (t.imageHandle) return t.imageHandle;
        this.images.push({ source: t.canvas, width: t.canvas.width, height: t.canvas.height });
        t.imageHandle = this.images.length - 1;
        return t.imageHandle;
      },

      // ---- audio ----
      snd_from_samples: (ptr, frames, channels, rate) => {
        const ctx = this.ensureAudio();
        if (!ctx || frames <= 0 || channels <= 0) return 0;
        const total = frames * channels;
        const dv = this.dv();
        const buf = ctx.createBuffer(channels, frames, rate);
        for (let ch = 0; ch < channels; ch++) {
          const out = buf.getChannelData(ch);
          for (let f = 0; f < frames; f++) {
            const s = dv.getInt16(ptr + (f * channels + ch) * 2, true);
            out[f] = s < 0 ? s / 32768 : s / 32767;
          }
        }
        this.sounds.push(buf);
        return this.sounds.length - 1;
      },
      snd_by_name: (ptr, len) => {
        const name = this.cstr(ptr, len);
        return this.lookupSound(name);
      },
      // Build an AudioBuffer from raw Float32 PCM samples in wasm memory.
      // Used by bossman-web's SoundManager to play the procedurally-
      // synthesized background loop from bossman-apple. Returns a handle
      // compatible with snd_play.
      snd_create_pcm: (samplesPtr, frameCount, sampleRate) => {
        const ctx = this.ensureAudio();
        if (!ctx || frameCount <= 0) return 0;
        const rate = sampleRate > 0 ? sampleRate : ctx.sampleRate;
        const buf = ctx.createBuffer(1, frameCount, rate);
        const dst = buf.getChannelData(0);
        const src = new Float32Array(this.wasmMemory.buffer, samplesPtr, frameCount);
        dst.set(src);
        this.sounds.push(buf);
        return this.sounds.length - 1;
      },
      snd_play: (buffer, volume, loop) => {
        const ctx = this.ensureAudio();
        const buf = this.sounds[buffer];
        if (!ctx || !buf) return 0;
        const src = ctx.createBufferSource();
        src.buffer = buf;
        src.loop = !!loop;
        const gain = ctx.createGain();
        const base = Math.max(0, Math.min(1, volume / 100));
        gain.gain.value = base * this.duckFactor;
        src.connect(gain).connect(ctx.destination);
        const handle = this.nextVoice++;
        const voice = { source: src, gain, base, state: 1 };
        this.voices.set(handle, voice);
        src.onended = () => {
          voice.state = 0;
          this.voices.delete(handle);
        };
        src.start();
        return handle;
      },
      snd_stop: (voice) => {
        const v = this.voices.get(voice);
        if (!v) return;
        try { v.source.onended = null; v.source.stop(); } catch (_e) {}
        v.state = 0;
        this.voices.delete(voice);
      },
      snd_set_volume: (voice, volume) => {
        const v = this.voices.get(voice);
        if (!v || !this.audioCtx) return;
        v.base = Math.max(0, Math.min(1, volume / 100));
        v.gain.gain.setTargetAtTime(v.base * this.duckFactor, this.audioCtx.currentTime, 0.02);
      },
      snd_status: (voice) => {
        const v = this.voices.get(voice);
        return v ? v.state : 0;
      },
      snd_pause_all: () => {
        if (this.audioCtx && this.audioCtx.state === 'running') this.audioCtx.suspend();
      },
      snd_resume_all: () => {
        // suspended OR Safari 'interrupted'; not 'closed' (would throw).
        if (this.audioCtx && this.audioCtx.state !== 'running' && this.audioCtx.state !== 'closed') {
          this.audioCtx.resume();
        }
      },

      // ---- input ----
      key_pressed: (sfKey) => {
        const code = SF_KEY[sfKey];
        return code && this.pressed.has(code) ? 1 : 0;
      },
      mouse_button: (sfButton) => {
        if (sfButton === 0) return this.mouseDown[0] ? 1 : 0;
        if (sfButton === 1) return this.mouseDown[1] ? 1 : 0;
        return 0;
      },
      mouse_x: () => this.mouseX | 0,
      mouse_y: () => this.mouseY | 0,
      // ---- gamepad / USB arcade joystick (Web Gamepad API) ----
      // pollGamepads() runs once per frame (above the wasm frame call) and
      // refreshes this.gpSnap[pad] = {buttons:[0/1], values:[0..1], axes:[-1..1]}.
      // These imports just read the snapshot, so they're cheap to call repeatedly.
      gp_connected: (pad) => (this.gpSnap && this.gpSnap[pad]) ? 1 : 0,
      gp_button: (pad, btn) => {
        const s = this.gpSnap && this.gpSnap[pad];
        return s && s.buttons[btn] ? 1 : 0;
      },
      gp_button_value: (pad, btn) => {
        const s = this.gpSnap && this.gpSnap[pad];
        return s ? (s.values[btn] || 0) : 0;
      },
      gp_axis: (pad, axis) => {
        const s = this.gpSnap && this.gpSnap[pad];
        return s ? (s.axes[axis] || 0) : 0;
      },
      gp_map_to_keys: (enable) => { this.gpMapToKeys = !!enable; },

      // ---- Text to speech (Web Speech API) ----
      // window.speechSynthesis is the standard surface; available on all major
      // browsers since 2014. AVSpeechSynthesizer.speak() routes here. Rate
      // and pitch are clamped to the Web Speech API's accepted ranges.
      //
      // Voice picking: bossman-apple walks a name-preference list ("rocko",
      // "ralph", "fred", "reed", ...) and prefers premium > enhanced quality.
      // We mirror that here: tts_set_preferred_voices stashes the list, and
      // tts_speak resolves the best match the first time voices populate,
      // then caches it. Robotic / novelty voices (bahh, bells, zarvox, ...)
      // are filtered out so a default of "first English voice" still skips
      // them when no preference matches.
      tts_set_preferred_voices: (utf8Ptr, len) => {
        const csv = this.cstr(utf8Ptr, len).toLowerCase();
        this._ttsPreferred = csv.split(',').map(s => s.trim()).filter(Boolean);
        this._ttsVoice = null;             // force re-pick on next speak
      },
      tts_set_robotic_voices: (utf8Ptr, len) => {
        const csv = this.cstr(utf8Ptr, len).toLowerCase();
        this._ttsRobotic = csv.split(',').map(s => s.trim()).filter(Boolean);
        this._ttsVoice = null;
      },
      tts_set_female_voices: (utf8Ptr, len) => {
        const csv = this.cstr(utf8Ptr, len).toLowerCase();
        this._ttsFemale = csv.split(',').map(s => s.trim()).filter(Boolean);
        this._ttsVoice = null;
      },
      tts_speak: (utf8Ptr, len, rate, pitch, volume) => {
        if (typeof speechSynthesis === 'undefined' || IS_IOS) return 0;
        try { speechSynthesis.resume(); } catch (_e) {}   // Safari can leave the queue paused
        const text = this.cstr(utf8Ptr, len);
        const u = new SpeechSynthesisUtterance(text);
        u.rate   = Math.max(0.1, Math.min(rate   || 1.0, 10));
        u.pitch  = Math.max(0,   Math.min(pitch  || 1.0, 2));
        u.volume = Math.max(0,   Math.min(volume || 1.0, 1));
        u.onstart = () => this._setDuck(0.25);   // duck music/SFX while speaking
        u.onend   = () => this._setDuck(1);
        u.onerror = () => this._setDuck(1);
        const v = this._pickTTSVoice();
        if (v) {
          u.voice = v;
          try { speechSynthesis.speak(u); return 1; } catch (_e) { return 0; }
        }
        // Voices aren't loaded yet — speaking now would fall through to
        // the browser default (often Samantha / female), which is why
        // bossman-web's first "Welcome back" line came out wrong.
        // Queue the utterance and drain when onvoiceschanged fires.
        this._ttsPending.push(u);
        return 1;
      },
      tts_cancel: () => { if (typeof speechSynthesis !== 'undefined') speechSynthesis.cancel(); this._setDuck(1); },

      // ============================================================
      // WebGL2 shader pipeline (SKShader, SKLightNode, SKWarpGeometry,
      // SK3DNode). Programs cached; uniform locations memoized.
      // ============================================================
      gfx_shader_compile: (ptr, len) => {
        const gl = this.ensureGL(); if (!gl) return 0;
        const src = this.cstr(ptr, len);
        const program = this.linkShaderProgram(gl, this.buildShaderFrag(src));
        if (!program) return 0;
        const id = this.shaders.length;
        this.shaders.push({ program, uniformLocs: new Map(), srcText: src });
        return id;
      },
      gfx_shader_release: (sh) => {
        if (sh <= 0 || sh >= this.shaders.length) return;
        const rec = this.shaders[sh]; if (!rec) return;
        if (this.gl && rec.program) this.gl.deleteProgram(rec.program);
        this.shaders[sh] = null;
      },
      gfx_shader_set_uniform_f: (sh, nPtr, nLen, v) => {
        if (!this.gl) return;
        const rec = this.shaders[sh]; if (!rec) return;
        this.gl.useProgram(rec.program);
        const loc = this.uniLoc(sh, this.cstr(nPtr, nLen));
        if (loc) this.gl.uniform1f(loc, v);
      },
      gfx_shader_set_uniform_v2: (sh, nPtr, nLen, x, y) => {
        if (!this.gl) return;
        const rec = this.shaders[sh]; if (!rec) return;
        this.gl.useProgram(rec.program);
        const loc = this.uniLoc(sh, this.cstr(nPtr, nLen));
        if (loc) this.gl.uniform2f(loc, x, y);
      },
      gfx_shader_set_uniform_v3: (sh, nPtr, nLen, x, y, z) => {
        if (!this.gl) return;
        const rec = this.shaders[sh]; if (!rec) return;
        this.gl.useProgram(rec.program);
        const loc = this.uniLoc(sh, this.cstr(nPtr, nLen));
        if (loc) this.gl.uniform3f(loc, x, y, z);
      },
      gfx_shader_set_uniform_v4: (sh, nPtr, nLen, x, y, z, w) => {
        if (!this.gl) return;
        const rec = this.shaders[sh]; if (!rec) return;
        this.gl.useProgram(rec.program);
        const loc = this.uniLoc(sh, this.cstr(nPtr, nLen));
        if (loc) this.gl.uniform4f(loc, x, y, z, w);
      },
      gfx_shader_set_uniform_t: (sh, nPtr, nLen, imgId) => {
        if (!this.gl) return;
        const rec = this.shaders[sh]; if (!rec) return;
        const tex = this.glTextureFor(imgId); if (!tex) return;
        this.gl.useProgram(rec.program);
        // Reserve texture unit 2+ for user textures (0 = u_texture, 1 = u_normal).
        rec.userTexUnits = rec.userTexUnits || new Map();
        let unit = rec.userTexUnits.get(nPtr);     // keyed by name pointer is fine; same call site reuses unit
        if (unit === undefined) { unit = 2 + rec.userTexUnits.size; rec.userTexUnits.set(nPtr, unit); }
        this.gl.activeTexture(this.gl.TEXTURE0 + unit);
        this.gl.bindTexture(this.gl.TEXTURE_2D, tex);
        const loc = this.uniLoc(sh, this.cstr(nPtr, nLen));
        if (loc) this.gl.uniform1i(loc, unit);
      },
      gfx_shader_draw: (sh, srcImg, dx, dy, dw, dh, time, color) => {
        if (sh <= 0 || sh >= this.shaders.length || !this.shaders[sh]) {
          // Shader unavailable — fall back to plain image draw so the sprite
          // still appears (un-shaded) instead of vanishing.
          const rec = this.images[srcImg];
          if (rec && rec.source) this.ctx2d().drawImage(rec.source, dx, dy, dw, dh);
          return;
        }
        this.glRunPassToCanvas(sh, srcImg, 0, dx, dy, dw, dh, time, color, null);
      },

      // SKLightNode lighting pass. `lights` is a pointer to a tightly-packed
      // float buffer: 8 floats per light = posX, posY, intensity, _pad,
      // colorR, colorG, colorB, falloff. Up to 8 lights consumed.
      gfx_lighting_draw: (srcImg, normalImg, lightsPtr, lightCount,
                          dx, dy, dw, dh, color) => {
        const shaderId = this.ensureLightingShader(); if (!shaderId) return;
        const dv = this.dv();
        const n = Math.max(0, Math.min(8, lightCount));
        const posIntensity = new Float32Array(8 * 4);
        const colorFalloff = new Float32Array(8 * 4);
        for (let i = 0; i < n; i++) {
          const base = lightsPtr + i * 32;
          posIntensity[i*4+0] = dv.getFloat32(base + 0,  true); // x
          posIntensity[i*4+1] = dv.getFloat32(base + 4,  true); // y
          posIntensity[i*4+2] = 0;                              // z (kept 0 in 2D)
          posIntensity[i*4+3] = dv.getFloat32(base + 8,  true); // intensity (in w slot)
          colorFalloff[i*4+0] = dv.getFloat32(base + 16, true); // r
          colorFalloff[i*4+1] = dv.getFloat32(base + 20, true); // g
          colorFalloff[i*4+2] = dv.getFloat32(base + 24, true); // b
          colorFalloff[i*4+3] = dv.getFloat32(base + 28, true); // falloff
        }
        this.glRunPassToCanvas(shaderId, srcImg, normalImg, dx, dy, dw, dh, 0, color,
          (gl, self) => {
            const uPos = self.uniLoc(shaderId, 'u_lightPositions');
            const uCol = self.uniLoc(shaderId, 'u_lightColors');
            const uCnt = self.uniLoc(shaderId, 'u_lightCount');
            const uAmb = self.uniLoc(shaderId, 'u_ambient');
            if (uPos) gl.uniform4fv(uPos, posIntensity);
            if (uCol) gl.uniform4fv(uCol, colorFalloff);
            if (uCnt) gl.uniform1i(uCnt, n);
            if (uAmb) gl.uniform4f(uAmb, 0.2, 0.2, 0.2, 1.0);
          });
      },

      // SKWarpGeometryGrid mesh warp. Renders a (cols x rows) cell grid of
      // textured triangles. srcUV is (cols+1)*(rows+1)*2 floats in 0..1.
      // dstXY is the same count, in normalized 0..1 dest coordinates.
      gfx_warp_draw: (srcImg, cols, rows, srcUVPtr, dstXYPtr,
                      dx, dy, dw, dh, color) => {
        const gl = this.ensureGL(); if (!gl) return;
        const srcTex = this.glTextureFor(srcImg); if (!srcTex) return;
        // Build vertex arrays from wasm memory.
        const verts = (cols + 1) * (rows + 1);
        const dv = this.dv();
        const xy = new Float32Array(verts * 2);
        const uv = new Float32Array(verts * 2);
        for (let i = 0; i < verts; i++) {
          // dest in 0..1 → NDC -1..1 (y flipped so 0 is top)
          xy[i*2+0] = dv.getFloat32(dstXYPtr + i*8 + 0, true) * 2 - 1;
          xy[i*2+1] = 1 - dv.getFloat32(dstXYPtr + i*8 + 4, true) * 2;
          uv[i*2+0] = dv.getFloat32(srcUVPtr + i*8 + 0, true);
          uv[i*2+1] = dv.getFloat32(srcUVPtr + i*8 + 4, true);
        }
        // Build index buffer (2 tris per cell).
        const idx = new Uint16Array(cols * rows * 6);
        let k = 0;
        for (let r = 0; r < rows; r++) {
          for (let c = 0; c < cols; c++) {
            const i00 = r * (cols + 1) + c;
            const i10 = i00 + 1;
            const i01 = i00 + (cols + 1);
            const i11 = i01 + 1;
            idx[k++] = i00; idx[k++] = i10; idx[k++] = i11;
            idx[k++] = i00; idx[k++] = i11; idx[k++] = i01;
          }
        }
        // Ensure a passthrough program exists.
        if (this.warpShader == null) {
          const src = `void main(){ gl_FragColor = SKDefaultShading(); }`;
          this.warpShader = this.linkShaderProgram(gl, this.buildShaderFrag(src));
        }
        if (!this.warpShader) return;
        this.glResize(dw, dh);
        gl.useProgram(this.warpShader);
        // Interleaved VBO.
        const buf = new Float32Array(verts * 4);
        for (let i = 0; i < verts; i++) {
          buf[i*4+0] = xy[i*2+0]; buf[i*4+1] = xy[i*2+1];
          buf[i*4+2] = uv[i*2+0]; buf[i*4+3] = uv[i*2+1];
        }
        const vbo = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.bufferData(gl.ARRAY_BUFFER, buf, gl.STREAM_DRAW);
        gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 16, 0);
        gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 16, 8);
        const ibo = gl.createBuffer();
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STREAM_DRAW);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, srcTex);
        const r = ((color >>> 24) & 0xFF) / 255;
        const g = ((color >>> 16) & 0xFF) / 255;
        const b = ((color >>>  8) & 0xFF) / 255;
        const a = ( color         & 0xFF) / 255;
        const program = this.warpShader;
        const uTex = gl.getUniformLocation(program, 'u_texture'); if (uTex) gl.uniform1i(uTex, 0);
        const uCol = gl.getUniformLocation(program, 'u_color_mix'); if (uCol) gl.uniform4f(uCol, r, g, b, a);
        gl.drawElements(gl.TRIANGLES, idx.length, gl.UNSIGNED_SHORT, 0);
        gl.deleteBuffer(vbo); gl.deleteBuffer(ibo);
        this.ctx2d().drawImage(this.glCanvas, 0, 0, this.glCanvas.width, this.glCanvas.height, dx, dy, dw, dh);
      },

      // SK3DNode minimal billboard render. Sets up a perspective view +
      // textured quad at the origin. Future: OBJ + scene graph.
      gfx_3d_draw_billboard: (srcImg, camX, camY, camZ,
                              dx, dy, dw, dh, color) => {
        // Simple compose: pass the texture through unchanged, scaled by view
        // distance so the quad gets smaller as the camera pulls back. Enough
        // to show "something" for games that only use SK3DNode for splash
        // billboards; a full SceneKit shim is its own project.
        const rec = this.images[srcImg];
        if (rec && rec.source) {
          const ctx = this.ctx2d();
          const fov = 60 * Math.PI / 180;
          const dist = Math.max(0.001, Math.sqrt(camX*camX + camY*camY + Math.max(camZ, 0.001) * Math.max(camZ, 0.001)));
          const scale = 1 / (1 + dist * Math.tan(fov / 2) * 0.01);
          const w2 = dw * scale, h2 = dh * scale;
          ctx.drawImage(rec.source, dx + (dw - w2) / 2, dy + (dh - h2) / 2, w2, h2);
        }
      },

      // SKMutableTexture push: replace an image asset's backing canvas with
      // the raw RGBA8 pixels at `ptr`. Resizes the canvas to (w, h).
      // ============================================================
      // AVAudioEngine — real Web Audio graph.
      // Each engine node maps to a Web Audio node (AudioBufferSourceNode for
      // players, GainNode for mixers). Players hold a queue of scheduled
      // buffers; play() triggers the next one. dst = -1 connects directly to
      // audioCtx.destination so a one-line player → output chain works.
      // ============================================================
      eng_player_create: () => {
        this.ensureAudio();
        const id = this.engineNodes.length;
        const gain = this.audioCtx.createGain();
        this.engineNodes.push({ kind: 'player', source: null, gain, queue: [], loops: 0 });
        return id;
      },
      eng_player_release: (id) => {
        const n = this.engineNodes[id]; if (!n) return;
        try { if (n.source) n.source.stop(); } catch (_e) {}
        try { n.gain.disconnect(); } catch (_e) {}
        this.engineNodes[id] = null;
      },
      eng_mixer_create: () => {
        this.ensureAudio();
        const id = this.engineNodes.length;
        const gain = this.audioCtx.createGain();
        this.engineNodes.push({ kind: 'mixer', gain });
        return id;
      },
      eng_node_set_volume: (id, v) => {
        const n = this.engineNodes[id]; if (!n) return;
        n.gain.gain.value = v;
      },
      eng_node_set_pan: (id, p) => {
        const n = this.engineNodes[id]; if (!n) return;
        if (!n.panner && this.audioCtx.createStereoPanner) {
          n.panner = this.audioCtx.createStereoPanner();
          try { n.gain.disconnect(); n.gain.connect(n.panner); } catch (_e) {}
          if (n.pannerDownstream) n.panner.connect(n.pannerDownstream);
        }
        if (n.panner) n.panner.pan.value = p;
      },
      eng_connect: (srcId, dstId) => {
        const s = this.engineNodes[srcId]; if (!s) return;
        const dst = dstId < 0 ? this.audioCtx.destination : (this.engineNodes[dstId] ? this.engineNodes[dstId].gain : null);
        if (!dst) return;
        try {
          (s.panner || s.gain).connect(dst);
          if (s.panner) s.pannerDownstream = dst;
        } catch (_e) {}
      },
      eng_player_schedule_buffer: (playerId, sndId, loops) => {
        const p = this.engineNodes[playerId]; if (!p || p.kind !== 'player') return 0;
        const buf = this.sounds[sndId]; if (!buf) return 0;
        p.queue.push({ buffer: buf, loops });
        return 1;
      },
      eng_player_play: (id) => {
        const p = this.engineNodes[id]; if (!p || p.kind !== 'player') return;
        if (p.queue.length === 0) return;
        const job = p.queue.shift();
        const src = this.audioCtx.createBufferSource();
        src.buffer = job.buffer;
        src.loop = job.loops < 0;
        src.connect(p.gain);
        try { src.start(); } catch (_e) {}
        p.source = src;
      },
      eng_player_stop: (id) => {
        const p = this.engineNodes[id]; if (!p || p.kind !== 'player') return;
        try { if (p.source) p.source.stop(); } catch (_e) {}
        p.source = null; p.queue = [];
      },
      eng_start: () => { this.ensureAudio(); if (this.audioCtx.state === 'suspended') this.audioCtx.resume(); },
      eng_stop:  () => { if (this.audioCtx && this.audioCtx.state === 'running') this.audioCtx.suspend(); },

      gfx_upload_pixels: (imgId, w, h, ptr, len) => {
        let rec, finalId = imgId;
        if (imgId <= 0) {
          // Allocate a new image slot.
          const cv = document.createElement('canvas');
          cv.width = w; cv.height = h;
          rec = { source: cv, width: w, height: h };
          finalId = this.images.length;
          this.images.push(rec);
        } else {
          rec = this.images[imgId];
          if (!rec) return 0;
        }
        let cv = rec.source;
        if (!(cv instanceof HTMLCanvasElement)) {
          cv = document.createElement('canvas');
          rec.source = cv;
        }
        if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; }
        const ctx = cv.getContext('2d');
        const data = ctx.createImageData(w, h);
        const u8 = new Uint8Array(this.wasmMemory.buffer, ptr, Math.min(len, w * h * 4));
        data.data.set(u8);
        ctx.putImageData(data, 0, 0);
        rec.width = w; rec.height = h;
        this.glTexFromImage.delete(finalId);   // invalidate GL cache so next pass re-uploads
        return finalId;
      },

      // ============================================================
      // Offscreen canvas pipeline (SKView.texture(from:), SKCropNode,
      // SKEffectNode). gfx_offscreen_begin pushes a new HTMLCanvasElement
      // onto this.targets, switches gfx output to it, and returns a handle.
      // _end_to_image commits the canvas as an image asset (img handle)
      // that subsequent gfx_draw_image calls can render. _end_discard
      // just pops the stack.
      // ============================================================
      gfx_offscreen_begin: (w, h) => {
        const dpr = window.devicePixelRatio || 1;
        const off = document.createElement('canvas');
        off.width  = Math.max(1, Math.round(w * dpr));
        off.height = Math.max(1, Math.round(h * dpr));
        const oc = off.getContext('2d', { alpha: true });
        oc.scale(dpr, dpr);    // logical pixel space matches main canvas
        const handle = this.targets.length;
        this.targets.push({ canvas: off, ctx: oc, logical: { w, h }, savedTarget: this.curTarget });
        this.curTarget = handle;
        return handle;
      },
      gfx_offscreen_end_to_image: (handle) => {
        if (handle <= 0 || handle >= this.targets.length) return 0;
        const t = this.targets[handle];
        this.curTarget = t.savedTarget != null ? t.savedTarget : 0;
        // Register the offscreen as a synthetic image asset so gfx_draw_image
        // can route to it. Match the {source, width, height} shape the rest
        // of the runtime expects from this.images.
        const rec = { source: t.canvas, width: t.canvas.width, height: t.canvas.height };
        // Reuse a slot freed by gfx_free_image so per-frame bakes (SKEffectNode
        // blur, SKCropNode) don't grow this.images without bound.
        let imgId;
        if (this.freeImageSlots && this.freeImageSlots.length) {
          imgId = this.freeImageSlots.pop();
          this.images[imgId] = rec;
        } else {
          imgId = this.images.length;
          this.images.push(rec);
        }
        if (handle === this.targets.length - 1) this.targets.pop();
        else this.targets[handle] = null;
        return imgId;
      },
      gfx_offscreen_end_discard: (handle) => {
        if (handle <= 0 || handle >= this.targets.length) return;
        const t = this.targets[handle];
        this.curTarget = t.savedTarget != null ? t.savedTarget : 0;
        if (handle === this.targets.length - 1) this.targets.pop();
        else this.targets[handle] = null;
      },
      // Release a baked image (from gfx_offscreen_end_to_image): drop its
      // canvas so the browser can reclaim it. Without this, a game that
      // re-bakes a texture per level (e.g. the maze sheet) leaks one full-size
      // canvas every level until the tab is killed for memory. Never call this
      // on a preloaded/atlas image that other textures still share.
      gfx_free_image: (img) => {
        if (img > 0 && this.images && this.images[img]) {
          this.images[img] = null;
          (this.freeImageSlots || (this.freeImageSlots = [])).push(img);
        }
      },
      // Blit an offscreen image as a SOFT drop shadow only: draw it far off
      // canvas with a compensating shadowOffset so just its ctx.shadowBlur
      // halo lands at (x,y,w,h). Done in device space (identity transform) so
      // shadowOffset — which Canvas2D does NOT transform — cancels exactly at
      // any devicePixelRatio. blur is logical px, scaled to device here.
      gfx_draw_shadow_image: (h, x, y, w, hh, blur, rgba) => {
        const img = this.images[h];
        if (!img || !img.source) return;
        const ctx = this.ctx2d();
        const m = ctx.getTransform();
        const dpr = window.devicePixelRatio || 1;
        const big = 100000;
        const devX = m.a * x + m.c * y + m.e;
        const devY = m.b * x + m.d * y + m.f;
        const devW = w * m.a, devH = hh * m.d;
        ctx.save();
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.shadowColor   = this.css(rgba);
        // +25px framework softening so CIGaussianBlur(radius) reads as soft on
        // Canvas2D as it does from Core Image on Apple.
        ctx.shadowBlur    = blur * dpr + 25;
        ctx.shadowOffsetX = devX + big;
        ctx.shadowOffsetY = devY;
        ctx.drawImage(img.source, -big, 0, devW, devH);
        ctx.restore();
      },

      // ============================================================
      // Canvas2D filter + composite ops (SKEffectNode + SKCropNode).
      // ============================================================
      gfx_set_filter: (ptr, len) => { this.ctx2d().filter = this.cstr(ptr, len); },
      gfx_clear_filter: ()       => { this.ctx2d().filter = 'none'; },

      // Canvas2D shadowBlur is the proper drop-shadow primitive and works
      // uniformly across browsers. ctx.filter blur applied to fillRect is
      // unreliable; shadow* properties are guaranteed to render a Gaussian
      // halo behind any subsequent fillRect / drawImage / fillText.
      gfx_set_shadow: (blur, dx, dy, rgba) => {
        const c = this.ctx2d();
        c.shadowBlur    = blur;
        c.shadowOffsetX = dx;
        c.shadowOffsetY = dy;
        c.shadowColor   = this.css(rgba);
      },
      gfx_clear_shadow: () => {
        const c = this.ctx2d();
        c.shadowBlur    = 0;
        c.shadowOffsetX = 0;
        c.shadowOffsetY = 0;
        c.shadowColor   = 'transparent';
      },
      gfx_set_composite: (mode)  => {
        const modes = ['source-over','destination-in','destination-out',
                       'lighter','multiply','screen','overlay'];
        this.ctx2d().globalCompositeOperation = modes[mode] || 'source-over';
      },

      // ============================================================
      // SKVideoNode: a DOM <video> element overlaid on the canvas.
      // The element is absolutely positioned in the canvas's bounding box
      // so it lines up with whatever logical-rect the game passed.
      // ============================================================
      vid_load: (ptr, len) => {
        const name = this.cstr(ptr, len);
        const v = document.createElement('video');
        v.src = (this.assetRoot || '') + '/videos/' + name;
        v.preload = 'auto'; v.playsInline = true; v.muted = false;
        v.style.position = 'absolute'; v.style.pointerEvents = 'none';
        v.style.display = 'none';
        document.body.appendChild(v);
        if (!this.videos) this.videos = [];
        const id = this.videos.length; this.videos.push(v); return id;
      },
      vid_play:  (id) => { if (this.videos && this.videos[id]) this.videos[id].play().catch(() => {}); },
      vid_pause: (id) => { if (this.videos && this.videos[id]) this.videos[id].pause(); },
      vid_stop:  (id) => {
        const v = this.videos && this.videos[id]; if (!v) return;
        v.pause(); v.currentTime = 0;
      },
      vid_set_rect: (id, x, y, w, h) => {
        const v = this.videos && this.videos[id]; if (!v) return;
        const rect = this.canvas.getBoundingClientRect();
        const scale = Math.min(rect.width / LOGICAL_W, rect.height / LOGICAL_H);
        v.style.left   = (rect.left + x * scale) + 'px';
        v.style.top    = (rect.top  + y * scale) + 'px';
        v.style.width  = (w * scale) + 'px';
        v.style.height = (h * scale) + 'px';
        v.style.display = '';
      },
      vid_set_visible: (id, visible) => {
        const v = this.videos && this.videos[id]; if (!v) return;
        v.style.display = visible ? '' : 'none';
      },

      // ============================================================
      // Web Audio per-voice stereo pan + playback rate.
      // Each voice from snd_play holds {source, gain, pannerNode}; the
      // panner is created on first snd_set_pan call so we don't allocate
      // one per voice when no game uses it.
      // ============================================================
      snd_set_pan: (voice, pan) => {
        const v = this.voices.get(voice); if (!v) return;
        if (!v.panner && this.audioCtx && this.audioCtx.createStereoPanner) {
          v.panner = this.audioCtx.createStereoPanner();
          try { v.gain.disconnect(); v.gain.connect(v.panner); v.panner.connect(this.audioCtx.destination); }
          catch (_e) {}
        }
        if (v.panner) v.panner.pan.value = Math.max(-1, Math.min(1, pan));
      },
      snd_set_rate: (voice, rate) => {
        const v = this.voices.get(voice); if (!v) return;
        if (v.source) try { v.source.playbackRate.value = Math.max(0.0625, Math.min(rate, 16)); } catch (_e) {}
      },

      // ============================================================
      // Pixel-perfect physics polygon: read canvas getImageData of the
      // image, trace its alpha boundary with marching squares, simplify
      // with Ramer-Douglas-Peucker, write up to `cap` xy pairs into
      // out_xy. Returns the actual point count written (clamped to cap).
      // ============================================================
      img_polygon_from_alpha: (imgId, threshold, outPtr, cap) => {
        const rec = this.images && this.images[imgId]; if (!rec || !rec.source) return 0;
        // Build a sampler canvas so we can call getImageData.
        const w = rec.width  || rec.source.naturalWidth  || rec.source.width;
        const h = rec.height || rec.source.naturalHeight || rec.source.height;
        if (!w || !h) return 0;
        const cv = document.createElement('canvas');
        cv.width = w; cv.height = h;
        const cx = cv.getContext('2d', { willReadFrequently: true });
        cx.drawImage(rec.source, 0, 0);
        let data;
        try { data = cx.getImageData(0, 0, w, h).data; } catch (_e) { return 0; }
        const a = Math.max(0, Math.min(threshold, 1)) * 255;
        // Marching-squares boundary trace from the first opaque pixel found.
        const inside = (x, y) => x >= 0 && y >= 0 && x < w && y < h && data[(y*w + x) * 4 + 3] >= a;
        // Find a seed on the boundary.
        let sx = -1, sy = -1;
        outer: for (let y = 0; y < h; y++) {
          for (let x = 0; x < w; x++) {
            if (inside(x, y)) { sx = x; sy = y; break outer; }
          }
        }
        if (sx < 0) return 0;
        // Walk the boundary clockwise using the standard Moore-neighbourhood
        // contour tracing algorithm.
        const dirs = [[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]];
        let cx0 = sx, cy0 = sy, dir = 0;
        const pts = [[cx0, cy0]];
        const MAX_STEPS = 4 * (w + h);
        for (let step = 0; step < MAX_STEPS; step++) {
          let found = false;
          for (let i = 0; i < 8; i++) {
            const d = (dir + 6 + i) & 7;     // start one step back from previous heading
            const nx = cx0 + dirs[d][0], ny = cy0 + dirs[d][1];
            if (inside(nx, ny)) {
              cx0 = nx; cy0 = ny; dir = d;
              pts.push([cx0, cy0]);
              found = true; break;
            }
          }
          if (!found) break;
          if (cx0 === sx && cy0 === sy && pts.length > 2) break;
        }
        // Ramer-Douglas-Peucker simplification to fit in `cap` points.
        const simplified = rdpSimplify(pts, Math.max(0.5, Math.min(w, h) / 64));
        const truncated = simplified.length > cap ? simplified.slice(0, cap) : simplified;
        // Convert pixel coords to centered, y-up (SpriteKit) coordinates.
        const dv = this.dv();
        for (let i = 0; i < truncated.length; i++) {
          const px = truncated[i][0] - w / 2;
          const py = h / 2 - truncated[i][1];
          dv.setFloat32(outPtr + i * 8,     px, true);
          dv.setFloat32(outPtr + i * 8 + 4, py, true);
        }
        return truncated.length;
      },

      evt_poll: (typePtr, aPtr, bPtr, cPtr, dPtr) => {
        const e = this.events.shift();
        if (!e) return 0;
        const dv = this.dv();
        dv.setInt32(typePtr, e.type | 0, true);
        dv.setInt32(aPtr, e.a | 0, true);
        dv.setInt32(bPtr, e.b | 0, true);
        dv.setInt32(cPtr, e.c | 0, true);
        dv.setInt32(dPtr, e.d | 0, true);
        return 1;
      },

      // ---- window ----
      win_set_title: (ptr, len) => { document.title = this.cstr(ptr, len); },
      win_width: () => LOGICAL_W,
      win_height: () => LOGICAL_H,
      win_request_fullscreen: () => {
        // Android + iPad + desktop use the real Fullscreen API. iPhone Safari has
        // none (video only), so fall back to a CSS pseudo-fullscreen that covers
        // the viewport (and asks an embedding page to expand its iframe).
        const el = this.canvas;
        if (el.requestFullscreen) el.requestFullscreen().catch(() => this._pseudoFullscreen(true));
        else if (el.webkitRequestFullscreen) el.webkitRequestFullscreen();
        else this._pseudoFullscreen(true);
      },
      win_exit_fullscreen: () => {
        if (document.exitFullscreen) document.exitFullscreen().catch(() => {});
        else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
        this._pseudoFullscreen(false);
      },

      // ---- persistence (localStorage) ----
      store_get: (keyPtr, klen, bufPtr, cap) => {
        const key = this.cstr(keyPtr, klen);
        const val = localStorage.getItem(key);
        if (val === null) return -1;
        const bytes = this.textEncoder.encode(val);
        const n = Math.min(bytes.length, cap);
        this.u8(bufPtr, n).set(bytes.subarray(0, n));
        return bytes.length;
      },
      store_set: (keyPtr, klen, valPtr, vlen) => {
        const key = this.cstr(keyPtr, klen);
        const val = this.cstr(valPtr, vlen);
        try { localStorage.setItem(key, val); } catch (_e) {}
      },
    };
  }

  // --------------------------------------------------------------------------
  // helpers
  // --------------------------------------------------------------------------
  ctx2d() { return this.targets[this.curTarget].ctx; }

  // ----------------------------------------------------------------------------
  // WebGL2 shader pipeline. The kit runs Canvas2D for most drawing; SKShader
  // and SKLightNode need a real GPU pipeline, so we host a hidden WebGL2 canvas
  // (created on first use), compile programs against it, render the shaded
  // result there, then drawImage it back onto the active Canvas2D target.
  // ----------------------------------------------------------------------------
  ensureGL() {
    if (this.gl) return this.gl;
    const c = document.createElement('canvas');
    c.width = 1024; c.height = 1024;
    const gl = c.getContext('webgl2', { premultipliedAlpha: false, alpha: true });
    if (!gl) { console.warn('[boss] WebGL2 unavailable; shaders will no-op'); return null; }
    this.glCanvas = c;
    this.gl = gl;
    // Shared full-quad VAO. Triangle strip covers [-1..1] in NDC; UVs cover [0..1].
    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    const vbo = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    // x, y, u, v
    const verts = new Float32Array([
      -1, -1, 0, 1,
       1, -1, 1, 1,
      -1,  1, 0, 0,
       1,  1, 1, 0,
    ]);
    gl.bufferData(gl.ARRAY_BUFFER, verts, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 16, 0);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 16, 8);
    gl.bindVertexArray(null);
    this.glQuadVAO = vao;
    return gl;
  }

  // Build the WebGL2 preamble that lets SpriteKit-style fragment source ("void
  // main() { ... gl_FragColor = ... }") compile against GLSL ES 3.00. We map
  // legacy names (texture2D, gl_FragColor) and inject SKDefaultShading plus
  // the standard SpriteKit varyings + uniforms.
  buildShaderFrag(userSrc) {
    return `#version 300 es
precision highp float;
in vec2 v_tex_coord;
in vec4 v_color_mix;
uniform sampler2D u_texture;
uniform float u_time;
out vec4 _outColor;
#define gl_FragColor _outColor
#define texture2D texture
vec4 SKDefaultShading() {
  return texture(u_texture, v_tex_coord) * v_color_mix;
}
${userSrc}
`;
  }

  buildShaderVert() {
    return `#version 300 es
in vec2 a_position;
in vec2 a_uv;
out vec2 v_tex_coord;
out vec4 v_color_mix;
uniform vec4 u_color_mix;
void main() {
  v_tex_coord = a_uv;
  v_color_mix = u_color_mix;
  gl_Position = vec4(a_position, 0.0, 1.0);
}`;
  }

  compileShaderObj(gl, type, src) {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      const log = gl.getShaderInfoLog(sh);
      console.warn('[boss] shader compile failed:', log, '\n\nSource:\n', src);
      gl.deleteShader(sh);
      return null;
    }
    return sh;
  }
  linkShaderProgram(gl, fragSrc) {
    const vs = this.compileShaderObj(gl, gl.VERTEX_SHADER, this.buildShaderVert());
    const fs = this.compileShaderObj(gl, gl.FRAGMENT_SHADER, fragSrc);
    if (!vs || !fs) return null;
    const p = gl.createProgram();
    gl.attachShader(p, vs);
    gl.attachShader(p, fs);
    gl.bindAttribLocation(p, 0, 'a_position');
    gl.bindAttribLocation(p, 1, 'a_uv');
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
      console.warn('[boss] program link failed:', gl.getProgramInfoLog(p));
      return null;
    }
    return p;
  }

  // Find/create a WebGLTexture for an image asset id. Cached so repeat draws
  // don't re-upload. SKMutableTexture invalidates by deleting the cache entry
  // on each gfx_upload_pixels.
  glTextureFor(imgId) {
    const gl = this.gl;
    let tex = this.glTexFromImage.get(imgId);
    if (tex) return tex;
    const rec = this.images[imgId]; if (!rec || !rec.source) return null;
    tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, rec.source);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    this.glTexFromImage.set(imgId, tex);
    return tex;
  }

  // Resize the WebGL canvas to (w, h) and reset the viewport. Used before
  // each shader/lighting/warp draw so the framebuffer matches the dest rect.
  glResize(w, h) {
    const gl = this.gl;
    const iw = Math.max(1, Math.round(w));
    const ih = Math.max(1, Math.round(h));
    if (this.glCanvas.width !== iw || this.glCanvas.height !== ih) {
      this.glCanvas.width = iw; this.glCanvas.height = ih;
    }
    gl.viewport(0, 0, iw, ih);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
  }

  // Look up (and cache) a uniform location on a program.
  uniLoc(shader, name) {
    const rec = this.shaders[shader]; if (!rec) return null;
    let loc = rec.uniformLocs.get(name);
    if (loc !== undefined) return loc;
    loc = this.gl.getUniformLocation(rec.program, name);
    rec.uniformLocs.set(name, loc);
    return loc;
  }

  // Cached default lighting program (compiled the first time SKLightNode renders).
  ensureLightingShader() {
    if (this.lightingShader != null) return this.lightingShader;
    const gl = this.ensureGL(); if (!gl) return null;
    // Up to 8 lights. Each light is vec4 posIntensity + vec4 colorFalloff.
    const userSrc = `
uniform sampler2D u_normal;
uniform vec4 u_ambient;
uniform vec4 u_lightPositions[8];
uniform vec4 u_lightColors[8];
uniform int  u_lightCount;
void main() {
  vec4 base = SKDefaultShading();
  vec3 normal = vec3(0.0, 0.0, 1.0);
  vec4 nm = texture(u_normal, v_tex_coord);
  // If a real normal map texture is bound (alpha != 0 placeholder), use it.
  if (nm.a > 0.001) { normal = normalize(nm.xyz * 2.0 - 1.0); }
  vec3 accum = u_ambient.rgb * base.rgb;
  for (int i = 0; i < 8; i++) {
    if (i >= u_lightCount) break;
    vec3 toLight = vec3(u_lightPositions[i].xy - gl_FragCoord.xy, u_lightPositions[i].z);
    float dist = length(toLight);
    vec3 dir = normalize(toLight);
    float diff = max(dot(normal, dir), 0.0);
    float fall = 1.0 / (1.0 + u_lightColors[i].a * dist);
    accum += base.rgb * u_lightColors[i].rgb * diff * fall * u_lightPositions[i].w;
  }
  gl_FragColor = vec4(accum, base.a);
}`;
    const program = this.linkShaderProgram(gl, this.buildShaderFrag(userSrc));
    if (!program) { this.lightingShader = -1; return null; }
    const id = this.shaders.length;
    this.shaders.push({ program, uniformLocs: new Map(), srcText: '<built-in lighting>' });
    this.lightingShader = id;
    return id;
  }

  // Apply a compiled program to (srcImg, dstW, dstH) into the WebGL canvas,
  // then drawImage the result onto the current 2D target at (dstX,dstY,dstW,dstH).
  glRunPassToCanvas(shaderId, srcImg, normalImg, dstX, dstY, dstW, dstH, time, colorRgba, extraUniforms) {
    const gl = this.ensureGL(); if (!gl) return;
    const rec = this.shaders[shaderId]; if (!rec) return;
    const srcTex = this.glTextureFor(srcImg); if (!srcTex) return;
    const normalTex = normalImg > 0 ? this.glTextureFor(normalImg) : null;
    this.glResize(dstW, dstH);
    gl.useProgram(rec.program);
    gl.bindVertexArray(this.glQuadVAO);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, srcTex);
    const uTex = this.uniLoc(shaderId, 'u_texture'); if (uTex) gl.uniform1i(uTex, 0);
    const uTime = this.uniLoc(shaderId, 'u_time'); if (uTime) gl.uniform1f(uTime, time);
    const uColor = this.uniLoc(shaderId, 'u_color_mix');
    if (uColor) {
      const r = ((colorRgba >>> 24) & 0xFF) / 255;
      const g = ((colorRgba >>> 16) & 0xFF) / 255;
      const b = ((colorRgba >>>  8) & 0xFF) / 255;
      const a = ( colorRgba         & 0xFF) / 255;
      gl.uniform4f(uColor, r, g, b, a);
    }
    if (normalTex) {
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, normalTex);
      const uN = this.uniLoc(shaderId, 'u_normal');
      if (uN) gl.uniform1i(uN, 1);
    }
    if (extraUniforms) extraUniforms(gl, this);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    // Blit WebGL result onto the current Canvas2D target.
    const dstCtx = this.ctx2d();
    dstCtx.drawImage(this.glCanvas, 0, 0, this.glCanvas.width, this.glCanvas.height,
                     dstX, dstY, dstW, dstH);
  }


  css(rgba) {
    const r = (rgba >>> 24) & 0xFF;
    const g = (rgba >>> 16) & 0xFF;
    const b = (rgba >>> 8) & 0xFF;
    const a = (rgba & 0xFF) / 255;
    return `rgba(${r},${g},${b},${a})`;
  }

  applyFont(c, font, sizePx, letterSpacing) {
    const family = (font > 0 && this.fonts[font]) ? this.fonts[font] : this.defaultFontFamily;
    c.font = `${sizePx}px ${family}`;
    if (this.hasLetterSpacing === undefined) this.hasLetterSpacing = 'letterSpacing' in c;
    if (this.hasLetterSpacing) c.letterSpacing = `${letterSpacing || 0}px`;
  }

  // Resolve an asset name to a handle, trying the name verbatim, then with the
  // extension stripped, then the basename. Preload registers all three forms.
  lookupImage(name) {
    let h = this.imageByName.get(name);
    if (h !== undefined) return h;
    h = this.imageByName.get(this.basename(name));
    return h !== undefined ? h : 0;
  }
  lookupSound(name) {
    let h = this.soundByName.get(name);
    if (h !== undefined) return h;
    h = this.soundByName.get(this.basename(name));
    return h !== undefined ? h : 0;
  }
  lookupFont(name) {
    let h = this.fontByName.get(name);
    if (h !== undefined) return h;
    h = this.fontByName.get(this.basename(name));
    return h !== undefined ? h : 0;
  }
  basename(path) {
    const base = path.split('/').pop();
    const dot = base.lastIndexOf('.');
    return dot > 0 ? base.slice(0, dot) : base;
  }

  // Mirrors bossman-apple's SoundManager.pickBossVoice + bestVoice.
  // Splits voices into NON-female and female pools (matching Apple's
  // gender filter — the Web Speech API doesn't expose v.gender, so we
  // match on a name-fragments list the consumer supplies). For each
  // pool, walks the preference list in order; first match wins, ranked
  // by premium > enhanced > anything within the match. Tries the entire
  // non-female pipeline (en-US -> any-English -> all) BEFORE touching
  // any female voice, so we never pick a female voice when a male one
  // exists anywhere in the pool.
  _pickTTSVoice() {
    if (this._ttsVoice) return this._ttsVoice;
    if (typeof speechSynthesis === 'undefined') return null;
    const all = speechSynthesis.getVoices();
    if (!all || !all.length) return null;
    const robotic = this._ttsRobotic;
    const female  = this._ttsFemale;
    const matches = (v, fragments) => {
      const id = ((v.voiceURI || '') + ' ' + (v.name || '')).toLowerCase();
      return fragments.some((f) => id.includes(f));
    };
    const usable = all.filter((v) => !matches(v, robotic));
    const nonFemale = usable.filter((v) => !matches(v, female));
    const femaleOnly = usable.filter((v) =>  matches(v, female));
    const usOnly = (a) => a.filter((v) => v.lang === 'en-US');
    const anyEn  = (a) => a.filter((v) => (v.lang || '').startsWith('en'));
    const rank = (v) => {
      const id = ((v.voiceURI || '') + ' ' + (v.name || '')).toLowerCase();
      if (id.includes('premium')) return 2;
      if (id.includes('enhanced')) return 1;
      return 0;
    };
    const best = (pool) => {
      if (!pool.length) return null;
      for (const name of this._ttsPreferred) {
        const m = pool.filter((v) => {
          const id = ((v.voiceURI || '') + ' ' + (v.name || '')).toLowerCase();
          return id.includes(name);
        });
        if (m.length) {
          m.sort((a, b) => rank(b) - rank(a));
          return m[0];
        }
      }
      return pool.slice().sort((a, b) => rank(b) - rank(a))[0];
    };
    const v =
      best(usOnly(nonFemale)) ||
      best(anyEn(nonFemale))  ||
      best(nonFemale)         ||
      best(usOnly(femaleOnly)) ||
      best(anyEn(femaleOnly))  ||
      best(femaleOnly);
    this._ttsVoice = v || null;
    return this._ttsVoice;
  }

  // Safari gates Web Speech behind a user gesture and silently drops utterances
  // fired outside one, and it does not reliably fire onvoiceschanged. Called from
  // the first keydown/mousedown/touchstart: speak a silent utterance to unlock the
  // synth for the session, then poll getVoices() (Safari's event is flaky) and
  // drain anything queued before voices were ready.
  _primeSpeech() {
    if (this._speechPrimed || typeof speechSynthesis === 'undefined' || IS_IOS) return;
    this._speechPrimed = true;
    try {
      speechSynthesis.resume();
      const u = new SpeechSynthesisUtterance(' ');
      u.volume = 0;
      speechSynthesis.speak(u);
    } catch (_e) {}
    let tries = 0;
    const poll = () => {
      this._ttsVoice = null;
      const v = this._pickTTSVoice();
      if (v && this._ttsPending.length) {
        const pending = this._ttsPending; this._ttsPending = [];
        for (const u of pending) { u.voice = v; try { speechSynthesis.speak(u); } catch (_e) {} }
      }
      if (!v && ++tries < 8) setTimeout(poll, 250);
    };
    poll();
  }

  // iOS Safari only lets speech run inside/just-after a user gesture, so keep the
  // synth "warm" by re-priming on every button/tap/key. A silent utterance unlocks
  // the window without interrupting a line that's actually speaking.
  _reprimeSpeech() {
    if (typeof speechSynthesis === 'undefined' || IS_IOS) return;
    try {
      speechSynthesis.resume();
      if (!speechSynthesis.speaking && !speechSynthesis.pending) {
        const u = new SpeechSynthesisUtterance(' ');
        u.volume = 0;
        speechSynthesis.speak(u);
      }
    } catch (_e) {}
  }

  // Duck every active snd voice (music + SFX + gold-disc bass) to `factor` of
  // its base gain; called with 0.25 while a TTS voice speaks and 1 when it ends.
  _setDuck(factor) {
    this.duckFactor = factor;
    if (!this.audioCtx) return;
    for (const v of this.voices.values()) {
      if (v.gain) v.gain.gain.setTargetAtTime((v.base ?? 1) * factor, this.audioCtx.currentTime, 0.05);
    }
  }

  // CSS fallback when the real Fullscreen API is unavailable (iPhone Safari):
  // pin the canvas over the viewport, and ask an embedding page (the website's
  // iframe) to expand itself. A synthetic resize recomputes the backing store.
  _pseudoFullscreen(on) {
    this._pseudoFsOn = on;
    const s = this.canvas.style;
    if (on) {
      s.position = 'fixed'; s.top = '0'; s.left = '0';
      s.width = '100vw'; s.height = '100dvh';
      s.maxWidth = 'none'; s.maxHeight = 'none'; s.zIndex = '99999';
    } else {
      s.position = ''; s.top = ''; s.left = '';
      s.width = ''; s.height = '';
      s.maxWidth = ''; s.maxHeight = ''; s.zIndex = '';
    }
    try {
      if (window.parent && window.parent !== window) {
        window.parent.postMessage(on ? 'wasmweb:fullscreen' : 'wasmweb:exit-fullscreen', '*');
      }
    } catch (_e) {}
    setTimeout(() => { try { window.dispatchEvent(new Event('resize')); } catch (_e) {} }, 0);
  }

  // Double-tap toggles fullscreen (enter if not in it, exit if in it), real API
  // where available and the iPhone pseudo-fullscreen otherwise.
  _toggleFullscreen() {
    const el = this.canvas;
    const inFs = this._pseudoFsOn || document.fullscreenElement || document.webkitFullscreenElement;
    if (inFs) {
      if (document.exitFullscreen) document.exitFullscreen().catch(() => {});
      else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
      this._pseudoFullscreen(false);
    } else {
      if (el.requestFullscreen) el.requestFullscreen().catch(() => this._pseudoFullscreen(true));
      else if (el.webkitRequestFullscreen) el.webkitRequestFullscreen();
      else this._pseudoFullscreen(true);
    }
  }

  ensureAudio() {
    if (!this.audioCtx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) {
        try {
          this.audioCtx = new AC();
          // Chrome caps a tab at 6 AudioContexts and does NOT release them on
          // page reload. Without an explicit close() each reload (every dev
          // iteration) leaks one until Web Audio stops producing sound — while
          // SpeechSynthesis/voice keeps working, since it's a separate
          // subsystem — and only a full browser restart recovers. Closing on
          // unload frees this page's context so reloads no longer accumulate.
          // Null it out too: if the page is later restored from Safari's
          // back-forward cache, ensureAudio() then builds a fresh context
          // instead of returning the dead closed one.
          const closeCtx = () => { try { this.audioCtx && this.audioCtx.close(); } catch (_e) {} this.audioCtx = null; };
          window.addEventListener('pagehide', closeCtx);
          window.addEventListener('beforeunload', closeCtx);
        } catch (e) {
          // Limit already hit from prior reloads: don't throw, just warn.
          console.error('AudioContext construction failed — Chrome hardware-context limit (6) likely reached from earlier reloads. Quit and reopen the browser to reset it.', e);
          this.audioCtx = null;
        }
      }
    }
    // Resume on ANY non-running state: 'suspended' (autoplay gate) and Safari's
    // 'interrupted' (window backgrounded/minimized) both need a resume; skip
    // 'closed' (resume would throw). Safari's lower context cap (~4) makes the
    // close-on-unload above mandatory.
    if (this.audioCtx && this.audioCtx.state !== 'running' && this.audioCtx.state !== 'closed' && !document.hidden) {
      this.audioCtx.resume();
    }
    return this.audioCtx;
  }

  // ==========================================================================
  // asset preload (everything decoded BEFORE boot)
  // ==========================================================================
  async preload() {
    const manifest = await this.discoverAssets();

    // fonts: FontFace per ttf, family name = filename without extension
    await Promise.all(manifest.fonts.map(async (path) => {
      const family = this.basename(path);
      try {
        const ff = new FontFace(family, `url(${ASSET_ROOT}/${path})`);
        await ff.load();
        document.fonts.add(ff);
        this.fonts.push(family);
        const handle = this.fonts.length - 1;
        this.registerName(this.fontByName, path, family, handle);
      } catch (e) { console.warn('font load failed', path, e); }
    }));

    // images: ImageBitmap from each png
    await Promise.all(manifest.images.map(async (path) => {
      try {
        const resp = await fetch(`${ASSET_ROOT}/${path}`);
        const blob = await resp.blob();
        const bmp = await createImageBitmap(blob);
        this.images.push({ source: bmp, width: bmp.width, height: bmp.height });
        const handle = this.images.length - 1;
        this.registerName(this.imageByName, path, this.basename(path), handle);
      } catch (e) { console.warn('image load failed', path, e); }
    }));

    // sounds: decode each wav with the AudioContext
    const ctx = this.ensureAudio();
    await Promise.all(manifest.sounds.map(async (path) => {
      try {
        const resp = await fetch(`${ASSET_ROOT}/${path}`);
        const arr = await resp.arrayBuffer();
        const buf = await ctx.decodeAudioData(arr);
        this.sounds.push(buf);
        const handle = this.sounds.length - 1;
        this.registerName(this.soundByName, path, this.basename(path), handle);
      } catch (e) { console.warn('sound load failed', path, e); }
    }));

    // text assets (levels.json, etc.): fetched as strings and exposed to the
    // wasm via asset_text(). Registered under full path, basename, and
    // basename-without-extension so any caller spelling resolves.
    await Promise.all((manifest.texts || ['levels.json']).map(async (path) => {
      try {
        const resp = await fetch(`${ASSET_ROOT}/${path}`);
        if (!resp.ok) return;
        const s = await resp.text();
        const base = path.split('/').pop();
        this.texts.set(path, s);
        this.texts.set('assets/' + path, s);
        this.texts.set(base, s);
        this.texts.set(this.basename(path), s);
      } catch (e) { console.warn('text load failed', path, e); }
    }));
  }

  // Register an asset under both its full relative path (as the C++ asset layer
  // passes, e.g. "assets/voice/capture_1.wav") and its bare basename
  // ("capture_1"), so lookups succeed regardless of which the caller uses.
  registerName(map, path, base, handle) {
    map.set(path, handle);                 // relative-to-assets, e.g. voice/x.wav
    map.set('assets/' + path, handle);     // full path the C++ uses
    map.set(base, handle);                 // bare name
  }

  // manifest.json lives next to this file (web/) and is regenerated from the
  // native assets tree by build-web.sh, so it never goes stale.
  async discoverAssets() {
    const manifest = await fetch('manifest.json')
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null);
    if (manifest) return manifest;
    // Fallback: minimal hardcoded manifest (matches current assets/).
    return {
      fonts: [
        'fonts/JetBrainsMono-Bold.ttf',
        'fonts/MarkerFelt-Thin.ttf',
        'fonts/MarkerFelt-Wide.ttf',
      ],
      images: ['images/red-stapler.png'],
      sounds: [],
    };
  }

  // ==========================================================================
  // DOM wiring + main loop
  // ==========================================================================
  wireInput() {
    const onResume = () => { this.ensureAudio(); this._primeSpeech(); };
    addEventListener('keydown', onResume, { once: true });
    addEventListener('mousedown', onResume, { once: true });
    addEventListener('touchstart', onResume, { once: true });

    // Go silent + idle while the tab is backgrounded: a tab that keeps a
    // looping AudioContext audible in the background is far more likely to be
    // reclaimed and auto-reloaded by Safari. Suspend on hide, resume on return.
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        if (this.audioCtx && this.audioCtx.state === 'running') this.audioCtx.suspend();
      } else {
        this.ensureAudio();
      }
    });

    addEventListener('keydown', (e) => {
      if (!e.repeat) this._reprimeSpeech();   // keep TTS warm on every key (Play/Esc/F/...)
      const sf = DOM_TO_SF.get(e.code);
      if (sf === undefined) return;
      e.preventDefault();
      const repeat = this.pressed.has(e.code);
      this.pressed.add(e.code);
      if (!repeat) {
        this.events.push({
          type: EVT.KeyPressed, a: sf,
          b: e.shiftKey ? 1 : 0, c: (e.metaKey || e.ctrlKey) ? 1 : 0, d: 0,
        });
      }
    });
    addEventListener('keyup', (e) => {
      const sf = DOM_TO_SF.get(e.code);
      if (sf === undefined) return;
      e.preventDefault();
      this.pressed.delete(e.code);
      this.events.push({
        type: EVT.KeyReleased, a: sf,
        b: e.shiftKey ? 1 : 0, c: (e.metaKey || e.ctrlKey) ? 1 : 0, d: 0,
      });
    });

    this.canvas.addEventListener('mousedown', (e) => {
      this._reprimeSpeech();   // keep TTS warm on every click
      const btn = e.button === 2 ? 1 : (e.button === 0 ? 0 : -1);
      if (btn < 0) return;
      this.mouseDown[btn] = true;
      const p = this.toLogical(e);
      this.events.push({ type: EVT.MouseButtonPressed, a: btn, b: p.x, c: p.y, d: 0 });
    });
    addEventListener('mouseup', (e) => {
      const btn = e.button === 2 ? 1 : (e.button === 0 ? 0 : -1);
      if (btn < 0) return;
      this.mouseDown[btn] = false;
      const p = this.toLogical(e);
      this.events.push({ type: EVT.MouseButtonReleased, a: btn, b: p.x, c: p.y, d: 0 });
    });
    this.canvas.addEventListener('mousemove', (e) => {
      const p = this.toLogical(e);
      this.mouseX = p.x; this.mouseY = p.y;
      this.events.push({ type: EVT.MouseMoved, a: p.x, b: p.y, c: 0, d: 0 });
    });
    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());

    // Touch -> the same pointer events the app already consumes, so a touch
    // tap behaves like a left click and a touch drag behaves like a press-drag
    // (the app turns drags into swipes). touch-action:none stops the browser
    // from scrolling/zooming the page out from under the gesture.
    this.canvas.style.touchAction = 'none';
    const touchAt = (t) => this.toLogical({ clientX: t.clientX, clientY: t.clientY });
    this.canvas.addEventListener('touchstart', (e) => {
      this._reprimeSpeech();   // keep TTS warm on every tap
      if (!e.changedTouches.length) return;
      this.mouseDown[0] = true;
      const p = touchAt(e.changedTouches[0]);
      this._touchStartX = p.x; this._touchStartY = p.y; this._touchMoved = false;
      this.mouseX = p.x; this.mouseY = p.y;
      this.events.push({ type: EVT.MouseButtonPressed, a: 0, b: p.x, c: p.y, d: 0 });
      e.preventDefault();
    }, { passive: false });
    this.canvas.addEventListener('touchmove', (e) => {
      if (!e.touches.length) return;
      const p = touchAt(e.touches[0]);
      if (Math.abs(p.x - this._touchStartX) > 16 || Math.abs(p.y - this._touchStartY) > 16) this._touchMoved = true;
      this.mouseX = p.x; this.mouseY = p.y;
      this.events.push({ type: EVT.MouseMoved, a: p.x, b: p.y, c: 0, d: 0 });
      e.preventDefault();
    }, { passive: false });
    const onTouchEnd = (e) => {
      if (!e.changedTouches.length) return;
      this.mouseDown[0] = false;
      const p = touchAt(e.changedTouches[0]);
      this.events.push({ type: EVT.MouseButtonReleased, a: 0, b: p.x, c: p.y, d: 0 });
      e.preventDefault();
      // Double-tap toggles fullscreen, but only on a CLEAN tap: not a swipe (moved)
      // and not in the bottom fire-button zone, so firing + steering never trigger it.
      const cleanTap = !this._touchMoved && p.y < LOGICAL_H - 180;
      if (cleanTap) {
        const now = Date.now();
        if (this._lastTapAt && now - this._lastTapAt < 300) {
          this._lastTapAt = 0;
          this._toggleFullscreen();
        } else {
          this._lastTapAt = now;
        }
      } else {
        this._lastTapAt = 0;   // a swipe or fire tap breaks the double-tap chain
      }
    };
    this.canvas.addEventListener('touchend', onTouchEnd, { passive: false });
    this.canvas.addEventListener('touchcancel', onTouchEnd, { passive: false });

    // Defer to the next frame: fullscreenchange/resize fire before the element
    // box is reflowed, so getBoundingClientRect would still report the old size.
    const relayout = () => requestAnimationFrame(() => {
      this.layout();
      this.events.push({ type: EVT.Resized, a: LOGICAL_W, b: LOGICAL_H, c: 0, d: 0 });
    });
    addEventListener('resize', relayout);
    document.addEventListener('fullscreenchange', relayout);
    document.addEventListener('webkitfullscreenchange', relayout);
    addEventListener('beforeunload', () => {
      this.events.push({ type: EVT.Closed, a: 0, b: 0, c: 0, d: 0 });
    });
  }

  // Poll the Web Gamepad API once per frame. USB arcade joysticks register as
  // standard gamepads (often as "Generic USB Joystick" with axes 0/1 = X/Y),
  // so the same loop handles them and Xbox/PlayStation/Switch controllers.
  // Snapshots the connected pads for the gp_* imports and (if gpMapToKeys is
  // on) synthesizes keydown/keyup events on edges of the d-pad, left stick,
  // and the A/Start buttons so games written for arrow keys + Space just work.
  pollGamepads() {
    if (!this.gpEnabled || !navigator.getGamepads) return;
    const pads = navigator.getGamepads();
    const snap = [];
    const dz = this.gpAxisDeadzone;
    for (let i = 0; i < 4; i++) {
      const p = pads[i];
      if (!p) { snap[i] = null; continue; }
      const buttons = new Array(p.buttons.length);
      const values = new Array(p.buttons.length);
      for (let b = 0; b < p.buttons.length; b++) {
        const btn = p.buttons[b];
        const v = typeof btn === 'object' ? btn.value : (btn ? 1 : 0);
        const pressed = typeof btn === 'object' ? btn.pressed : !!btn;
        buttons[b] = pressed ? 1 : 0;
        values[b] = v;
      }
      const ax = p.axes || [];
      snap[i] = { buttons, values, axes: ax };

      if (!this.gpMapToKeys) continue;

      // Direction = d-pad OR left stick past deadzone.
      const left  = buttons[14] || (ax[0] || 0) < -dz;
      const right = buttons[15] || (ax[0] || 0) >  dz;
      const up    = buttons[12] || (ax[1] || 0) < -dz;
      const down  = buttons[13] || (ax[1] || 0) >  dz;
      const fire  = buttons[0];   // A / Cross / South -> Space
      const pause = buttons[9];   // Start             -> P

      const prev = this.gpPrev[i] || { left: 0, right: 0, up: 0, down: 0, fire: 0, pause: 0 };
      this.emitSynthKey('ArrowLeft',  left,  prev.left);
      this.emitSynthKey('ArrowRight', right, prev.right);
      this.emitSynthKey('ArrowUp',    up,    prev.up);
      this.emitSynthKey('ArrowDown',  down,  prev.down);
      this.emitSynthKey('Space',      fire,  prev.fire);
      this.emitSynthKey('KeyP',       pause, prev.pause);
      this.gpPrev[i] = { left, right, up, down, fire, pause };
    }
    this.gpSnap = snap;
  }

  // Edge-trigger a synthetic key event. Mirrors the keydown/keyup wiring in
  // wireInput(): both queues an EVT.KeyPressed/KeyReleased and updates the
  // pressed-set the game polls via key_pressed().
  emitSynthKey(code, now, prev) {
    if (!now === !prev) return;
    const sf = DOM_TO_SF.get(code);
    if (now) {
      this.pressed.add(code);
      if (sf !== undefined) this.events.push({ type: EVT.KeyPressed, a: sf, b: 0, c: 0, d: 0 });
    } else {
      this.pressed.delete(code);
      if (sf !== undefined) this.events.push({ type: EVT.KeyReleased, a: sf, b: 0, c: 0, d: 0 });
    }
  }

  // Size the canvas backing store to the displayed pixels (x devicePixelRatio)
  // so the game, which draws in logical 1184x644, renders crisp at any window or
  // fullscreen size. baseScale/offX/offY letterbox logical space into the store.
  layout() {
    const dpr = window.devicePixelRatio || 1;
    const rect = this.canvas.getBoundingClientRect();
    const availW = (rect.width || LOGICAL_W) * dpr;
    const availH = (rect.height || LOGICAL_H) * dpr;
    // Backing store keeps the game's aspect ratio, so logical content always
    // fills it exactly (never clips). CSS object-fit: contain letterboxes the
    // display when the element box has a different aspect (e.g. fullscreen).
    const S = Math.max(1, Math.min(availW / LOGICAL_W, availH / LOGICAL_H));
    const W = Math.round(LOGICAL_W * S);
    const H = Math.round(LOGICAL_H * S);
    if (this.canvas.width !== W) this.canvas.width = W;
    if (this.canvas.height !== H) this.canvas.height = H;
    this.baseScale = S;
    this.offX = 0;
    this.offY = 0;
  }

  // Convert a mouse event's client coords to logical game pixels, accounting for
  // the object-fit: contain letterbox between the element box and the backing.
  toLogical(e) {
    const rect = this.canvas.getBoundingClientRect();
    const scale = Math.min(rect.width / LOGICAL_W, rect.height / LOGICAL_H);
    const dispX = rect.left + (rect.width - LOGICAL_W * scale) / 2;
    const dispY = rect.top + (rect.height - LOGICAL_H * scale) / 2;
    return {
      x: Math.round((e.clientX - dispX) / scale),
      y: Math.round((e.clientY - dispY) / scale),
    };
  }

  async load(url) {
    await this.preload();

    const imports = {
      env: this.envImports(),
      wasi_snapshot_preview1: this.wasiImports(),
    };
    // Prefer streaming, but fall back to fetch->arrayBuffer->instantiate so we
    // work even when the server doesn't send Content-Type: application/wasm
    // (instantiateStreaming hard-requires it; plain instantiate doesn't care).
    let instance;
    try {
      ({ instance } = await WebAssembly.instantiateStreaming(fetch(url), imports));
    } catch (_e) {
      const bytes = await fetch(url).then((r) => r.arrayBuffer());
      ({ instance } = await WebAssembly.instantiate(bytes, imports));
    }
    this.exports = instance.exports;
    this.wasmMemory = this.exports.memory;

    this.layout();                // hi-res backing store before the first frame

    this.exports._initialize();   // libc/libc++ init + global ctors
    this.exports.boot();

    this.wireInput();

    let last = performance.now();
    const loop = (t) => {
      const dt = t - last;
      last = t;
      try {
        this.pollGamepads();        // emit synthetic key events before the frame
        this.exports.frame(dt);
      } catch (err) {
        console.error('frame() threw', err);
        return;   // stop the loop on a fatal trap
      }
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }
}

window.addEventListener('DOMContentLoaded', () => {
  if (CFG.title) document.title = CFG.title;
  const canvas = document.getElementById(CFG.canvasId);
  new Runtime(canvas).load(CFG.wasmUrl).catch((e) => {
    console.error('runtime failed to start', e);
  });
});
