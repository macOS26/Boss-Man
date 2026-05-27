#pragma once
#include "../System.hpp"

namespace sf {

class Color {
public:
    Uint8 r{0}, g{0}, b{0}, a{255};
    Color() = default;
    Color(Uint8 r_, Uint8 g_, Uint8 b_, Uint8 a_ = 255) : r(r_), g(g_), b(b_), a(a_) {}
    explicit Color(Uint32 rgba) : r((rgba >> 24) & 0xFF), g((rgba >> 16) & 0xFF),
                                  b((rgba >> 8) & 0xFF), a(rgba & 0xFF) {}
    Uint32 toInteger() const { return (Uint32(r) << 24) | (Uint32(g) << 16) | (Uint32(b) << 8) | Uint32(a); }

    static const Color Black;
    static const Color White;
    static const Color Red;
    static const Color Green;
    static const Color Blue;
    static const Color Yellow;
    static const Color Magenta;
    static const Color Cyan;
    static const Color Transparent;

    bool operator==(const Color& o) const { return r == o.r && g == o.g && b == o.b && a == o.a; }
    bool operator!=(const Color& o) const { return !(*this == o); }
};

}  // namespace sf
