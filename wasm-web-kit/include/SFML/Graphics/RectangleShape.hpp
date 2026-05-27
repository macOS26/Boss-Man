#pragma once
#include "Shape.hpp"

namespace sf {

// MARK: - RectangleShape
class RectangleShape : public Shape {
public:
    explicit RectangleShape(const Vector2f& size = Vector2f(0, 0)) : m_size(size) {}

    void setSize(const Vector2f& size) { m_size = size; }
    const Vector2f& getSize() const { return m_size; }

    std::size_t getPointCount() const override { return 4; }
    Vector2f getPoint(std::size_t index) const override {
        switch (index) {
        default:
        case 0: return {0.f, 0.f};
        case 1: return {m_size.x, 0.f};
        case 2: return {m_size.x, m_size.y};
        case 3: return {0.f, m_size.y};
        }
    }

protected:
    void draw(RenderTarget& target, RenderStates states) const override {
        target.beginDraw(states);
        RenderTarget::applyTransform(getTransform());
        if (m_fill.a > 0)
            gfx_fill_rect(0.f, 0.f, m_size.x, m_size.y, m_fill.toInteger());
        if (m_thickness != 0.f && m_outline.a > 0)
            gfx_stroke_rect(0.f, 0.f, m_size.x, m_size.y, m_thickness, m_outline.toInteger());
        target.endDraw();
    }

private:
    Vector2f m_size;
};

}  // namespace sf
