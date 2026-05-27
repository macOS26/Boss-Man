#pragma once
#include <SFML/Graphics.hpp>
#include <vector>
#include "LocalLeaderboard.hpp"

namespace bm {

// Renders the title screen to match the SpriteKit TitleScene: yellow background,
// Marker Felt "BOSS-MAN", red stapler, blinking prompt, high score, and the
// sticky-note leaderboard panel.
class TitleScreen {
public:
    void draw(sf::RenderTarget& target, float windowW, float windowH,
              int highScore, const std::vector<LeaderboardEntry>& board);

private:
    void ensureLoaded();

    bool loaded_ = false;
    bool staplerLoaded_ = false;
    sf::Font fontWide_;  // Marker Felt Wide (title)
    sf::Font fontThin_;  // Marker Felt Thin (everything else)
    sf::Font fontMono_;  // JetBrains Mono Bold (HUD font) — fullscreen hint
    sf::Texture stapler_;
    sf::Clock blinkClock_;
};

} // namespace bm
