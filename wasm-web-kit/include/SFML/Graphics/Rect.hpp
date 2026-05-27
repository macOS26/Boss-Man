#pragma once
#include "../System.hpp"
#include <algorithm>

namespace sf {

template <typename T>
class Rect {
public:
    T left{}, top{}, width{}, height{};
    Rect() = default;
    Rect(T l, T t, T w, T h) : left(l), top(t), width(w), height(h) {}
    Rect(const Vector2<T>& pos, const Vector2<T>& size)
        : left(pos.x), top(pos.y), width(size.x), height(size.y) {}
    template <typename U> explicit Rect(const Rect<U>& r)
        : left(static_cast<T>(r.left)), top(static_cast<T>(r.top)),
          width(static_cast<T>(r.width)), height(static_cast<T>(r.height)) {}

    bool contains(T x, T y) const {
        T minX = std::min(left, static_cast<T>(left + width));
        T maxX = std::max(left, static_cast<T>(left + width));
        T minY = std::min(top, static_cast<T>(top + height));
        T maxY = std::max(top, static_cast<T>(top + height));
        return (x >= minX) && (x < maxX) && (y >= minY) && (y < maxY);
    }
    bool contains(const Vector2<T>& p) const { return contains(p.x, p.y); }

    bool intersects(const Rect<T>& r) const {
        T r1MinX = std::min(left, static_cast<T>(left + width));
        T r1MaxX = std::max(left, static_cast<T>(left + width));
        T r1MinY = std::min(top, static_cast<T>(top + height));
        T r1MaxY = std::max(top, static_cast<T>(top + height));
        T r2MinX = std::min(r.left, static_cast<T>(r.left + r.width));
        T r2MaxX = std::max(r.left, static_cast<T>(r.left + r.width));
        T r2MinY = std::min(r.top, static_cast<T>(r.top + r.height));
        T r2MaxY = std::max(r.top, static_cast<T>(r.top + r.height));
        return std::max(r1MinX, r2MinX) < std::min(r1MaxX, r2MaxX)
            && std::max(r1MinY, r2MinY) < std::min(r1MaxY, r2MaxY);
    }

    bool operator==(const Rect<T>& o) const {
        return left == o.left && top == o.top && width == o.width && height == o.height;
    }
};

using FloatRect = Rect<float>;
using IntRect   = Rect<int>;

}  // namespace sf
