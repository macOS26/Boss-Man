#pragma once
#include "../System.hpp"
#include "Rect.hpp"

namespace sf {

// MARK: - Transform
// 3x3 affine matrix stored column-major like SFML 2.6. On the web backend a
// Transform is realized by replaying its accumulated translate/scale/rotate as
// gfx_* state changes around a draw, but we also keep the matrix so the few call
// sites that compose transforms (and transformPoint) behave correctly.
class Transform {
public:
    Transform() {
        m[0] = 1.f; m[4] = 0.f; m[8]  = 0.f; m[12] = 0.f;
        m[1] = 0.f; m[5] = 1.f; m[9]  = 0.f; m[13] = 0.f;
        m[2] = 0.f; m[6] = 0.f; m[10] = 1.f; m[14] = 0.f;
        m[3] = 0.f; m[7] = 0.f; m[11] = 0.f; m[15] = 1.f;
    }
    Transform(float a00, float a01, float a02,
              float a10, float a11, float a12,
              float a20, float a21, float a22) {
        m[0] = a00; m[4] = a01; m[8]  = 0.f; m[12] = a02;
        m[1] = a10; m[5] = a11; m[9]  = 0.f; m[13] = a12;
        m[2] = 0.f; m[6] = 0.f; m[10] = 1.f; m[14] = 0.f;
        m[3] = a20; m[7] = a21; m[11] = 0.f; m[15] = a22;
    }

    const float* getMatrix() const { return m; }

    Transform getInverse() const {
        float det = m[0] * (m[15] * m[5] - m[7] * m[13])
                  - m[1] * (m[15] * m[4] - m[7] * m[12])
                  + m[3] * (m[13] * m[4] - m[5] * m[12]);
        if (det == 0.f) return Identity;
        float i = 1.f / det;
        return Transform(
            (m[15] * m[5] - m[7] * m[13]) * i,
            -(m[15] * m[4] - m[7] * m[12]) * i,
            (m[13] * m[4] - m[5] * m[12]) * i,
            -(m[15] * m[1] - m[3] * m[13]) * i,
            (m[15] * m[0] - m[3] * m[12]) * i,
            -(m[13] * m[0] - m[1] * m[12]) * i,
            (m[7] * m[1] - m[3] * m[5]) * i,
            -(m[7] * m[0] - m[3] * m[4]) * i,
            (m[5] * m[0] - m[1] * m[4]) * i);
    }

    Vector2f transformPoint(float x, float y) const {
        return Vector2f(m[0] * x + m[4] * y + m[12], m[1] * x + m[5] * y + m[13]);
    }
    Vector2f transformPoint(const Vector2f& p) const { return transformPoint(p.x, p.y); }

    FloatRect transformRect(const FloatRect& r) const {
        const Vector2f pts[4] = {
            transformPoint(r.left, r.top),
            transformPoint(r.left, r.top + r.height),
            transformPoint(r.left + r.width, r.top),
            transformPoint(r.left + r.width, r.top + r.height)};
        float minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y;
        for (int k = 1; k < 4; ++k) {
            minX = pts[k].x < minX ? pts[k].x : minX;
            maxX = pts[k].x > maxX ? pts[k].x : maxX;
            minY = pts[k].y < minY ? pts[k].y : minY;
            maxY = pts[k].y > maxY ? pts[k].y : maxY;
        }
        return FloatRect(minX, minY, maxX - minX, maxY - minY);
    }

    Transform& combine(const Transform& t) {
        const float* a = m;
        const float* b = t.m;
        *this = Transform(
            a[0] * b[0]  + a[4] * b[1]  + a[12] * b[3],
            a[0] * b[4]  + a[4] * b[5]  + a[12] * b[7],
            a[0] * b[12] + a[4] * b[13] + a[12] * b[15],
            a[1] * b[0]  + a[5] * b[1]  + a[13] * b[3],
            a[1] * b[4]  + a[5] * b[5]  + a[13] * b[7],
            a[1] * b[12] + a[5] * b[13] + a[13] * b[15],
            a[3] * b[0]  + a[7] * b[1]  + a[15] * b[3],
            a[3] * b[4]  + a[7] * b[5]  + a[15] * b[7],
            a[3] * b[12] + a[7] * b[13] + a[15] * b[15]);
        return *this;
    }

    Transform& translate(float x, float y) {
        Transform t(1, 0, x, 0, 1, y, 0, 0, 1);
        return combine(t);
    }
    Transform& translate(const Vector2f& o) { return translate(o.x, o.y); }

    Transform& rotate(float angle) {
        float rad = angle * 3.14159265f / 180.f;
        float c = std::cos(rad), s = std::sin(rad);
        Transform t(c, -s, 0, s, c, 0, 0, 0, 1);
        return combine(t);
    }
    Transform& rotate(float angle, float cx, float cy) {
        float rad = angle * 3.14159265f / 180.f;
        float c = std::cos(rad), s = std::sin(rad);
        Transform t(c, -s, cx * (1 - c) + cy * s,
                    s, c, cy * (1 - c) - cx * s,
                    0, 0, 1);
        return combine(t);
    }
    Transform& rotate(float angle, const Vector2f& c) { return rotate(angle, c.x, c.y); }

    Transform& scale(float sx, float sy) {
        Transform t(sx, 0, 0, 0, sy, 0, 0, 0, 1);
        return combine(t);
    }
    Transform& scale(float sx, float sy, float cx, float cy) {
        Transform t(sx, 0, cx * (1 - sx),
                    0, sy, cy * (1 - sy),
                    0, 0, 1);
        return combine(t);
    }
    Transform& scale(const Vector2f& f) { return scale(f.x, f.y); }
    Transform& scale(const Vector2f& f, const Vector2f& c) { return scale(f.x, f.y, c.x, c.y); }

    static const Transform Identity;

    float m[16];
};

inline Transform operator*(const Transform& a, const Transform& b) {
    Transform r = a;
    return r.combine(b);
}
inline Transform& operator*=(Transform& a, const Transform& b) { return a.combine(b); }
inline Vector2f operator*(const Transform& a, const Vector2f& p) { return a.transformPoint(p); }

}  // namespace sf
