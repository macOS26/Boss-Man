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
WABI void gfx_set_text_baseline(int mode);
WABI int  img_by_name(const char* name, int len);
WABI int  img_width(int img);
WABI int  img_height(int img);
WABI int  snd_by_name(const char* name, int len);
WABI int  snd_create_pcm(const float* samples, int frameCount, int sampleRate);
WABI int  font_by_name(const char* name, int len);   /* 0 = default monospace */
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
WABI void  tts_set_preferred_voices(const char* csv, int len);
WABI void  tts_set_robotic_voices(const char* csv, int len);
WABI void  tts_set_female_voices(const char* csv, int len);

/* offscreen canvas (SKView.texture(from:), SKCropNode, SKEffectNode) */
/* gfx_offscreen_begin: switch all subsequent gfx_* calls to an offscreen */
/* canvas of (w,h) at devicePixelRatio. Returns a handle the caller passes */
/* to gfx_offscreen_end to either commit (returns img handle) or discard. */
WABI int   gfx_offscreen_begin(int w, int h);
WABI int   gfx_offscreen_end_to_image(int handle);   /* returns img handle */
WABI void  gfx_offscreen_end_discard(int handle);

/* Canvas2D filter string (CSS filter syntax: 'blur(8px) saturate(150%)'). */
/* gfx_set_filter applies to all subsequent draws until gfx_clear_filter. */
WABI void  gfx_set_filter(const char* utf8, int len);
WABI void  gfx_clear_filter(void);

/* Canvas2D shadowBlur primitive — gives a real Gaussian drop shadow for any
 * subsequent draw call (fillRect, drawImage, etc.). dx/dy are in canvas
 * (y-down) pixels, applied after the active transform. blurRadius > 0
 * activates the shadow; gfx_clear_shadow() resets shadowBlur + shadowColor. */
WABI void  gfx_set_shadow(float blurRadius, float dx, float dy, uint32_t rgba);
WABI void  gfx_clear_shadow(void);

/* Composite mode: 0=source-over (default), 1=destination-in, 2=destination-out, */
/* 3=lighter, 4=multiply, 5=screen, 6=overlay. */
WABI void  gfx_set_composite(int mode);

/* DOM video element (SKVideoNode). vid_load registers the source by name */
/* (resolved through the asset table), vid_play / vid_pause control playback, */
/* vid_set_rect positions/sizes the element in logical pixels (y-down). */
WABI int   vid_load(const char* name, int len);
WABI void  vid_play(int id);
WABI void  vid_pause(int id);
WABI void  vid_stop(int id);
WABI void  vid_set_rect(int id, float x, float y, float w, float h);
WABI void  vid_set_visible(int id, int visible);

/* Sound positional / playback rate (per-voice) */
WABI void  snd_set_pan(int voice, float pan);   /* -1 = left, +1 = right */
WABI void  snd_set_rate(int voice, float rate); /* 1.0 = normal speed */

/* AVAudioEngine — Web Audio graph behind the Swift shim.                  */
/* eng_player_create returns a player node id; connect chains arbitrary    */
/* engine nodes (player → mixer → output). schedule_buffer plays a sample. */
WABI int   eng_player_create(void);
WABI void  eng_player_release(int id);
WABI int   eng_mixer_create(void);
WABI void  eng_node_set_volume(int id, float v);
WABI void  eng_node_set_pan(int id, float p);
WABI void  eng_connect(int src, int dst);     /* dst = -1 means destination */
WABI int   eng_player_schedule_buffer(int player, int sound, int loops);
WABI void  eng_player_play(int id);
WABI void  eng_player_stop(int id);
WABI void  eng_start(void);
WABI void  eng_stop(void);

