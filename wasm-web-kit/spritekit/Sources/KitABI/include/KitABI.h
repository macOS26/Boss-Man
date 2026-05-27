#pragma once
#include <stdint.h>
#define WABI __attribute__((import_module("env")))

/* graphics (see wasm-web-kit/include/abi.h) */
WABI void js_log(const char* p, int len);
WABI void gfx_clear(uint32_t rgba);
WABI void gfx_save(void);
WABI void gfx_restore(void);
WABI void gfx_translate(float x, float y);
WABI void gfx_scale(float sx, float sy);
WABI void gfx_rotate(float degrees);
WABI void gfx_set_alpha(float a);
WABI void gfx_set_blend(int mode);
WABI void gfx_fill_rect(float x, float y, float w, float h, uint32_t rgba);
WABI void gfx_stroke_rect(float x, float y, float w, float h, float t, uint32_t rgba);
WABI void gfx_fill_circle(float cx, float cy, float r, uint32_t rgba);
WABI void gfx_stroke_circle(float cx, float cy, float r, float t, uint32_t rgba);
WABI void gfx_fill_poly(const float* xy, int n, uint32_t rgba);
WABI void gfx_stroke_poly(const float* xy, int n, int closed, float t, uint32_t rgba);
WABI void gfx_draw_image(int img, float sx, float sy, float sw, float sh,
                         float dx, float dy, float dw, float dh, uint32_t rgba);
WABI int  txt_width(int font, const char* utf8, int len, int sizePx, float spacing);
WABI void gfx_draw_text(int font, const char* utf8, int len, float x, float y,
                        int sizePx, uint32_t rgba, float spacing);
WABI int  img_by_name(const char* name, int len);
WABI int  snd_by_name(const char* name, int len);
WABI int  snd_play(int buffer, float volume, int loop);

/* input */
WABI int  key_pressed(int sfKey);
WABI int  mouse_x(void);
WABI int  mouse_y(void);
WABI int  mouse_button(int b);
WABI int  evt_poll(int* type, int* a, int* b, int* c, int* d);
WABI int  win_width(void);
WABI int  win_height(void);

/* Box2D shim (defined in libcbox2d.a; see boss-man-spritekit-web/native) */
void  cb_reset(float gx, float gy);
int   cb_add_box(float x, float y, float hw, float hh, int dynamic, uint16_t cat, uint16_t mask);
int   cb_add_circle(float x, float y, float r, int dynamic, uint16_t cat, uint16_t mask);
void  cb_set_velocity(int body, float vx, float vy);
void  cb_set_transform(int body, float x, float y, float angle);
void  cb_get_position(int body, float* x, float* y);
float cb_get_angle(int body);
void  cb_step(float dt);
int   cb_poll_contact(int* catA, int* catB, int* bodyA, int* bodyB);
