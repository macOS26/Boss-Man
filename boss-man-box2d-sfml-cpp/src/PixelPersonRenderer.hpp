#pragma once
#include <SFML/Graphics.hpp>
#include "Constants.hpp"
#include "MoveDirection.hpp"

namespace bm {

struct PersonConfig {
    Color bodyColor = PETE_BODY;
    Color tieColor = PETE_TIE;
    Color hairColor = PETE_HAIR;
    Color shoeOutlineColor = WHITE;
    Color pantsColor = PETE_PANTS;
    // Skin tone (head + hands). Defaults to SKIN_COLOR; frightened bosses
    // override this to FLEE_SKIN so face/hands read blue.
    Color skinColor = SKIN_COLOR;
    float walkExaggeration = 0.0f;
    bool wearsSunglasses = false;
    float headYOffset = 0.0f; // positive = lower on screen (SFML Y-down)
};

class PixelPersonRenderer {
public:
    PersonConfig config;

    PixelPersonRenderer(const PersonConfig& cfg = {}) : config(cfg) {}

    void draw(sf::RenderTarget& target, sf::Vector2f position, bool facingLeft,
              bool walking, MoveDirection lookDir, float walkPhase, float alpha = 1.0f, float scale = 1.0f) const;

    static sf::Color toSfColor(Color c) {
        return sf::Color((uint8_t)(c.r * 255), (uint8_t)(c.g * 255),
                         (uint8_t)(c.b * 255), (uint8_t)(c.a * 255));
    }
};

} // namespace bm