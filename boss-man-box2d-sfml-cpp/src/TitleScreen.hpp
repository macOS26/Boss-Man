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
    enum class Hit { None, Play, Editor, BossTracks, WaterGun, Fullscreen, Window };

    void draw(sf::RenderTarget& target, float windowW, float windowH,
              int highScore, const std::vector<LeaderboardEntry>& board);

    // Hit-test a click in logical (letterboxed) coordinates against the buttons
    // and the bottom-right toggle column. Rects are set by the most recent draw().
    Hit hitTest(float x, float y) const;

private:
    void ensureLoaded();

    bool loaded_ = false;
    bool staplerLoaded_ = false;
    sf::Font fontWide_;  // Marker Felt Wide (title)
    sf::Font fontThin_;  // Marker Felt Thin (everything else)
    sf::Font fontMono_;  // JetBrains Mono Bold (HUD font) — hints + toggles
    sf::Texture stapler_;
    sf::Texture panelShadow_; // soft, feathered drop shadow for the leaderboard panel
    sf::Clock blinkClock_;

    sf::FloatRect playRect_, editorRect_;
    sf::FloatRect bossTracksRect_, waterGunRect_, fullscreenRect_, windowRect_;
};

} // namespace bm
