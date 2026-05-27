// Our own minimal sf:: System layer for the web (wasm) build. Mirrors the SFML
// 2.6 API surface the game uses. Native builds use real SFML; this header is on
// the include path only for the wasm target.
#pragma once
#include <cstdint>
#include <cmath>
#include <string>
#include "../abi.h"

namespace sf {

using Int8   = int8_t;   using Uint8  = uint8_t;
using Int16  = int16_t;  using Uint16 = uint16_t;
using Int32  = int32_t;  using Uint32 = uint32_t;
using Int64  = int64_t;  using Uint64 = uint64_t;

// ---- Vector2 ----
template <typename T>
class Vector2 {
public:
    T x{}, y{};
    Vector2() = default;
    Vector2(T x_, T y_) : x(x_), y(y_) {}
    template <typename U> explicit Vector2(const Vector2<U>& v)
        : x(static_cast<T>(v.x)), y(static_cast<T>(v.y)) {}
};
template <typename T> Vector2<T> operator-(const Vector2<T>& r) { return {-r.x, -r.y}; }
template <typename T> Vector2<T> operator+(const Vector2<T>& a, const Vector2<T>& b) { return {a.x + b.x, a.y + b.y}; }
template <typename T> Vector2<T> operator-(const Vector2<T>& a, const Vector2<T>& b) { return {a.x - b.x, a.y - b.y}; }
template <typename T> Vector2<T> operator*(const Vector2<T>& a, T s) { return {a.x * s, a.y * s}; }
template <typename T> Vector2<T> operator*(T s, const Vector2<T>& a) { return {a.x * s, a.y * s}; }
template <typename T> Vector2<T> operator/(const Vector2<T>& a, T s) { return {a.x / s, a.y / s}; }
template <typename T> Vector2<T>& operator+=(Vector2<T>& a, const Vector2<T>& b) { a.x += b.x; a.y += b.y; return a; }
template <typename T> Vector2<T>& operator-=(Vector2<T>& a, const Vector2<T>& b) { a.x -= b.x; a.y -= b.y; return a; }
template <typename T> Vector2<T>& operator*=(Vector2<T>& a, T s) { a.x *= s; a.y *= s; return a; }
template <typename T> bool operator==(const Vector2<T>& a, const Vector2<T>& b) { return a.x == b.x && a.y == b.y; }
template <typename T> bool operator!=(const Vector2<T>& a, const Vector2<T>& b) { return !(a == b); }

using Vector2f = Vector2<float>;
using Vector2i = Vector2<int>;
using Vector2u = Vector2<unsigned int>;

// ---- Time / Clock ----
class Time {
public:
    Time() = default;
    float asSeconds() const { return m_us / 1000000.f; }
    Int32 asMilliseconds() const { return static_cast<Int32>(m_us / 1000); }
    Int64 asMicroseconds() const { return m_us; }
    static const Time Zero;
    bool operator>(const Time& t) const { return m_us > t.m_us; }
    bool operator<(const Time& t) const { return m_us < t.m_us; }
    bool operator>=(const Time& t) const { return m_us >= t.m_us; }
    bool operator<=(const Time& t) const { return m_us <= t.m_us; }
    Time& operator+=(const Time& t) { m_us += t.m_us; return *this; }
    Time& operator-=(const Time& t) { m_us -= t.m_us; return *this; }
    friend Time seconds(float);
    friend Time milliseconds(Int32);
    friend Time microseconds(Int64);
private:
    explicit Time(Int64 us) : m_us(us) {}
    Int64 m_us{0};
};
inline Time seconds(float s)        { return Time(static_cast<Int64>(s * 1000000.f)); }
inline Time milliseconds(Int32 ms)  { return Time(static_cast<Int64>(ms) * 1000); }
inline Time microseconds(Int64 us)  { return Time(us); }
inline Time operator-(const Time& a, const Time& b) { return microseconds(a.asMicroseconds() - b.asMicroseconds()); }
inline Time operator+(const Time& a, const Time& b) { return microseconds(a.asMicroseconds() + b.asMicroseconds()); }

// JS owns the wall clock; we read it through a tiny helper exposed by the audio
// timeline. To avoid an extra import, derive elapsed from performance.now via a
// dedicated import would be ideal; instead Clock is driven by the frame loop,
// which sets the current time. For the game's purposes (dt + animation phase),
// monotonically increasing microseconds are enough.
namespace detail { inline Int64& nowUs() { static Int64 t = 0; return t; } }

class Clock {
public:
    Clock() : m_start(detail::nowUs()) {}
    Time getElapsedTime() const { return microseconds(detail::nowUs() - m_start); }
    Time restart() { Int64 n = detail::nowUs(); Time e = microseconds(n - m_start); m_start = n; return e; }
private:
    Int64 m_start{0};
};

inline void sleep(Time) {}  // no-op in the browser (RAF paces frames)

}  // namespace sf
