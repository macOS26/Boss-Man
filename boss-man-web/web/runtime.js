// BOSS-MAN web runtime. Hand-rolled: loads a wasm32-wasi module built with the
// WASI SDK (no Emscripten), provides the WASI preview1 syscalls the binary
// references, and implements the platform/web/abi.h `env` imports on Canvas2D +
// WebAudio + DOM. The wasm is a reactor module exporting `_initialize`, `boot`,
// `frame`, and `memory`.
//
// SERVING: serve from the boss-man-web/ root so that web/index.html can fetch
// its assets at ../assets/... cleanly. From boss-man-web/:
//     python3 -m http.server 8080
// then open http://localhost:8080/web/   (assets resolve via ../assets/, the
// wasm via ./boss.wasm). No build step beyond build-web.sh is required.

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

const LOGICAL_W = 1184;
const LOGICAL_H = 666;

// Asset roots, relative to web/index.html.
const ASSET_ROOT = '../assets';

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
    const { instance } = await WebAssembly.instantiateStreaming(fetch(url), imports);
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
  const canvas = document.getElementById('game');
  new Runtime(canvas).load('boss.wasm').catch((e) => {
    console.error('runtime failed to start', e);
  });
});
