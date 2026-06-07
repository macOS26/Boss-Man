#pragma once
#include <SFML/Graphics.hpp>
#include <algorithm>
#include "Constants.hpp"
#include "MoveDirection.hpp"

namespace bm {

struct PersonConfig {
    Color bodyColor = PETE_BODY;
    Color tieColor = PETE_TIE;
    Color hairColor = PETE_HAIR;
    Color shoeOutlineColor = WHITE;
    Color pantsColor = PETE_PANTS;
    Color skinColor = SKIN_COLOR;
    Color eyeColor = BLACK;
    Color shirtOutlineColor = WHITE;
    Color tieOutlineColor = {0.f, 0.f, 0.f, 0.f};
    float tieLineWidth = 0.f;
    float walkExaggeration = 0.0f;
    bool wearsSunglasses = false;
    float headYOffset = 0.0f;
    bool backView = false;
};

class PixelPersonRenderer {
public:
    PersonConfig config;

    PixelPersonRenderer(const PersonConfig& cfg = {}) : config(cfg) {}

    void draw(sf::RenderTarget& target, sf::Vector2f position, bool facingLeft,
              bool walking, MoveDirection lookDir, float walkPhase, float alpha = 1.0f, float scale = 1.0f) const;

    // Pixel footprint of a person, in the same units draw() uses (position is the
    // figure's origin: torso center, between the shoulders). The raycaster needs
    // these to size and vertically anchor a billboarded sprite of the avatar.
    //   width      : widest extent (arm to arm) = 27
    //   height     : head-top to shoe-bottom = 39.5
    //   feetOffset : distance from origin DOWN to the soles (shoe bottom)
    //   headOffset : distance from origin UP to the top of the hair/head
    // Multiply each by the draw() `scale` for a scaled figure.
    struct Metrics { float width, height, feetOffset, headOffset; };
    Metrics metrics() const {
        float feet = 20.5f + std::max(0.0f, config.headYOffset);
        float head = 19.0f - std::min(0.0f, config.headYOffset);
        return {27.0f, feet + head, feet, head};
    }

    static sf::Color toSfColor(Color c) {
        return sf::Color((uint8_t)(c.r * 255), (uint8_t)(c.g * 255),
                         (uint8_t)(c.b * 255), (uint8_t)(c.a * 255));
    }
};

} // namespace bm