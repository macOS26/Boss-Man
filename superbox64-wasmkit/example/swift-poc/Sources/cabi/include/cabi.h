#pragma once
#include <stdint.h>
#define WABI __attribute__((import_module("env")))
WABI void js_log(const char* p, int len);
WABI void gfx_clear(uint32_t rgba);
WABI void gfx_fill_rect(float x, float y, float w, float h, uint32_t rgba);
WABI void gfx_fill_circle(float cx, float cy, float r, uint32_t rgba);

/* Box2D shim (defined in libcbox2d.a) */
void  cb_init(void);
void  cb_step(float dt);
float cb_box_y(void);
