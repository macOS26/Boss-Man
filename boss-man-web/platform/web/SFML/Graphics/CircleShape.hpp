#pragma once
#include "Shape.hpp"

namespace sf {

// MARK: - CircleShape
class CircleShape : public Shape {
public:
    explicit CircleShape(float radius = 0.f, std::size_t pointCount = 30)
        : m_radius(radius), m_pointCount(pointCount) {}

    void setRadius(float radius) { m_radius = radius; }
    float getRadius() const { return m_radius; }
    void setPointCount(std::size_t count) { m_pointCount = count; }
    std::size_t getPointCount() const override { return m_pointCount; }

    Vector2f getPoint(std::size_t index) const override {
        static const float kPi = 3.141592654f;
        float angle = (float)index * 2.f * kPi / (float)m_pointCount - kPi / 2.f;
        return {m_radius + m_radius * std::cos(angle), m_radius + m_radius * std::sin(angle)};
    }

protected:
    void draw(RenderTarget& target, RenderStates states) const override {
        target.beginDraw(states);
        RenderTarget::applyTransform(getTransform());
        if (m_thickness > 0.f && m_outline.a > 0)
            gfx_fill_circle(m_radius, m_radius, m_radius + m_thickness, m_outline.toInteger());
        gfx_fill_circle(m_radius, m_radius, m_radius, m_fill.toInteger());
        target.endDraw();
    }

private:
    float       m_radius;
    std::size_t m_pointCount;
};

}  // namespace sf
