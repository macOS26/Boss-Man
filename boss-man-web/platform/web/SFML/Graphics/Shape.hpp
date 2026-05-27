#pragma once
#include "../System.hpp"
#include "Color.hpp"
#include "Rect.hpp"
#include "Drawable.hpp"
#include "Transformable.hpp"
#include "RenderStates.hpp"
#include "Texture.hpp"
#include "RenderTarget.hpp"
#include <vector>
#include <cstddef>

namespace sf {

// MARK: - Shape
// Abstract point-based shape (SFML 2.6). Subclasses provide getPointCount/getPoint;
// the base supplies fill/outline color, outline thickness, bounds, and draw(). The
// web backend rasterizes the polygon via gfx_fill_poly. Outline (no poly-stroke in
// the ABI) is emulated by filling an outward-expanded polygon behind the fill.
class Shape : public Drawable, public Transformable {
public:
    virtual ~Shape() = default;

    virtual std::size_t getPointCount() const = 0;
    virtual Vector2f getPoint(std::size_t index) const = 0;

    void setFillColor(const Color& c) { m_fill = c; }
    void setOutlineColor(const Color& c) { m_outline = c; }
    void setOutlineThickness(float t) { m_thickness = t; }
    void setTexture(const Texture* t, bool = false) { m_texture = t; }
    void setTextureRect(const IntRect& r) { m_textureRect = r; }

    const Color& getFillColor() const { return m_fill; }
    const Color& getOutlineColor() const { return m_outline; }
    float getOutlineThickness() const { return m_thickness; }

    FloatRect getLocalBounds() const {
        std::size_t n = getPointCount();
        if (n == 0) return FloatRect();
        Vector2f p0 = getPoint(0);
        float minX = p0.x, maxX = p0.x, minY = p0.y, maxY = p0.y;
        for (std::size_t i = 1; i < n; ++i) {
            Vector2f p = getPoint(i);
            minX = p.x < minX ? p.x : minX;
            maxX = p.x > maxX ? p.x : maxX;
            minY = p.y < minY ? p.y : minY;
            maxY = p.y > maxY ? p.y : maxY;
        }
        float t = m_thickness > 0.f ? m_thickness : 0.f;
        return FloatRect(minX - t, minY - t, (maxX - minX) + 2 * t, (maxY - minY) + 2 * t);
    }

    FloatRect getGlobalBounds() const { return getTransform().transformRect(getLocalBounds()); }

protected:
    void update() {}

    void draw(RenderTarget& target, RenderStates states) const override {
        std::size_t n = getPointCount();
        if (n < 2) return;
        target.beginDraw(states);
        RenderTarget::applyTransform(getTransform());

        std::vector<float> xy;
        xy.reserve(n * 2);
        float cx = 0.f, cy = 0.f;
        for (std::size_t i = 0; i < n; ++i) {
            Vector2f p = getPoint(i);
            xy.push_back(p.x); xy.push_back(p.y);
            cx += p.x; cy += p.y;
        }
        cx /= (float)n; cy /= (float)n;

        if (m_thickness > 0.f && m_outline.a > 0) {
            std::vector<float> outl;
            outl.reserve(n * 2);
            for (std::size_t i = 0; i < n; ++i) {
                float dx = xy[i * 2] - cx, dy = xy[i * 2 + 1] - cy;
                float len = std::sqrt(dx * dx + dy * dy);
                float s = (len > 0.f) ? (len + m_thickness) / len : 1.f;
                outl.push_back(cx + dx * s);
                outl.push_back(cy + dy * s);
            }
            gfx_fill_poly(outl.data(), (int)n, m_outline.toInteger());
        }

        gfx_fill_poly(xy.data(), (int)n, m_fill.toInteger());
        target.endDraw();
    }

    Color    m_fill{Color::White};
    Color    m_outline{Color(0, 0, 0)};
    float    m_thickness{0.f};
    const Texture* m_texture{nullptr};
    IntRect  m_textureRect;
};

}  // namespace sf
