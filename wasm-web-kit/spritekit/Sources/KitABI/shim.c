/* C wrappers around libm so Swift can call them through KitABI without
 * the Swift-mangled witness arguments confusing wasm-ld. Swift's @_silgen_name
 * on a top-level free function still adds two i32 self/witness args; declaring
 * these here as plain C functions and importing them via the KitABI module
 * lets Swift call them with the right (Double)->Double signature. */
#include <math.h>

double sb64_sin(double x)            { return sin(x); }
double sb64_cos(double x)            { return cos(x); }
double sb64_atan2(double y, double x){ return atan2(y, x); }
double sb64_sqrt(double x)           { return sqrt(x); }
double sb64_floor(double x)          { return floor(x); }
double sb64_ceil(double x)           { return ceil(x); }
double sb64_fmod(double a, double b) { return fmod(a, b); }
double sb64_pow(double a, double b)  { return pow(a, b); }
double sb64_hypot(double x, double y){ return hypot(x, y); }
