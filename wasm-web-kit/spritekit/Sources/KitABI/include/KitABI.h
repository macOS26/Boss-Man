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
WABI void snd_stop(int voice);
WABI void snd_set_volume(int voice, float volume);
WABI int  snd_status(int voice);
WABI void snd_pause_all(void);
WABI void snd_resume_all(void);

/* gamepad / USB arcade joystick (Web Gamepad API, 4 pads) */
WABI int   gp_connected(int pad);
WABI int   gp_button(int pad, int button);
WABI float gp_button_value(int pad, int button);
WABI float gp_axis(int pad, int axis);
WABI void  gp_map_to_keys(int enable);

/* text-to-speech (Web Speech API) */
WABI int   tts_speak(const char* utf8, int len, float rate, float pitch, float volume);
WABI void  tts_cancel(void);

/* input */
WABI int  key_pressed(int sfKey);
WABI int  mouse_x(void);
WABI int  mouse_y(void);
WABI int  mouse_button(int b);
WABI int  evt_poll(int* type, int* a, int* b, int* c, int* d);
WABI int  win_width(void);
WABI int  win_height(void);

/* libm wrappers — see shim.c. Swift uses these instead of importing libm
 * directly because @_silgen_name passes through Swift's witness mangling
 * and produces a signature mismatch with libc's (Double)->Double. */
double sb64_sin(double x);
double sb64_cos(double x);
double sb64_atan2(double y, double x);
double sb64_sqrt(double x);
double sb64_floor(double x);
double sb64_ceil(double x);
double sb64_fmod(double a, double b);
double sb64_pow(double a, double b);
double sb64_hypot(double x, double y);

/* Box2D shim (defined in Box2DBridge target; see Sources/Box2DBridge/cbox2d.cpp) */
void  cb_reset(float gx, float gy);
int   cb_add_box(float x, float y, float hw, float hh, int dynamic, uint16_t cat, uint16_t mask, int sensor);
int   cb_add_circle(float x, float y, float r, int dynamic, uint16_t cat, uint16_t mask, int sensor);
int   cb_add_polygon(float x, float y, const float* xy, int count, int dynamic, uint16_t cat, uint16_t mask, int sensor);
int   cb_add_edge(float x1, float y1, float x2, float y2, uint16_t cat, uint16_t mask);
int   cb_add_chain(const float* xy, int count, int closed, uint16_t cat, uint16_t mask);
void  cb_set_velocity(int body, float vx, float vy);
void  cb_set_angular_velocity(int body, float w);
float cb_get_angular_velocity(int body);
void  cb_set_transform(int body, float x, float y, float angle);
void  cb_get_position(int body, float* x, float* y);
float cb_get_angle(int body);
void  cb_apply_force(int body, float fx, float fy);
void  cb_apply_impulse(int body, float ix, float iy);
void  cb_apply_torque(int body, float t);
void  cb_apply_angular_impulse(int body, float i);
int   cb_add_joint_pin(int a, int b, float ax, float ay, int enableLimits,
                       float lower, float upper, float frictionTorque, float motorSpeed);
int   cb_add_joint_spring(int a, int b, float ax, float ay, float bx, float by,
                          float frequency, float damping);
int   cb_add_joint_sliding(int a, int b, float ax, float ay, float dx, float dy,
                           int enableLimits, float lower, float upper);
int   cb_add_joint_limit(int a, int b, float ax, float ay, float bx, float by, float maxLength);
int   cb_add_joint_fixed(int a, int b, float ax, float ay);
int   cb_add_joint_distance(int a, int b, float ax, float ay, float bx, float by);
void  cb_remove_joint(int id);
void  cb_step(float dt);
int   cb_poll_contact(int* catA, int* catB, int* bodyA, int* bodyB);
