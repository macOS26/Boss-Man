#include "PixelPersonRenderer.hpp"
#include <algorithm>
#include <cmath>

namespace bm {

namespace {

// Rounded rectangle shape. SFML has no built-in, so we generate the corner arcs.
// Origin is the top-left corner (0,0)..(size.x,size.y), matching SFML conventions.
class RoundedRect : public sf::Shape {
public:
    RoundedRect(sf::Vector2f size, float radius, unsigned cornerPts = 6)
        : m_size(size), m_radius(radius), m_cornerPts(radius > 0.f ? cornerPts : 1) {
        update();
    }

    std::size_t getPointCount() const override { return m_cornerPts * 4; }

    sf::Vector2f getPoint(std::size_t index) const override {
        if (m_radius <= 0.f) {
            switch (index % 4) {
            case 0:  return {0.f, 0.f};
            case 1:  return {m_size.x, 0.f};
            case 2:  return {m_size.x, m_size.y};
            default: return {0.f, m_size.y};
            }
        }
        static const float PI = 3.14159265f;
        unsigned corner = (unsigned)index / m_cornerPts;
        float deltaAngle = (PI / 2.f) / (float)(m_cornerPts - 1);
        sf::Vector2f center;
        switch (corner) {
        case 0:  center = {m_size.x - m_radius, m_radius}; break;            // top-right
        case 1:  center = {m_radius, m_radius}; break;                       // top-left
        case 2:  center = {m_radius, m_size.y - m_radius}; break;            // bottom-left
        default: center = {m_size.x - m_radius, m_size.y - m_radius}; break; // bottom-right
        }
        float angle = deltaAngle * (float)(index % m_cornerPts) + (PI / 2.f) * (float)corner;
        return {center.x + m_radius * std::cos(angle),
                center.y - m_radius * std::sin(angle)};
    }

private:
    sf::Vector2f m_size;
    float m_radius;
    unsigned m_cornerPts;
};

} // namespace

void PixelPersonRenderer::draw(sf::RenderTarget& target, sf::Vector2f position, bool facingLeft,
                               bool walking, MoveDirection lookDir, float walkPhase, float alpha, float scale) const {
    // Lift-up-only walk: legs rise from the rest line (never sink below it) and
    // alternate, arms swing opposite and cross-paired, matching the SpriteKit actions.
    float legAmp = 3.0f + config.walkExaggeration;
    float armAmp = 2.0f + config.walkExaggeration;
    float leftLegLift = 0, rightLegLift = 0, leftArmSwing = 0, rightArmSwing = 0;
    if (walking) {
        // walkPhase is elapsed walking time in SECONDS (accumulated by the caller
        // while moving). The SpriteKit master runs the leg/arm cycle as two
        // stepDuration phases (up then down), so a full cycle is 2*stepDuration of
        // real time. Mapping seconds -> radians at 2*PI per full cycle keeps the
        // cadence locked to the master regardless of the 60/120Hz render loop.
        static const float PI = 3.14159265f;
        static const float STEP_DURATION = 0.16f;             // master stepDuration
        static const float CYCLE_RATE = PI / STEP_DURATION;   // 2*PI / (2*stepDuration)
        float w = walkPhase * CYCLE_RATE;
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
    auto skinFill = toSfColor(config.skinColor);

    // Capture/spawn scale applied uniformly through render states (identity when scale==1).
    sf::RenderStates states;
    if (scale != 1.0f) {
        sf::Transform tf;
        tf.scale(scale, scale, position.x, position.y);
        states.transform = tf;
    }

    // Whole-node alpha (spawn fade-in, shield blink, capture fade) multiplies into every part.
    auto fade = [&](sf::Color c) {
        c.a = (uint8_t)(c.a * alpha);
        return c;
    };

    // Rounded/plain rect with a SpriteKit-style centered stroke. SFML's
    // setOutlineThickness grows outward and renders unevenly at the rounded
    // corners, so instead draw two filled rounded rects: the outer one in the
    // stroke colour (the w x h path grown by lw/2 each side) and the fill inset by
    // lw/2 on top. That yields a uniform-width border with clean rounded corners,
    // matching the SpriteKit master (half-in / half-out on the w x h path).
    auto drawR = [&](float offX, float offY, float w, float h, sf::Color fill,
                     sf::Color out = sf::Color::Transparent, float lw = 0.f, float radius = 0.f) {
        if (lw > 0.f && out.a > 0) {
            RoundedRect outer({w + lw, h + lw}, radius > 0.f ? radius + lw * 0.5f : 0.f);
            outer.setFillColor(fade(out));
            outer.setPosition(position.x + offX - (w + lw) / 2.f, position.y + offY - (h + lw) / 2.f);
            target.draw(outer, states);
            RoundedRect inner({w - lw, h - lw}, radius > 0.f ? std::max(0.f, radius - lw * 0.5f) : 0.f);
            inner.setFillColor(fade(fill));
            inner.setPosition(position.x + offX - (w - lw) / 2.f, position.y + offY - (h - lw) / 2.f);
            target.draw(inner, states);
        } else {
            RoundedRect shape({w, h}, radius);
            shape.setFillColor(fade(fill));
            shape.setPosition(position.x + offX - w / 2.f, position.y + offY - h / 2.f);
            target.draw(shape, states);
        }
    };

    auto drawC = [&](float offX, float offY, float radius, sf::Color fill) {
        sf::CircleShape c(radius);
        c.setFillColor(fade(fill));
        c.setPosition(position.x + offX - radius, position.y + offY - radius);
        target.draw(c, states);
    };

    bool needsBacking = config.bodyColor.a < 1.0f;
    bool back = config.backView;
    float headY = -13 + config.headYOffset;

    // Reusable part draws, sequenced below in the painter order the SpriteKit
    // zPositions imply. Back view differs only in ordering and three omissions
    // (no collar/tie/eyes) plus a hair-coloured head; the shapes are identical.
    auto drawLegs = [&] {
        drawR(-4 * sx, 14 - leftLegLift, 6, 8, pantsFill);
        drawR(4 * sx, 14 - rightLegLift, 6, 8, pantsFill);
    };
    auto drawShoes = [&] {
        drawR((-4 + 1) * sx, 19 - leftLegLift, 8, 3, shoeFill, shoeOut, 1.0f);
        drawR((4 + 1) * sx, 19 - rightLegLift, 8, 3, shoeFill, shoeOut, 1.0f);
    };
    auto drawTorsoBacking = [&] {
        if (needsBacking)
            drawR(0, 2, 18, 16, sf::Color::White, sf::Color::Transparent, 0.f, 2.0f);
    };
    auto drawArmBacking = [&] {
        if (!needsBacking) return;
        drawR(-11 * sx, 2 + leftArmSwing, 5, 14, sf::Color::White, sf::Color::Transparent, 0.f, 1.0f);
        drawR(11 * sx, 2 + rightArmSwing, 5, 14, sf::Color::White, sf::Color::Transparent, 0.f, 1.0f);
    };
    auto drawArms = [&] {
        drawR(-11 * sx, 2 + leftArmSwing, 5, 14, bodyFill, sf::Color::White, 1.0f, 1.0f);
        drawR(11 * sx, 2 + rightArmSwing, 5, 14, bodyFill, sf::Color::White, 1.0f, 1.0f);
    };
    auto drawHands = [&] {
        drawC(-11 * sx, 10 + leftArmSwing, 2.5f, skinFill);
        drawC(11 * sx, 10 + rightArmSwing, 2.5f, skinFill);
    };
    auto drawTorso = [&] {
        drawR(0, 2, 18, 16, bodyFill, sf::Color::White, 1.5f, 2.0f);
    };
    auto drawHead = [&] {
        sf::Color faceFill = back ? hairFill : skinFill;
        drawR(0, headY, 14, 12, faceFill, sf::Color::Transparent, 0.f, 2.0f);
        drawR(0, headY - 4, 14, 4, hairFill);
    };

    if (back) {
        // Back silhouette painter order (ascending effective SpriteKit z):
        // shoes (z 0, behind legs), legs (1), backings (1.5/2.5),
        // hands (z 2, behind sleeves), arms (3), shirt back (3.5, over arms),
        // head (4, hair-coloured). No collar, tie, or eyes.
        drawShoes();
        drawLegs();
        drawTorsoBacking();
        drawArmBacking();
        drawHands();
        drawArms();
        drawTorso();
        drawHead();
        return;
    }

    // Front silhouette: legs(1), shoes over legs, torso backing(1.5), torso(2)+collar,
    // arm backing(2.5), arms(3)+hands over arms, tie(3), head(4)+hair+eyes/shades.
    drawLegs();
    drawShoes();
    drawTorsoBacking();
    drawTorso();
    drawR(0, -3, 8, 3, sf::Color::White);   // collar, child of torso
    drawArmBacking();
    drawArms();
    drawHands();

    // Tie (on top of arms, shifts with look direction like original)
    if (config.wearsSunglasses) {
        drawR(lookOffX * sx, 2 + lookOffY, 4, 12, tieFill, sf::Color::White, 1.0f);
    } else {
        drawR(lookOffX * sx, 2 + lookOffY, 4, 12, tieFill);
    }

    drawHead();

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
