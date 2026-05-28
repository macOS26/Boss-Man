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
  0: 'KeyA',  2: 'KeyC',  3: 'KeyD',  4: 'KeyE',  5: 'KeyF',
  15: 'KeyP', 17: 'KeyR', 18: 'KeyS', 21: 'KeyV', 22: 'KeyW', 25: 'KeyZ',
  36: 'Escape',
  57: 'Space',
  59: 'Backspace',
  71: 'ArrowLeft', 72: 'ArrowRight', 73: 'ArrowUp', 74: 'ArrowDown',
  26: 'Digit0', 27: 'Digit1', 28: 'Digit2', 29: 'Digit3', 30: 'Digit4',
  31: 'Digit5', 32: 'Digit6', 33: 'Digit7', 34: 'Digit8', 35: 'Digit9',
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

    // ---- handle tables (1-based; 0 means "not loaded/none") ----
    this.images = [null];   // each: { source, width, height }  source = drawable
    this.fonts = [null];    // each: family string ; index 0 is implicit default
    this.sounds = [null];   // each: AudioBuffer
    this.imageByName = new Map();
    this.soundByName = new Map();
    this.fontByName = new Map();
    this.texts = new Map();   // text assets (levels.json, ...) for asset_text

    // ---- audio ----
    this.audioCtx = null;
    this.voices = new Map();   // voice handle -> { source, gain, state }
    this.nextVoice = 1;

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
          c.drawImage(rec.source, sx, sy, sw, sh, dx, dy, dw, dh);
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
      gfx_draw_text: (font, ptr, len, x, y, sizePx, rgba, letterSpacing) => {
        const c = this.ctx2d();
        const s = this.cstr(ptr, len);
        this.applyFont(c, font, sizePx, letterSpacing);
        c.textBaseline = 'top';
        c.textAlign = 'left';
        c.fillStyle = this.css(rgba);
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
      snd_play: (buffer, volume, loop) => {
        const ctx = this.ensureAudio();
        const buf = this.sounds[buffer];
        if (!ctx || !buf) return 0;
        const src = ctx.createBufferSource();
        src.buffer = buf;
        src.loop = !!loop;
        const gain = ctx.createGain();
        gain.gain.value = Math.max(0, Math.min(1, volume / 100));
        src.connect(gain).connect(ctx.destination);
        const handle = this.nextVoice++;
        const voice = { source: src, gain, state: 1 };
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
        const g = Math.max(0, Math.min(1, volume / 100));
        v.gain.gain.setTargetAtTime(g, this.audioCtx.currentTime, 0.02);
      },
      snd_status: (voice) => {
        const v = this.voices.get(voice);
        return v ? v.state : 0;
      },
      snd_pause_all: () => {
        if (this.audioCtx && this.audioCtx.state === 'running') this.audioCtx.suspend();
      },
      snd_resume_all: () => {
        if (this.audioCtx && this.audioCtx.state === 'suspended') this.audioCtx.resume();
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
      tts_speak: (utf8Ptr, len, rate, pitch, volume) => {
        if (typeof speechSynthesis === 'undefined') return 0;
        const text = this.cstr(utf8Ptr, len);
        const u = new SpeechSynthesisUtterance(text);
        u.rate   = Math.max(0.1, Math.min(rate   || 1.0, 10));
        u.pitch  = Math.max(0,   Math.min(pitch  || 1.0, 2));
        u.volume = Math.max(0,   Math.min(volume || 1.0, 1));
        try { speechSynthesis.speak(u); return 1; } catch (_e) { return 0; }
      },
      tts_cancel: () => { if (typeof speechSynthesis !== 'undefined') speechSynthesis.cancel(); },

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
        const imgId = this.images.length;
        this.images.push({ source: t.canvas, width: t.canvas.width, height: t.canvas.height });
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

      // ============================================================
      // Canvas2D filter + composite ops (SKEffectNode + SKCropNode).
      // ============================================================
      gfx_set_filter: (ptr, len) => { this.ctx2d().filter = this.cstr(ptr, len); },
      gfx_clear_filter: ()       => { this.ctx2d().filter = 'none'; },
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
        if (this.canvas.requestFullscreen) this.canvas.requestFullscreen().catch(() => {});
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

  ensureAudio() {
    if (!this.audioCtx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) this.audioCtx = new AC();
    }
    if (this.audioCtx && this.audioCtx.state === 'suspended') this.audioCtx.resume();
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
    const onResume = () => this.ensureAudio();
    addEventListener('keydown', onResume, { once: false });
    addEventListener('mousedown', onResume, { once: false });

    addEventListener('keydown', (e) => {
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
