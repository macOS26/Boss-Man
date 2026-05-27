#include "TitleScreen.hpp"
#include "UiScale.hpp"
#include "Assets.hpp"
#include <algorithm>
#include <cmath>
#include <string>

namespace bm {

namespace {
// halign: 0=left, 1=center, 2=right. Always vertically centered at (x,y).
// Rasterized at size*uiScale and counter-scaled so it stays crisp on Retina.
void drawText(sf::RenderTarget& t, const sf::Font& f, const std::string& s, unsigned size,
              sf::Color color, float x, float y, int halign = 1,
              float rotationDeg = 0.f, uint8_t alpha = 255) {
    float dpi = uiScale();
    sf::Text txt;
    txt.setFont(f);
    txt.setString(s); // interpret bytes as UTF-8
    txt.setCharacterSize((unsigned)(size * dpi));
    color.a = alpha;
    txt.setFillColor(color);
    auto lb = txt.getLocalBounds();
    float ox = (halign == 0) ? lb.left : (halign == 2 ? lb.left + lb.width : lb.left + lb.width / 2.f);
    // SpriteKit SKLabelNode uses baseline vertical alignment by default: the node's
    // y is the text baseline and glyphs sit above it. Anchor on the bounding-box
    // bottom (= baseline for these all-caps labels) so the layout matches exactly.
    txt.setOrigin(ox, lb.top + lb.height);
    txt.setScale(1.f / dpi, 1.f / dpi);
    txt.setPosition(x, y);
    txt.setRotation(rotationDeg);
    t.draw(txt);
}
} // namespace

void TitleScreen::ensureLoaded() {
    if (loaded_) return;
    loaded_ = true;
    loadFont(fontWide_, "assets/fonts/MarkerFelt-Wide.ttf");
    loadFont(fontThin_, "assets/fonts/MarkerFelt-Thin.ttf");
    loadFont(fontMono_, "assets/fonts/JetBrainsMono-Bold.ttf");
    staplerLoaded_ = loadTexture(stapler_, "assets/images/red-stapler.png");
    if (staplerLoaded_) stapler_.setSmooth(true);
}

void TitleScreen::draw(sf::RenderTarget& target, float W, float H,
                       int highScore, const std::vector<LeaderboardEntry>& board) {
    ensureLoaded();

    // Background (matches SpriteKit 1.0, 0.93, 0.34)
    sf::RectangleShape bg(sf::Vector2f(W, H));
    bg.setFillColor(sf::Color(255, 237, 87));
    target.draw(bg);

    const sf::Color ink(0, 0, 0);

    // --- Leaderboard sticky-note panel (drawn first; title sits on top if overlapping) ---
    const float panelW = 320.f, panelH = 400.f;
    const float panelCX = panelW / 2.f + 32.f;
    const float panelCY = H * 0.5f;
    const float panelLeft = panelCX - panelW / 2.f;
    const float panelTop = panelCY - panelH / 2.f;

    // Drop shadow behind the panel, offset down-right.
    {
        sf::RectangleShape shadow(sf::Vector2f(panelW, panelH));
        shadow.setFillColor(sf::Color(0, 0, 0, 60));
        shadow.setPosition(panelLeft + 6.f, panelTop + 8.f);
        target.draw(shadow);
    }

    // Post-it body
    sf::RectangleShape postIt(sf::Vector2f(panelW, panelH));
    postIt.setFillColor(sf::Color(255, 235, 107)); // 1.0, 0.92, 0.42
    postIt.setPosition(panelLeft, panelTop);
    target.draw(postIt);

    // Adhesive strip across the top
    sf::RectangleShape adhesive(sf::Vector2f(panelW, 32.f));
    adhesive.setFillColor(sf::Color(255, 224, 87, 115)); // 1.0, 0.88, 0.34, 0.45
    adhesive.setPosition(panelLeft, panelTop);
    target.draw(adhesive);

    // Header + underline
    float headerY = panelCY - 140.f;
    drawText(target, fontThin_, "LEADERBOARD", 24, sf::Color(46, 26, 10), panelCX, headerY, 1);
    sf::RectangleShape underline(sf::Vector2f(panelW - 44.f, 2.f));
    underline.setFillColor(sf::Color(0, 0, 0, 102)); // alpha 0.40
    underline.setPosition(panelLeft + 22.f, headerY + 14.f);
    target.draw(underline);

    // Entries (or a placeholder when empty)
    if (board.empty()) {
        drawText(target, fontThin_, "NO SCORES YET", 18, sf::Color(0, 0, 0, 178),
                 panelCX, panelCY, 1);
    } else {
        float startY = headerY + 42.f;
        float rowH = 28.f;
        float rankRight = panelCX - panelW / 2.f + 40.f; // leftEdge(18) + rank col(22)
        float nameLeft = rankRight + 4.f;
        float scoreRight = panelCX + panelW / 2.f - 18.f;
        int n = std::min((int)board.size(), 10);
        for (int i = 0; i < n; ++i) {
            float y = startY + i * rowH;
            drawText(target, fontThin_, std::to_string(i + 1) + ".", 18, ink, rankRight, y, 2);
            drawText(target, fontThin_, board[i].name, 18, ink, nameLeft, y, 0);
            drawText(target, fontThin_, std::to_string(board[i].score), 18, ink, scoreRight, y, 2);
        }
    }

    // --- Title "BOSS-MAN" — Marker Felt Wide, tilted (SpriteKit zRotation -0.04) ---
    drawText(target, fontWide_, "BOSS-MAN", 108, ink, W / 2.f, H * 0.26f, 1, 2.3f);

    // --- Red stapler, fit to ~290px, tilted (zRotation -0.06) ---
    if (staplerLoaded_) {
        sf::Sprite sp(stapler_);
        auto ts = stapler_.getSize();
        float fit = 290.f / (float)std::max(ts.x, ts.y);
        sp.setOrigin(ts.x / 2.f, ts.y / 2.f);
        sp.setScale(fit, fit);
        sp.setRotation(3.4f);
        // SpriteKit centers the stapler sprite at height*0.46 (i.e. 0.54 from top).
        sp.setPosition(W / 2.f, H * 0.54f);
        target.draw(sp);
    }

    // --- Blinking prompt ---
    float t = blinkClock_.getElapsedTime().asSeconds();
    uint8_t a = (uint8_t)((0.625f + 0.375f * std::sin(t * 5.24f)) * 255); // ~1.0<->0.25
    drawText(target, fontThin_, "P to Play \xC2\xB7 E for Editor", 40, ink, W / 2.f, H * 0.85f, 1, 0.f, a);

    // --- High score ---
    if (highScore > 0) {
        drawText(target, fontThin_, "HIGH SCORE " + std::to_string(highScore), 26, ink,
                 W / 2.f, H * 0.94f, 1);
    }

    // --- Fullscreen hint, bottom-right, HUD mono font ---
    drawText(target, fontMono_, "F for Fullscreen", 16, ink, W - 20.f, H - 18.f, 2);
}

} // namespace bm
