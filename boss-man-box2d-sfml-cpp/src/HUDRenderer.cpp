#include "HUDRenderer.hpp"
#include "EmojiText.hpp"
#include "UiScale.hpp"
#include <cmath>

namespace bm {

namespace {

// Emoji UTF-8 (matching original SpriteKit HUD glyphs)
const std::string EMO_CHECK   = "\xE2\x9C\x85";                 // ✅
const std::string EMO_UNCHECK = "\xE2\x9D\x8C";                 // ❌
const std::string EMO_PRINTER = "\xF0\x9F\x96\xA8\xEF\xB8\x8F"; // 🖨️
const std::string EMO_FAX     = "\xF0\x9F\x93\xA0";             // 📠
const std::string EMO_COVER   = "\xF0\x9F\x93\x84";             // 📄
const std::string EMO_BINDER  = "\xF0\x9F\x93\x9A";             // 📚
const std::string EMO_GUN     = "\xF0\x9F\x94\xAB";            // 🔫

const std::string& machineEmoji(const std::string& name) {
    static const std::string none;
    if (name == Machine::PRINTER)     return EMO_PRINTER;
    if (name == Machine::FAX)         return EMO_FAX;
    if (name == Machine::COVER_SHEET) return EMO_COVER;
    if (name == Machine::BOOK_BINDER) return EMO_BINDER;
    return none;
}

const sf::Font& hudFont() {
    static sf::Font font;
    static bool loaded = false;
    if (!loaded) {
        loaded = font.loadFromFile("assets/fonts/JetBrainsMono-Bold.ttf") ||
                 font.loadFromFile("/System/Library/Fonts/Menlo.ttc") ||
                 font.loadFromFile("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf");
    }
    return font;
}

// Draw text vertically centered at centerY. halign: 0=left, 1=center, 2=right.
// Returns the rendered width.
float drawText(sf::RenderTarget& t, const std::string& s, unsigned size, sf::Color color,
               float x, float centerY, int halign) {
    float dpi = uiScale();
    sf::Text txt;
    txt.setFont(hudFont());
    txt.setString(s);
    txt.setCharacterSize((unsigned)(size * dpi)); // rasterize hi-res, counter-scale below
    txt.setFillColor(color);
    auto lb = txt.getLocalBounds();
    float ox = (halign == 0) ? lb.left : (halign == 2 ? lb.left + lb.width : lb.left + lb.width / 2.f);
    txt.setOrigin(ox, lb.top + lb.height / 2.f);
    txt.setScale(1.f / dpi, 1.f / dpi);
    txt.setPosition(x, centerY);
    t.draw(txt);
    return lb.width / dpi; // report logical width
}

} // namespace

void HUDRenderer::showMessage(const std::string& text, float duration) {
    message = text;
    messageTimer = duration;
}

void HUDRenderer::update(float dt) {
    if (messageTimer > 0) {
        messageTimer -= dt;
        if (messageTimer <= 0) message.clear();
    }
}

void HUDRenderer::draw(sf::RenderTarget& target, float windowWidth, float windowHeight) {
    const float panelH = HUD_HEIGHT;

    // Panel background (top of screen)
    sf::RectangleShape panel(sf::Vector2f(windowWidth, panelH));
    panel.setFillColor(sf::Color(8, 10, 13, 235));
    target.draw(panel);

    // Vertical centers from the top edge, matching the SpriteKit layout (100px panel).
    const float row1 = 22.f, row2 = 52.f, row3 = 84.f;
    const unsigned FS = 19;

    // Status line
    drawText(target,
             "Score: " + std::to_string(score) + "   High: " + std::to_string(highScore) +
                 "   Level: " + std::to_string(level) + "   Dots: " + std::to_string(collectedDots) +
                 "/" + std::to_string(dotCount) + "   Reports: " + std::to_string(tpsReports),
             FS, sf::Color::White, 16, row1, 0);

    // TPS checklist with emoji (✅/❌ + machine icon per required item)
    float x = 16;
    x += drawText(target, "TPS:", FS, sf::Color::White, x, row2, 0) + 10;
    const float em = 20.f;
    for (auto& req : Machine::REQUIRED) {
        bool has = reportItems.count(req) > 0;
        drawEmoji(target, has ? EMO_CHECK : EMO_UNCHECK, {x + em / 2.f, row2}, em);
        x += em;
        drawEmoji(target, machineEmoji(req), {x + em / 2.f, row2}, em);
        x += em + 12.f;
    }

    // Lives: label + mini-PETE figures
    drawText(target, "Lives:", FS, sf::Color(50, 200, 90), 16, row3, 0);
    for (int i = 0; i < lives; ++i) {
        float ix = 90 + i * 24.f;
        peteIcon_.draw(target, {ix, row3}, false, false, MoveDirection::None, 0.f, 1.f, 0.45f);
    }

    // Level traveler-emoji progression (top-right, grows leftward)
    int cyclePos = ((level - 1) % TRAVELER_COUNT) + 1;
    for (int i = 0; i < cyclePos; ++i) {
        float ex = (windowWidth - 25.f) - (cyclePos - 1 - i) * 26.f;
        drawEmoji(target, TRAVELERS[i].emoji, {ex, row1}, 18.f);
    }

    // Message (right-aligned, yellow)
    if (!message.empty())
        drawText(target, message, FS, sf::Color(255, 231, 0), windowWidth - 16, row2, 2);

    // Water gun: 🔫 icon + ammo dots (filled = loaded, ring = spent). Drawn as
    // shapes rather than ●/○ glyphs, which the mono fonts lack (render as tofu).
    if (waterGunVisible) {
        bool empty = !waterGunActive || waterGunPellets == 0;
        sf::Color ammoColor = goldDiscActive ? sf::Color(10, 122, 255, 128)
                              : (empty ? sf::Color(255, 69, 58) : sf::Color(10, 122, 255));
        uint8_t gunAlpha = goldDiscActive ? 64 : (empty ? 128 : 255);
        drawEmoji(target, EMO_GUN, {windowWidth - 24.f, row3}, 20.f, sf::Color(255, 255, 255, gunAlpha));

        const float r = 7.f, spacing = 22.f, rightX = windowWidth - 54.f;
        for (int i = 0; i < WATER_GUN_PELLETS; ++i) {
            float cx = rightX - (WATER_GUN_PELLETS - 1 - i) * spacing;
            sf::CircleShape dot(r, 24);
            if (i < waterGunPellets) {
                dot.setFillColor(ammoColor);
            } else {
                dot.setFillColor(sf::Color::Transparent);
                dot.setOutlineColor(ammoColor);
                dot.setOutlineThickness(2.f);
            }
            dot.setPosition(cx - r, row3 - r);
            target.draw(dot);
        }
    }

    // Game over overlay
    if (isGameOver) {
        sf::RectangleShape dim(sf::Vector2f(windowWidth, windowHeight));
        dim.setFillColor(sf::Color(0, 0, 0, 199));
        target.draw(dim);

        float cx = windowWidth / 2;
        float cy = windowHeight / 2;

        sf::RectangleShape frame(sf::Vector2f(520, 220));
        frame.setFillColor(sf::Color(13, 13, 18));
        frame.setOutlineColor(sf::Color(255, 149, 0));
        frame.setOutlineThickness(3);
        frame.setPosition(cx - 260, cy - 110);
        target.draw(frame);

        drawText(target, Message::GAME_OVER, 56, sf::Color(255, 69, 58), cx, cy - 20, 1);

        // Blinking new-game prompt (1.0 <-> 0.2 over ~0.6s each way)
        float t = blinkClock_.getElapsedTime().asSeconds();
        uint8_t promptA = (uint8_t)((0.6f + 0.4f * std::sin(t * 5.24f)) * 255);
        drawText(target, Message::PROMPT_NEW_GAME, 18, sf::Color(255, 231, 0, promptA), cx, cy + 40, 1);
        drawText(target, Message::PROMPT_TITLE, 14, sf::Color(192, 192, 192), cx, cy + 72, 1);
    }
}

} // namespace bm
