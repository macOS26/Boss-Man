// BOSS-MAN web platform ABI: the contract between the wasm module (our sf:: layer)
// and runtime.js (Canvas2D + WebAudio + DOM). Every sf:: call on web bottoms out
// in one of these imported functions. runtime.js implements exactly this list.
//
// Conventions:
//  - Colors are packed 0xRRGGBBAA in a uint32.
//  - A "target" is a draw surface handle: 0 = the screen canvas; >0 = a render
//    texture from rt_create. gfx_target(h) selects the active target; all gfx_*
//    draw to it until changed. State (transform/alpha/blend) is per-target with a
//    save/restore stack (maps to Canvas2D save/restore).
//  - Coordinates are logical game pixels (canvas backing store is the fixed
//    logical size; CSS scales it). So mouse events arrive already in logical px.
//  - Image/font/sound handles are small ints minted by JS; 0 means "not loaded".
//  - Assets are preloaded by JS before boot(); *_by_name looks them up.
#pragma once
#include <cstdint>

#define WABI __attribute__((import_module("env")))

extern "C" {

// ---- logging ----
WABI void js_log(const char* ptr, int len);

// ---- target + transform/blend state ----
WABI void gfx_target(int target);                 // 0 = screen
WABI void gfx_clear(uint32_t rgba);
WABI void gfx_save();
WABI void gfx_restore();
WABI void gfx_translate(float x, float y);
WABI void gfx_scale(float sx, float sy);
WABI void gfx_rotate(float degrees);
WABI void gfx_set_alpha(float a);                  // 0..1, multiplies
WABI void gfx_set_blend(int mode);                 // 0 alpha, 1 add, 2 multiply, 3 none

// ---- primitives (current target, current transform) ----
WABI void gfx_fill_rect(float x, float y, float w, float h, uint32_t rgba);
WABI void gfx_stroke_rect(float x, float y, float w, float h, float thickness, uint32_t rgba);
WABI void gfx_fill_circle(float cx, float cy, float r, uint32_t rgba);
WABI void gfx_stroke_circle(float cx, float cy, float r, float thickness, uint32_t rgba);
WABI void gfx_fill_poly(const float* xy, int npts, uint32_t rgba);
WABI void gfx_stroke_poly(const float* xy, int npts, int closed, float thickness, uint32_t rgba);

// textured quad: src rect (in image px) -> dst rect, modulated by rgba (tint+alpha)
WABI void gfx_draw_image(int img, float sx, float sy, float sw, float sh,
                         float dx, float dy, float dw, float dh, uint32_t rgba);

// ---- text (Canvas2D fillText; renders emoji too) ----
// font 0 = default; sizePx in logical px; returns measured width. height ~= sizePx.
WABI int  txt_width(int font, const char* utf8, int len, int sizePx, float letterSpacing);
WABI void gfx_draw_text(int font, const char* utf8, int len, float x, float y,
                        int sizePx, uint32_t rgba, float letterSpacing);
// Selects Canvas2D textBaseline for subsequent gfx_draw_text calls.
//   0 = alphabetic (true typographic baseline; the default)
//   1 = middle     (vertical CENTRE of the glyph bounding box — what SK
//                  .center alignment actually means; gives correct emoji
//                  centring without per-glyph metrics)
//   2 = top
//   3 = bottom
WABI void gfx_set_text_baseline(int mode);

// ---- images / fonts / render textures (loaded/created via JS) ----
WABI int  img_by_name(const char* name, int len);  // preloaded image -> handle
WABI int  img_from_rgba(const uint8_t* px, int w, int h); // raw RGBA -> handle
WABI int  img_width(int img);
WABI int  img_height(int img);
WABI int  font_by_name(const char* name, int len);
// Reads a preloaded text asset (e.g. levels.json) into buf; returns length or -1.
WABI int  asset_text(const char* name, int nlen, char* buf, int cap);
// True if a preloaded asset (image/font/sound/text) is registered under name.
WABI int  asset_exists(const char* name, int len);
WABI int  rt_create(int w, int h);                 // offscreen target -> target handle
WABI int  rt_image(int rt);                        // image handle backed by the RT

// ---- audio (WebAudio) ----
WABI int  snd_from_samples(const int16_t* samples, int frames, int channels, int rate);
WABI int  snd_by_name(const char* name, int len);  // preloaded clip -> buffer handle
// Build a sound buffer directly from a Float32 PCM sample array. Used for
// procedurally-synthesized music (bossman-apple's SoundManager generates
// the background loop in real-time; the wasm port does the same and
// hands the buffer to the runtime through this hook).
WABI int  snd_create_pcm(const float* samples, int frameCount, int sampleRate);
WABI int  snd_play(int buffer, float volume, int loop); // -> voice handle
WABI void snd_stop(int voice);
WABI void snd_set_volume(int voice, float volume);
WABI int  snd_status(int voice);                   // 0 stopped, 1 playing, 2 paused
WABI void snd_pause_all();
WABI void snd_resume_all();

// ---- input (polling + event queue) ----
WABI int  key_pressed(int sfKey);                  // sf::Keyboard code -> 0/1
WABI int  mouse_button(int sfButton);              // 0 Left,1 Right -> 0/1
WABI int  mouse_x();
WABI int  mouse_y();
// Drains one event. Returns 0 if queue empty, else 1 and fills the out ints.
// type matches sf::Event::EventType ordering used by our Window/Event.hpp.
WABI int  evt_poll(int* type, int* a, int* b, int* c, int* d);

// ---- gamepad / USB arcade joystick (Web Gamepad API) ----
// Up to 4 simultaneous controllers. USB arcade sticks register as standard
// gamepads in the browser, so the same API covers both. Buttons follow the
// W3C Standard Gamepad layout (0=A/South, 1=B/East, 2=X/West, 3=Y/North,
// 4=L1, 5=R1, 6=L2, 7=R2, 8=Select, 9=Start, 10=L3, 11=R3,
// 12=DpadUp, 13=DpadDown, 14=DpadLeft, 15=DpadRight, 16=Home).
WABI int   gp_connected(int pad);                  // 0/1
WABI int   gp_button(int pad, int button);         // 0/1 (digital edge of analog trigger)
WABI float gp_button_value(int pad, int button);   // 0..1 (analog triggers)
WABI float gp_axis(int pad, int axis);             // -1..1 (0/1 left stick, 2/3 right stick)
// Runtime can synthesize key events for d-pad/stick so games that already read
// arrow keys + Space "just work" on a gamepad. Toggleable per-game.
WABI void  gp_map_to_keys(int enable);

// ---- window ----
WABI void win_set_title(const char* s, int len);
WABI int  win_width();
WABI int  win_height();
WABI void win_request_fullscreen();
WABI void win_exit_fullscreen();
// Browser "Save As": host wraps data in a Blob and clicks a download anchor.
WABI void win_download(const char* name, int nlen, const char* data, int dlen);

// ---- persistence (localStorage-backed; for high score / levels / leaderboard) ----
// Reads up to cap bytes into buf; returns actual length (or -1 if absent).
WABI int  store_get(const char* key, int klen, char* buf, int cap);
WABI void store_set(const char* key, int klen, const char* val, int vlen);

}  // extern "C"

#undef WABI
