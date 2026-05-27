#include "PixelPersonRenderer.hpp"
#include <algorithm>
#include <cmath>

namespace bm {

void PixelPersonRenderer::draw(sf::RenderTarget& target, sf::Vector2f position, bool facingLeft,
                               bool walking, MoveDirection lookDir, float walkPhase, float alpha, float scale) const {
    // Lift-up-only walk: legs rise from the rest line (never sink below it) and
    // alternate, arms swing opposite and cross-paired, matching the SpriteKit actions.
    float legAmp = 3.0f + config.walkExaggeration;
    float armAmp = 2.0f + config.walkExaggeration;
    float leftLegLift = 0, rightLegLift = 0, leftArmSwing = 0, rightArmSwing = 0;
    if (walking) {
        float w = walkPhase * 10.0f;
        leftLegLift   = legAmp * (0.5f - 0.5f * std::cos(w));
        rightLegLift  = legAmp * (0.5f + 0.5f * std::cos(w));
        leftArmSwing  = armAmp * (0.5f + 0.5f * std::cos(w));
        rightArmSwing = armAmp * (0.5f - 0.5f * std::cos(w));
    }

    // Look direction offset (1px shift for eyes AND tie, matching original)
    float lookOffX = 0, lookOffY = 0;
    if (lookDir == MoveDirection::Left || lookDir == MoveDirection::Right) lookOffX = 1;
    else if (lookDir == MoveDirection::Up) lookOffY = -1;  // SFML Y-down
    else if (lookDir == MoveDirection::Down) lookOffY = 1;

    float sx = facingLeft ? -1.0f : 1.0f;
    auto bodyFill = toSfColor(config.bodyColor);
    auto tieFill = toSfColor(config.tieColor);
    auto pantsFill = toSfColor(config.pantsColor);
    auto hairFill = toSfColor(config.hairColor);
    auto shoeFill = toSfColor(SHOE_COLOR);
    auto shoeOut = toSfColor(config.shoeOutlineColor);
    auto skinFill = toSfColor(SKIN_COLOR);

    // Whole-node alpha (spawn fade-in, shield blink, capture fade) multiplies into every part.
    auto fade = [&](sf::Color c) {
        c.a = (uint8_t)(c.a * alpha);
        return c;
    };

    // Rounded/plain rect. To emulate SpriteKit's centered stroke (half in / half out),
    // SFML can only expand the outline outward, so we shrink the fill by the line width
    // and let the outline grow back to the original silhouette.
    auto drawR = [&](float offX, float offY, float w, float h, sf::Color fill,
                     sf::Color out = sf::Color::Transparent, float lw = 0.f, float radius = 0.f) {
        float sw = w - lw;
        float sh = h - lw;
        (void)radius; // wrapper shapes are rectangular; rounded corners aren't representable
        sf::RectangleShape shape(sf::Vector2f(sw, sh));
        shape.setFillColor(fade(fill));
        shape.setOutlineColor(fade(out));
        shape.setOutlineThickness(lw);
        shape.setPosition(position.x + offX - sw / 2.f, position.y + offY - sh / 2.f);
        target.draw(shape);
    };

    auto drawC = [&](float offX, float offY, float radius, sf::Color fill) {
        sf::CircleShape c(radius);
        c.setFillColor(fade(fill));
        c.setPosition(position.x + offX - radius, position.y + offY - radius);
        target.draw(c);
    };

    // Drawing order matches original SpriteKit zPositions:
    // z=1: legs, z=1.5: torso backing, z=2: torso+collar, z=2.5: arm backing,
    // z=3: arms+hands+tie, z=4: head+hair+eyes

    // z=1: Legs (lift up only)
    drawR(-4 * sx, 14 - leftLegLift, 6, 8, pantsFill);
    drawR(4 * sx, 14 - rightLegLift, 6, 8, pantsFill);

    // Shoes (children of legs)
    drawR((-4 + 1) * sx, 19 - leftLegLift, 8, 3, shoeFill, shoeOut, 1.0f);
    drawR((4 + 1) * sx, 19 - rightLegLift, 8, 3, shoeFill, shoeOut, 1.0f);

    // z=1.5: Torso backing (only for translucent bodies like DOM)
    bool needsBacking = config.bodyColor.a < 1.0f;
    if (needsBacking) {
        drawR(0, 2, 18, 16, sf::Color::White, sf::Color::Transparent, 0.f, 2.0f);
    }

    // z=2: Torso
    drawR(0, 2, 18, 16, bodyFill, sf::Color::White, 1.5f, 2.0f);

    // Collar (child of torso)
    drawR(0, -3, 8, 3, sf::Color::White);

    // z=2.5: Arm backing (only for translucent bodies)
    if (needsBacking) {
        drawR(-11 * sx, 2 + leftArmSwing, 5, 14, sf::Color::White, sf::Color::Transparent, 0.f, 1.0f);
        drawR(11 * sx, 2 + rightArmSwing, 5, 14, sf::Color::White, sf::Color::Transparent, 0.f, 1.0f);
    }

    // z=3: Arms (drawn before tie so tie is on top)
    drawR(-11 * sx, 2 + leftArmSwing, 5, 14, bodyFill, sf::Color::White, 1.0f, 1.0f);
    drawR(11 * sx, 2 + rightArmSwing, 5, 14, bodyFill, sf::Color::White, 1.0f, 1.0f);

    // Hands (children of arms, at bottom of arm)
    drawC(-11 * sx, 10 + leftArmSwing, 2.5f, skinFill);
    drawC(11 * sx, 10 + rightArmSwing, 2.5f, skinFill);

    // z=3: Tie (on top of arms, shifts with look direction like original)
    if (config.wearsSunglasses) {
        drawR(lookOffX * sx, 2 + lookOffY, 4, 12, tieFill, sf::Color::White, 1.0f);
    } else {
        drawR(lookOffX * sx, 2 + lookOffY, 4, 12, tieFill);
    }

    // z=4: Head
    float headY = -13 + config.headYOffset;
    drawR(0, headY, 14, 12, skinFill, sf::Color(0, 0, 0, 128), 1.0f, 2.0f);

    // Hair (child of head)
    drawR(0, headY - 4, 14, 4, hairFill);

    // Eyes or sunglasses
    if (config.wearsSunglasses) {
        drawR(0, headY, 12, 4, sf::Color(30, 30, 30));
    } else {
        // Eyes shift 1px in look direction, mirrored by sx for facing
        drawR((-3 + lookOffX) * sx, headY + lookOffY, 2, 2, sf::Color::Black);
        drawR((3 + lookOffX) * sx, headY + lookOffY, 2, 2, sf::Color::Black);
    }
}

} // namespace bm
