#pragma once
#include "Shape.hpp"

namespace sf {

// MARK: - ConvexShape
// Point-based convex polygon (SFML 2.6). Points are explicitly supplied via
// setPoint; the Shape base handles fill, outline emulation, bounds, and draw().
class ConvexShape : public Shape {
public:
    explicit ConvexShape(std::size_t pointCount = 0) { setPointCount(pointCount); }

    void setPointCount(std::size_t count) { m_points.resize(count); }
    std::size_t getPointCount() const override { return m_points.size(); }

    void setPoint(std::size_t index, const Vector2f& point) { m_points[index] = point; }
    Vector2f getPoint(std::size_t index) const override { return m_points[index]; }

private:
    std::vector<Vector2f> m_points;
};

}  // namespace sf
