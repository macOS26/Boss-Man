#pragma once
#include <SFML/Graphics.hpp>
#include <vector>
#include <string>

namespace bm {

struct ScorePopup {
    std::string text;
    sf::Vector2f position;
    float timer = 0.7f;
    int points;
    bool isRed = false;
};

class ScorePopupManager {
public:
    std::vector<ScorePopup> popups;

    void add(int points, sf::Vector2f pos, bool isRed = false) {
        ScorePopup p;
        p.text = (points >= 0 ? "+" : "") + std::to_string(points);
        p.position = pos;
        p.timer = 0.7f;
        p.points = points;
        p.isRed = isRed;
        popups.push_back(p);
    }

    void update(float dt) {
        for (auto& p : popups) {
            p.timer -= dt;
            p.position.y -= 30 * dt;
        }
        popups.erase(std::remove_if(popups.begin(), popups.end(),
            [](const ScorePopup& p) { return p.timer <= 0; }), popups.end());
    }

    void draw(sf::RenderTarget& target) {
        static sf::Font font;
        static bool fontLoaded = false;
        if (!fontLoaded) {
            fontLoaded = font.loadFromFile("assets/fonts/JetBrainsMono-Bold.ttf") ||
                         font.loadFromFile("/System/Library/Fonts/Menlo.ttc") ||
                         font.loadFromFile("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf");
        }
        for (auto& p : popups) {
            uint8_t alpha = (uint8_t)(std::min(1.0f, p.timer / 0.3f) * 255);
            sf::Text text;
            text.setFont(font);
            text.setString(p.text);
            text.setCharacterSize(14);
            text.setFillColor(p.isRed ? sf::Color(255, 69, 58, alpha) : sf::Color(255, 255, 255, alpha));
            text.setPosition(p.position.x - text.getLocalBounds().width/2, p.position.y);
            target.draw(text);
        }
    }
};

} // namespace bm