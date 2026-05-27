#pragma once
#include "Transform.hpp"

namespace sf {

// MARK: - Transformable
// position / origin / scale / rotation, exactly as SFML 2.6. getTransform()
// composes them (translate(pos) * rotate * scale * translate(-origin)); the web
// backend replays that as gfx_translate/rotate/scale around each draw.
class Transformable {
public:
    Transformable() = default;
    virtual ~Transformable() = default;

    void setPosition(float x, float y) { m_position = {x, y}; m_dirty = true; }
    void setPosition(const Vector2f& p) { m_position = p; m_dirty = true; }

    void setRotation(float angle) {
        m_rotation = std::fmod(angle, 360.f);
        if (m_rotation < 0.f) m_rotation += 360.f;
        m_dirty = true;
    }

    void setScale(float sx, float sy) { m_scale = {sx, sy}; m_dirty = true; }
    void setScale(const Vector2f& s) { m_scale = s; m_dirty = true; }

    void setOrigin(float x, float y) { m_origin = {x, y}; m_dirty = true; }
    void setOrigin(const Vector2f& o) { m_origin = o; m_dirty = true; }

    const Vector2f& getPosition() const { return m_position; }
    float getRotation() const { return m_rotation; }
    const Vector2f& getScale() const { return m_scale; }
    const Vector2f& getOrigin() const { return m_origin; }

    void move(float dx, float dy) { m_position.x += dx; m_position.y += dy; m_dirty = true; }
    void move(const Vector2f& off) { move(off.x, off.y); }
    void rotate(float angle) { setRotation(m_rotation + angle); }
    void scale(float fx, float fy) { m_scale.x *= fx; m_scale.y *= fy; m_dirty = true; }
    void scale(const Vector2f& f) { scale(f.x, f.y); }

    const Transform& getTransform() const {
        if (m_dirty) {
            Transform t;
            t.translate(m_position.x, m_position.y);
            t.rotate(m_rotation);
            t.scale(m_scale.x, m_scale.y);
            t.translate(-m_origin.x, -m_origin.y);
            m_transform = t;
            m_dirty = false;
        }
        return m_transform;
    }

private:
    Vector2f m_position{0.f, 0.f};
    Vector2f m_origin{0.f, 0.f};
    Vector2f m_scale{1.f, 1.f};
    float    m_rotation{0.f};
    mutable Transform m_transform;
    mutable bool      m_dirty{true};
};

}  // namespace sf
