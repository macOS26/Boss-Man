// Toolchain + runtime proof for the hand-rolled WebAssembly port.
// No Emscripten: compiled with WASI SDK clang to wasm32-wasi (reactor model),
// driven by our own runtime.js. Proves wasm->JS imports and JS->wasm exports
// both work, that libc++/STL init runs, and that a RAF loop animates Canvas2D.

#include <cstdint>
#include <cmath>
#include <vector>
#include <string>

#define WASM_IMPORT(name) __attribute__((import_module("env"), import_name(name)))
#define WASM_EXPORT(name) __attribute__((export_name(name)))

extern "C" {
WASM_IMPORT("js_log")       void js_log(const char* ptr, int len);
WASM_IMPORT("gfx_clear")    void gfx_clear(int r, int g, int b);
WASM_IMPORT("gfx_fill_rect") void gfx_fill_rect(float x, float y, float w, float h,
                                                int r, int g, int b);
WASM_IMPORT("gfx_fill_circle") void gfx_fill_circle(float cx, float cy, float radius,
                                                    int r, int g, int b);
WASM_IMPORT("audio_beep")   void audio_beep(float freq, float durMs);
}

static void log(const std::string& s) { js_log(s.data(), (int)s.size()); }

static double g_t = 0.0;
static std::vector<float> g_proof;
static float g_lastKeyX = 600.f;

extern "C" WASM_EXPORT("boot") void boot() {
    g_proof.assign(8, 3.14f);
    float sum = 0; for (float v : g_proof) sum += v;
    log("BOSS-MAN wasm runtime booted; STL vector sum=" + std::to_string(sum));
}

extern "C" WASM_EXPORT("frame") void frame(double dtMs) {
    g_t += dtMs / 1000.0;
    gfx_clear(18, 18, 28);
    float x = 600.f + std::sin(g_t) * 360.f;
    gfx_fill_rect(x, 280.f, 96.f, 96.f, 240, 200, 40);            // bouncing block
    gfx_fill_circle(g_lastKeyX, 480.f, 28.f, 90, 200, 255);       // moves on keypress
}

// JS pushes keyboard here: code is a small int we define in runtime.js.
extern "C" WASM_EXPORT("key_event") void key_event(int code, int down) {
    if (!down) return;
    if (code == 1) g_lastKeyX -= 40.f;  // Left
    if (code == 2) g_lastKeyX += 40.f;  // Right
    if (code == 3) { audio_beep(440.f, 120.f); log("space -> beep"); }
}
