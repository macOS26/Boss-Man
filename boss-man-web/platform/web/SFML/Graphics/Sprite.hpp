#pragma once
#include "../System.hpp"
#include "Color.hpp"
#include "Rect.hpp"
#include "Drawable.hpp"
#include "Transformable.hpp"
#include "Texture.hpp"
#include "RenderTarget.hpp"

namespace sf {

// MARK: - Sprite
// Textured quad. Draws via gfx_draw_image (src rect in image px -> unit-local dst
// rect), with the color used as tint+alpha. Origin/scale/rotation come from
// Transformable and are replayed as gfx transforms.
class Sprite : public Drawable, public Transformable {
public:
    Sprite() = default;
    explicit Sprite(const Texture& texture) { setTexture(texture, true); }
    Sprite(const Texture& texture, const IntRect& rectangle) {
        setTexture(texture, false);
        setTextureRect(rectangle);
    }

    void setTexture(const Texture& texture, bool resetRect = false) {
        m_texture = &texture;
        Vector2u sz = texture.getSize();
        if (resetRect || (m_rect.width == 0 && m_rect.height == 0))
            m_rect = IntRect(0, 0, (int)sz.x, (int)sz.y);
    }
    void setTextureRect(const IntRect& rect) { m_rect = rect; }
    void setColor(const Color& c) { m_color = c; }

    const Texture* getTexture() const { return m_texture; }
    const IntRect& getTextureRect() const { return m_rect; }
    const Color& getColor() const { return m_color; }

    FloatRect getLocalBounds() const {
        return FloatRect(0.f, 0.f, (float)std::abs(m_rect.width), (float)std::abs(m_rect.height));
    }
    FloatRect getGlobalBounds() const { return getTransform().transformRect(getLocalBounds()); }

protected:
    void draw(RenderTarget& target, RenderStates states) const override {
        if (!m_texture || m_texture->handle() == 0) return;
        target.beginDraw(states);
        RenderTarget::applyTransform(getTransform());
        gfx_draw_image(m_texture->handle(),
                       (float)m_rect.left, (float)m_rect.top,
                       (float)m_rect.width, (float)m_rect.height,
                       0.f, 0.f, (float)m_rect.width, (float)m_rect.height,
                       m_color.toInteger());
        target.endDraw();
    }

private:
    const Texture* m_texture{nullptr};
    IntRect        m_rect;
    Color          m_color{Color::White};
};

}  // namespace sf
