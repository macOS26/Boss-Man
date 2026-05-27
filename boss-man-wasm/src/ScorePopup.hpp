#pragma once
#include <SFML/Graphics.hpp>
#include "UiScale.hpp"
#include "Assets.hpp"
#include <vector>
#include <string>
#include <algorithm>

namespace bm {

struct ScorePopup {
    std::string text;
    sf::Vector2f position;
    float timer = 0.7f;
    int points;
    bool isRed = false;
};

// Matches the SpriteKit ScorePopup: systemYellow (red for penalties), fontSize 18,
// spawns 20px above the source, rises 28px and fades out over 0.7s.
class ScorePopupManager {
public:
    std::vector<ScorePopup> popups;

    void add(int points, sf::Vector2f pos, bool isRed = false) {
        ScorePopup p;
        p.text = (points >= 0 ? "+" : "") + std::to_string(points);
        p.position = {pos.x, pos.y - 20.f}; // SpriteKit spawns the label 20px up
        p.timer = 0.7f;
        p.points = points;
        p.isRed = isRed;
        popups.push_back(p);
    }

    void update(float dt) {
        for (auto& p : popups) {
            p.timer -= dt;
            p.position.y -= 40.f * dt; // rise ~28px over the 0.7s lifetime
        }
        popups.erase(std::remove_if(popups.begin(), popups.end(),
            [](const ScorePopup& p) { return p.timer <= 0; }), popups.end());
    }

    void draw(sf::RenderTarget& target) {
        static sf::Font font;
        static bool fontLoaded = false;
        if (!fontLoaded) {
            fontLoaded = loadFont(font, "assets/fonts/JetBrainsMono-Bold.ttf");
        }
        float dpi = uiScale();
        for (auto& p : popups) {
            // Fade linearly across the whole lifetime, like SpriteKit's fadeOut(0.7).
            uint8_t alpha = (uint8_t)(std::clamp(p.timer / 0.7f, 0.f, 1.f) * 255);
            sf::Text text;
            text.setFont(font);
            text.setString(p.text);
            text.setCharacterSize((unsigned)(18 * dpi)); // rasterize hi-res, counter-scale below
            text.setFillColor(p.isRed ? sf::Color(255, 69, 58, alpha)   // systemRed
                                      : sf::Color(255, 231, 0, alpha)); // systemYellow
            auto lb = text.getLocalBounds();
            text.setOrigin(lb.left + lb.width / 2.f, lb.top + lb.height / 2.f);
            text.setScale(1.f / dpi, 1.f / dpi);
            text.setPosition(p.position.x, p.position.y);
            target.draw(text);
        }
    }
};

} // namespace bm
