#pragma once
#include "../System.hpp"
#include "Color.hpp"
#include "Drawable.hpp"
#include "RenderStates.hpp"
#include "View.hpp"

namespace sf {

// MARK: - RenderTarget
// Base draw surface. Holds a target handle (0 = screen, >0 = render texture). The
// concrete drawables emit gfx_* primitives; RenderTarget just selects the target,
// pushes the states' transform/blend, forwards to the drawable, and restores.
class RenderTarget {
public:
    virtual ~RenderTarget() = default;

    void clear(const Color& color = Color(0, 0, 0, 255)) {
        gfx_target(m_target);
        gfx_clear(color.toInteger());
    }

    void draw(const Drawable& drawable, const RenderStates& states = RenderStates()) {
        drawable.draw(*this, states);
    }

    void setView(const View& view) { m_view = view; }
    const View& getView() const { return m_view; }
    const View& getDefaultView() const { return m_defaultView; }

    virtual Vector2u getSize() const = 0;

    // MARK: - coordinate mapping
    // The canvas backing store is the logical surface and JS delivers mouse coords
    // already in logical pixels, so pixel<->coord mapping is identity (the View is
    // bookkeeping only on web).
    Vector2f mapPixelToCoords(const Vector2i& point) const {
        return Vector2f((float)point.x, (float)point.y);
    }
    Vector2f mapPixelToCoords(const Vector2i& point, const View&) const {
        return Vector2f((float)point.x, (float)point.y);
    }
    Vector2i mapCoordsToPixel(const Vector2f& point) const {
        return Vector2i((int)point.x, (int)point.y);
    }
    Vector2i mapCoordsToPixel(const Vector2f& point, const View&) const {
        return Vector2i((int)point.x, (int)point.y);
    }

    // MARK: - backend helpers (used by drawables)
    int gfxTarget() const { return m_target; }

    // Selects this target and pushes a save scope carrying the states' transform
    // and blend mode. Drawables call beginDraw()/endDraw() around their primitives.
    void beginDraw(const RenderStates& states) const {
        gfx_target(m_target);
        gfx_save();
        applyTransform(states.transform);
        gfx_set_blend(webBlendCode(states.blendMode));
    }
    void endDraw() const { gfx_restore(); }

    // Replays an affine Transform as gfx_translate/rotate/scale. Decomposes the
    // 2x2 linear part into rotation + scale (no shear is produced by Transformable
    // or the game's transforms).
    static void applyTransform(const Transform& t) {
        const float* m = t.getMatrix();
        float tx = m[12], ty = m[13];
        float a = m[0], b = m[1], c = m[4], d = m[5];
        gfx_translate(tx, ty);
        float sx = std::sqrt(a * a + b * b);
        float det = a * d - b * c;
        float sy = (sx != 0.f) ? det / sx : std::sqrt(c * c + d * d);
        float rot = std::atan2(b, a) * 180.f / 3.14159265f;
        if (rot != 0.f) gfx_rotate(rot);
        float fsx = (sx == 0.f) ? 1.f : sx;
        float fsy = (sy == 0.f) ? 1.f : sy;
        if (fsx != 1.f || fsy != 1.f) gfx_scale(fsx, fsy);
    }

protected:
    int  m_target{0};
    View m_view;
    View m_defaultView;
};

}  // namespace sf
