// BOSS-MAN web runtime. Hand-rolled: loads a wasm32-wasi module built with the
// WASI SDK (no Emscripten), provides the handful of WASI preview1 syscalls it
// references, and implements our platform imports (gfx/audio/input) on Canvas2D
// + WebAudio. The wasm exports a reactor `_initialize` plus boot/frame/key_event.

const KEY = { ArrowLeft: 1, ArrowRight: 2, Space: 3 };

class Runtime {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d', { alpha: false });
    this.memory = null;
    this.exports = null;
    this.audio = null;
    this.textDecoder = new TextDecoder('utf-8');
  }

  // ---- WASI preview1 (only what the binary imports) ----
  wasiImports() {
    const mem = () => new DataView(this.memory.buffer);
    return {
      fd_close: () => 0,
      fd_seek: () => 0,
      fd_write: (fd, iovsPtr, iovsLen, nwrittenPtr) => {
        const dv = mem();
        let total = 0;
        const parts = [];
        for (let i = 0; i < iovsLen; i++) {
          const base = iovsPtr + i * 8;
          const ptr = dv.getUint32(base, true);
          const len = dv.getUint32(base + 4, true);
          parts.push(new Uint8Array(this.memory.buffer, ptr, len));
          total += len;
        }
        const text = parts.map((p) => this.textDecoder.decode(p)).join('');
        (fd === 2 ? console.error : console.log)('[wasm] ' + text.replace(/\n$/, ''));
        dv.setUint32(nwrittenPtr, total, true);
        return 0;
      },
    };
  }

  // ---- our platform imports (env) ----
  envImports() {
    const ctx = this.ctx;
    return {
      js_log: (ptr, len) => {
        const s = this.textDecoder.decode(new Uint8Array(this.memory.buffer, ptr, len));
        console.log('%c[boss] ' + s, 'color:#e6b800');
      },
      gfx_clear: (r, g, b) => {
        ctx.fillStyle = `rgb(${r},${g},${b})`;
        ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
      },
      gfx_fill_rect: (x, y, w, h, r, g, b) => {
        ctx.fillStyle = `rgb(${r},${g},${b})`;
        ctx.fillRect(x, y, w, h);
      },
      gfx_fill_circle: (cx, cy, radius, r, g, b) => {
        ctx.fillStyle = `rgb(${r},${g},${b})`;
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, Math.PI * 2);
        ctx.fill();
      },
      audio_beep: (freq, durMs) => {
        if (!this.audio) this.audio = new (window.AudioContext || window.webkitAudioContext)();
        const o = this.audio.createOscillator();
        const g = this.audio.createGain();
        o.frequency.value = freq;
        g.gain.value = 0.15;
        o.connect(g).connect(this.audio.destination);
        const now = this.audio.currentTime;
        o.start(now);
        g.gain.setValueAtTime(0.15, now);
        g.gain.exponentialRampToValueAtTime(0.0001, now + durMs / 1000);
        o.stop(now + durMs / 1000);
      },
    };
  }

  async load(url) {
    const imports = { env: this.envImports(), wasi_snapshot_preview1: this.wasiImports() };
    const { instance } = await WebAssembly.instantiateStreaming(fetch(url), imports);
    this.exports = instance.exports;
    this.memory = this.exports.memory;
    this.exports._initialize();   // run libc/libc++ init + global ctors
    this.exports.boot();

    addEventListener('keydown', (e) => {
      const code = KEY[e.code];
      if (code) { e.preventDefault(); this.exports.key_event(code, 1); }
    });
    addEventListener('keyup', (e) => {
      const code = KEY[e.code];
      if (code) { e.preventDefault(); this.exports.key_event(code, 0); }
    });

    let last = performance.now();
    const loop = (t) => {
      const dt = t - last; last = t;
      this.exports.frame(dt);
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }
}

window.addEventListener('DOMContentLoaded', () => {
  const canvas = document.getElementById('game');
  new Runtime(canvas).load('boss.wasm');
});