/* WebGL2 shader pipeline (SKShader, SKLightNode, SKWarpGeometry, SK3DNode). */
/* The runtime hosts a hidden WebGL2 canvas. gfx_shader_compile returns a    */
/* program id; uniforms are pushed by name with the typed setters; apply     */
/* renders the source image through the shader into an offscreen and blits   */
/* the result onto the current Canvas2D target at (dstX,dstY,dstW,dstH).     */
/* SpriteKit's standard preamble (u_time, v_tex_coord, v_color_mix,          */
/* SKDefaultShading, #define texture2D=texture) is injected automatically.   */
WABI int   gfx_shader_compile(const char* src, int len);
WABI void  gfx_shader_release(int shader);
WABI void  gfx_shader_set_uniform_f (int shader, const char* name, int nlen, float v);
WABI void  gfx_shader_set_uniform_v2(int shader, const char* name, int nlen, float x, float y);
WABI void  gfx_shader_set_uniform_v3(int shader, const char* name, int nlen, float x, float y, float z);
WABI void  gfx_shader_set_uniform_v4(int shader, const char* name, int nlen, float x, float y, float z, float w);
WABI void  gfx_shader_set_uniform_t (int shader, const char* name, int nlen, int img);
/* Draw the source image through the shader onto the current 2D target.    */
/* time is seconds (passed to u_time); colorRgba is the per-call tint mix. */
WABI void  gfx_shader_draw(int shader, int srcImg, float dstX, float dstY,
                           float dstW, float dstH, float time, uint32_t colorRgba);

/* Built-in lighting pass — SKLightNode. lights is a flat array of 8 floats */
/* per light (x, y, ambientRgbaPacked-as-float-bits, lightRgbaPacked,       */
/* falloff, intensity, _, _) and `lightCount` says how many to read.       */
/* normalImg is the SKSpriteNode.normalTexture (0 = no normal map).        */
WABI void  gfx_lighting_draw(int srcImg, int normalImg,
                             const float* lights, int lightCount,
                             float dstX, float dstY, float dstW, float dstH,
                             uint32_t colorRgba);

/* SKWarpGeometryGrid mesh warp. The grid is (cols+1) * (rows+1) vertices  */
/* of normalized source UVs (0..1) and destination positions in the dest   */
/* rectangle (0..1 normalized; runtime scales to dst*).                    */
WABI void  gfx_warp_draw(int srcImg, int cols, int rows,
                         const float* srcUV, const float* dstXY,
                         float dstX, float dstY, float dstW, float dstH,
                         uint32_t colorRgba);

/* SK3DNode viewport: srcImg becomes a billboarded textured quad rendered  */
/* through a perspective camera at (camX, camY, camZ) looking at origin.   */
/* Result blits onto the current 2D target at (dstX,dstY,dstW,dstH).       */
WABI void  gfx_3d_draw_billboard(int srcImg, float camX, float camY, float camZ,
                                 float dstX, float dstY, float dstW, float dstH,
                                 uint32_t colorRgba);

/* SKMutableTexture push: upload an RGBA8 pixel buffer to an image asset.  */
/* w*h*4 bytes expected. Resizes/recreates the backing canvas if needed.   */
/* When `img` is 0, allocates a new image asset and returns its handle;    */
/* otherwise updates `img` in place and returns the same handle.           */
WABI int   gfx_upload_pixels(int img, int w, int h, const uint8_t* rgba, int len);

/* localStorage-backed persistence. store_get returns -1 when the key is   */
/* absent; otherwise returns the value's total byte length (copies up to   */
/* `cap` bytes into buf).                                                  */
WABI int   store_get(const char* key, int klen, char* buf, int cap);
WABI void  store_set(const char* key, int klen, const char* val, int vlen);

/* Asset text reads (e.g. *.json compiled from .sks).                       */
WABI int   asset_exists(const char* name, int len);
WABI int   asset_text(const char* name, int len, char* buf, int cap);

/* Pixel-perfect physics polygon from a texture's alpha channel.            */
/* Runtime reads canvas getImageData, runs marching squares + RDP simplify, */
/* writes up to `cap` xy pairs into out_xy. Returns the actual point count. */
WABI int   img_polygon_from_alpha(int img, float alphaThreshold,
                                  float* out_xy, int cap);

/* input */
WABI int  key_pressed(int sfKey);
WABI int  mouse_x(void);
WABI int  mouse_y(void);
WABI int  mouse_button(int b);
WABI int  evt_poll(int* type, int* a, int* b, int* c, int* d);
WABI int  win_width(void);
WABI int  win_height(void);
WABI void win_set_title(const char* s, int len);
WABI void win_request_fullscreen(void);
WABI void win_exit_fullscreen(void);

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
int    sb64_rand(void);
void   sb64_srand(unsigned int seed);

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
void  cb_remove_body(int body);
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
