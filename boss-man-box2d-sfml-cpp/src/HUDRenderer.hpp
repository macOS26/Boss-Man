#pragma once
#include <SFML/Graphics.hpp>
#include <string>
#include <unordered_set>
#include "Constants.hpp"
#include "PixelPersonRenderer.hpp"

namespace bm {

class HUDRenderer {
public:
    int lives = STARTING_LIVES;
    int score = 0;
    int highScore = 0;
    int level = 1;
    int collectedDots = 0;
    int dotCount = 0;
    int tpsReports = 0;
    std::unordered_set<std::string> reportItems;
    bool waterGunActive = false;
    bool waterGunVisible = false; // picked up this level (stays shown even when empty)
    int waterGunPellets = 0;
    bool goldDiscActive = false;
    std::string message;
    float messageTimer = 0.0f;
    bool isGameOver = false;

    void showMessage(const std::string& text, float duration);
    void update(float dt);
    void draw(sf::RenderTarget& target, float windowWidth, float windowHeight);

private:
    PixelPersonRenderer peteIcon_; // default config is PETE; used for life icons
    sf::Clock blinkClock_;         // drives the game-over prompt blink
};

} // namespace bm
