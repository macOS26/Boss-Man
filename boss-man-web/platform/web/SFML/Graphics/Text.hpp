#pragma once
#include "../System.hpp"
#include "../System/String.hpp"
#include "Color.hpp"
#include "Rect.hpp"
#include "Drawable.hpp"
#include "Transformable.hpp"
#include "Font.hpp"
#include "RenderTarget.hpp"
#include <string>

namespace sf {

// MARK: - Text
// Drawn by Canvas2D fillText through gfx_draw_text; width is measured with
// txt_width. localBounds is modeled as a (0,0,width,characterSize) box: the
// game anchors labels on that box (origin = box bottom-center) and the runtime
// draws the string's top-left at the local (0,0) the transform resolves to.
class Text : public Drawable, public Transformable {
public:
    enum Style {
        Regular       = 0,
        Bold          = 1 << 0,
        Italic        = 1 << 1,
        Underlined    = 1 << 2,
        StrikeThrough = 1 << 3
    };

    Text() = default;
    Text(const String& string, const Font& font, unsigned characterSize = 30)
        : m_string(string.bytes()), m_font(&font), m_size(characterSize) {}

    void setString(const String& s) { m_string = s.bytes(); }
    void setString(const std::string& s) { m_string = s; }
    void setFont(const Font& f) { m_font = &f; }
    void setCharacterSize(unsigned size) { m_size = size; }
    void setFillColor(const Color& c) { m_fill = c; }
    void setColor(const Color& c) { m_fill = c; }
    void setOutlineColor(const Color& c) { m_outline = c; }
    void setOutlineThickness(float t) { m_outlineThickness = t; }
    void setLetterSpacing(float f) { m_letterSpacing = f; }
    void setStyle(Uint32 style) { m_style = style; }

    const std::string& getString() const { return m_string; }
    unsigned getCharacterSize() const { return m_size; }
    const Color& getFillColor() const { return m_fill; }
    const Color& getOutlineColor() const { return m_outline; }
    float getOutlineThickness() const { return m_outlineThickness; }
    float getLetterSpacing() const { return m_letterSpacing; }

    FloatRect getLocalBounds() const {
        int font = m_font ? m_font->handle() : 0;
        float w = (float)txt_width(font, m_string.c_str(), (int)m_string.size(),
                                   (int)m_size, m_letterSpacing - 1.f);
        return FloatRect(0.f, 0.f, w, (float)m_size);
    }
    FloatRect getGlobalBounds() const { return getTransform().transformRect(getLocalBounds()); }

protected:
    void draw(RenderTarget& target, RenderStates states) const override {
        if (m_string.empty()) return;
        int font = m_font ? m_font->handle() : 0;
        target.beginDraw(states);
        RenderTarget::applyTransform(getTransform());
        if (m_outlineThickness > 0.f && m_outline.a > 0) {
            float t = m_outlineThickness;
            for (int oy = -1; oy <= 1; ++oy)
                for (int ox = -1; ox <= 1; ++ox)
                    if (ox != 0 || oy != 0)
                        gfx_draw_text(font, m_string.c_str(), (int)m_string.size(),
                                      ox * t, oy * t, (int)m_size,
                                      m_outline.toInteger(), m_letterSpacing - 1.f);
        }
        gfx_draw_text(font, m_string.c_str(), (int)m_string.size(),
                      0.f, 0.f, (int)m_size, m_fill.toInteger(), m_letterSpacing - 1.f);
        target.endDraw();
    }

private:
    std::string m_string;
    const Font* m_font{nullptr};
    unsigned    m_size{30};
    Color       m_fill{Color::White};
    Color       m_outline{Color(0, 0, 0)};
    float       m_outlineThickness{0.f};
    float       m_letterSpacing{1.f};
    Uint32      m_style{Regular};
};

}  // namespace sf
