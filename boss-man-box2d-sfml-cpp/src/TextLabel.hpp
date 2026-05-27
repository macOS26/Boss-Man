#pragma once
#include <SFML/Graphics.hpp>
#include "UiScale.hpp"
#include <string>

namespace bm {

// Draws horizontally-centered text whose baseline sits at baselineY. Rasterized
// at characterSize * uiScale() and counter-scaled so it stays crisp on Retina,
// matching the HUD/title text path. Used for the PETE / boss name tags, which in
// SpriteKit are SKLabelNodes with default (baseline) vertical alignment.
inline void drawNameLabel(sf::RenderTarget& target, const sf::Font& font,
                          const std::string& text, unsigned size, sf::Color color,
                          float centerX, float baselineY) {
    float dpi = uiScale();
    sf::Text t;
    t.setFont(font);
    t.setString(text);
    t.setCharacterSize((unsigned)(size * dpi));
    t.setFillColor(color);
    auto lb = t.getLocalBounds();
    // Center horizontally; anchor on the bounding-box bottom (= baseline for the
    // all-caps tags) so glyphs sit above baselineY like the SpriteKit labels.
    t.setOrigin(lb.left + lb.width / 2.f, lb.top + lb.height);
    t.setScale(1.f / dpi, 1.f / dpi);
    t.setPosition(centerX, baselineY);
    target.draw(t);
}

} // namespace bm
