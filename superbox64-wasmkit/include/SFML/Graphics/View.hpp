#pragma once
#include "../System.hpp"
#include "Rect.hpp"

namespace sf {

// MARK: - View
// On the web the canvas backing store IS the logical surface and JS delivers mouse
// coords already in logical pixels, so the View does not affect drawing or
// coordinate mapping. We still store center/size/viewport faithfully so the game's
// letterbox bookkeeping reads back the values it set.
class View {
public:
    View() : m_center(0.f, 0.f), m_size(1000.f, 1000.f) {}
    explicit View(const FloatRect& rect)
        : m_center(rect.left + rect.width / 2.f, rect.top + rect.height / 2.f),
          m_size(rect.width, rect.height) {}
    View(const Vector2f& center, const Vector2f& size) : m_center(center), m_size(size) {}

    void setCenter(float x, float y) { m_center = {x, y}; }
    void setCenter(const Vector2f& c) { m_center = c; }
    void setSize(float w, float h) { m_size = {w, h}; }
    void setSize(const Vector2f& s) { m_size = s; }
    void setRotation(float angle) { m_rotation = angle; }
    void setViewport(const FloatRect& vp) { m_viewport = vp; }
    void reset(const FloatRect& rect) {
        m_center = {rect.left + rect.width / 2.f, rect.top + rect.height / 2.f};
        m_size = {rect.width, rect.height};
        m_rotation = 0.f;
    }

    const Vector2f& getCenter() const { return m_center; }
    const Vector2f& getSize() const { return m_size; }
    float getRotation() const { return m_rotation; }
    const FloatRect& getViewport() const { return m_viewport; }

    void move(float dx, float dy) { m_center.x += dx; m_center.y += dy; }
    void move(const Vector2f& o) { move(o.x, o.y); }
    void zoom(float factor) { m_size.x *= factor; m_size.y *= factor; }

private:
    Vector2f  m_center;
    Vector2f  m_size;
    float     m_rotation{0.f};
    FloatRect m_viewport{0.f, 0.f, 1.f, 1.f};
};

}  // namespace sf
