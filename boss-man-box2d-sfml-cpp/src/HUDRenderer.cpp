#include "HUDRenderer.hpp"
#include "EmojiText.hpp"
#include "UiScale.hpp"
#include "Assets.hpp"
#include "Settings.hpp"
#include <cmath>
#include <algorithm>

namespace bm {

namespace {

// Emoji UTF-8 (matching original SpriteKit HUD glyphs)
const std::string EMO_DICE    = "\xF0\x9F\x8E\xB2";             // 🎲 U+1F3B2
const std::string EMO_PRINTER = "\xF0\x9F\x96\xA8\xEF\xB8\x8F"; // 🖨️ U+1F5A8 U+FE0F
const std::string EMO_FAX     = "\xF0\x9F\x93\xA0";             // 📠 U+1F4E0
const std::string EMO_COVER   = "\xF0\x9F\x93\x84";             // 📄 U+1F4C4
const std::string EMO_BINDER  = "\xF0\x9F\x93\x9A";             // 📚 U+1F4DA
const std::string EMO_GUN     = "\xF0\x9F\x94\xAB";             // 🔫 U+1F52B
const std::string EMO_DIAMOND = "\xF0\x9F\x92\x8E";            // 💎 U+1F48E

// Report books: 📙 📘 📗 📕 (orange, blue, green, red)
const std::string REPORT_BOOKS[4] = {
    "\xF0\x9F\x93\x99", "\xF0\x9F\x93\x98", "\xF0\x9F\x93\x97", "\xF0\x9F\x93\x95"
};

const std::string& machineEmoji(const std::string& name) {
    static const std::string none;
    if (name == Machine::PRINTER)     return EMO_PRINTER;
    if (name == Machine::FAX)         return EMO_FAX;
    if (name == Machine::COVER_SHEET) return EMO_COVER;
    if (name == Machine::BOOK_BINDER) return EMO_BINDER;
    return none;
}

// SpriteKit menloBold stand-in: the embedded mono bold font. The message /
// PAUSED label is MarkerFelt-Wide, matching the spec's only non-menlo label.
const sf::Font& menloFont() {
    static sf::Font font;
    static bool loaded = false;
    if (!loaded) loaded = loadFont(font, "assets/fonts/JetBrainsMono-Bold.ttf");
    return font;
}

const sf::Font& markerFeltFont() {
    static sf::Font font;
    static bool loaded = false;
    if (!loaded) loaded = loadFont(font, "assets/fonts/MarkerFelt-Wide.ttf");
    return font;
}

// ASCII-only uppercase (HUD.allCaps): a-z -> A-Z by byte, everything else
// (UTF-8 emoji lead/continuation bytes are >= 0x80, digits, punctuation) is
// left untouched. Replicated exactly; never a locale-aware uppercase.
std::string allCaps(const std::string& s) {
    std::string out = s;
    for (char& c : out) {
        unsigned char u = (unsigned char)c;
        if (u >= 97 && u <= 122) c = (char)(u - 32);
    }
    return out;
}

// Draw a label vertically centered at centerY. halign: 0=left, 1=center, 2=right.
// Returns the rendered logical width. Rasterized at uiScale and counter-scaled so
// glyphs stay crisp on Retina (matching the rest of the SFML port).
float drawLabel(sf::RenderTarget& t, const sf::Font& font, const std::string& s,
                float sizePx, sf::Color color, float x, float centerY, int halign,
                float alpha = 1.f) {
    if (s.empty()) return 0.f;
    float dpi = uiScale();
    sf::Text txt;
    txt.setFont(font);
    txt.setString(s);
    txt.setCharacterSize((unsigned)(sizePx * dpi));
    color.a = (uint8_t)std::round(color.a * alpha);
    txt.setFillColor(color);
    auto lb = txt.getLocalBounds();
    float ox = (halign == 0) ? lb.left : (halign == 2 ? lb.left + lb.width : lb.left + lb.width / 2.f);
    txt.setOrigin(ox, lb.top + lb.height / 2.f);
    txt.setScale(1.f / dpi, 1.f / dpi);
    txt.setPosition(x, centerY);
    t.draw(txt);
    return lb.width / dpi;
}

// The level's traveler index in TRAVELERS (cycling every 12 levels).
inline int travelerIndexForLevel(int lvl) {
    return ((lvl - 1) % TRAVELER_COUNT + TRAVELER_COUNT) % TRAVELER_COUNT;
}

inline bool travelerFlip(int idx) {
    // The Swift image-traveler mirror (xScale = -0.8). Only the stapler glyph
    // ships an image asset in the port; flip + shrink it like the master.
    return TRAVELERS[idx].facesRight;
}

} // namespace

void HUDRenderer::showMessage(const std::string& text, float duration) {
    // Game funnels both the progress text and the PAUSED overlay through here.
    // PAUSED latches (larger MarkerFelt font, no auto-fade-out); the empty string
    // on resume clears it. Everything else is a timed progress crossfade.
    if (text == Message::PAUSED) { showPaused(true); return; }
    if (text.empty()) { showPaused(false); message_.clear(); messageHold_ = 0.f; messageOut_ = true; return; }

    paused_ = false;
    message_ = allCaps(text);
    messageSize_ = 25.72f;
    messageHold_ = duration;
    messageOut_ = false;
    // Fade resumes from wherever it is so back-to-back messages don't pop.
}

void HUDRenderer::showPaused(bool paused) {
    paused_ = paused;
    if (paused) {
        message_ = allCaps(Message::PAUSED);
        messageSize_ = 30.f;
        messageFade_ = 1.f;
        messageHold_ = 0.f;
        messageOut_ = false;
    } else {
        paused_ = false;
        message_.clear();
        messageHold_ = 0.f;
        messageOut_ = true;
    }
}

void HUDRenderer::update(float dt) {
    const float fadeRate = 1.f / 0.3f; // SpriteKit fade = 0.3s
    if (paused_) { messageFade_ = 1.f; return; }

    if (messageHold_ > 0.f) {
        // Crossfade in, then hold for the steady-state duration.
        messageFade_ = std::min(1.f, messageFade_ + dt * fadeRate);
        if (messageFade_ >= 1.f) messageHold_ -= dt;
        if (messageHold_ <= 0.f) { messageHold_ = 0.f; messageOut_ = true; }
    } else if (messageOut_ || messageFade_ > 0.f) {
        messageFade_ = std::max(0.f, messageFade_ - dt * fadeRate);
        if (messageFade_ <= 0.f) { messageFade_ = 0.f; messageOut_ = false; message_.clear(); }
    }
}

void HUDRenderer::draw(sf::RenderTarget& target, float windowWidth, float windowHeight) {
    extraRow = compactHud ? false : (Settings::mazeZoom() <= 100);

    const float W = windowWidth;
    const float top = windowHeight; // SpriteKit `top = size.height`
    const float pad = 12.f;
    const float panelHeight = 89.7f;

    // SpriteKit Y (bottom-left, +Y up) -> SFML Y (top-left, +Y down).
    auto Y = [&](float skY) { return top - skY; };

    // Top-row anchor Y (SpriteKit): 100% floats near the top; 150%/200% centre on
    // the panel. bottomRowY only exists at 100%.
    const float rowY   = extraRow ? (top - 38.f) : (top - 8.f - panelHeight / 2.f);
    const float bottomY = top - 98.f;

    // Panel border/background — only in the camera modes (150%/200%).
    if (!extraRow) {
        // SpriteKit rect: x = pad-5, y = top-panelHeight-8-3, w = width-2*pad+10,
        // h = panelHeight+6. Convert the SK bottom-left rect to an SFML top-left one.
        float rx = pad - 5.f;
        float rw = W - pad * 2.f + 10.f;
        float rh = panelHeight + 6.f;
        float skBottom = top - panelHeight - 8.f - 3.f; // SK y of the rect's bottom edge
        float ry = Y(skBottom + rh);                    // SFML top of the rect
        sf::RectangleShape panel(sf::Vector2f(rw, rh));
        panel.setPosition(rx, ry);
        panel.setFillColor(sf::Color(5, 5, 5, (uint8_t)std::round(0.42f * 255))); // calibratedWhite 0.02 @ 0.42
        panel.setOutlineColor(sf::Color(255, 255, 255, (uint8_t)std::round(0.10f * 255)));
        panel.setOutlineThickness(1.f);
        target.draw(panel);
    }

    const float sfRowY = Y(rowY);

    // Progress / PAUSED crossfade alpha. While the message shows, score/dice/gun/
    // ammo dim to 0.33 and the TPS checklist crossfades out (replaced by the
    // centered MarkerFelt message in the same space).
    const float msgA = messageFade_;
    const float dimA = 1.f - 0.67f * msgA;   // 1.0 -> 0.33
    const float tpsA = 1.f - msgA;           // checklist fades out as message fades in

    // --- 2a. Life icons (Pete) ---------------------------------------------
    const float lifeStartX = pad + 27.05f;   // 39.05
    const float lifeSpacing = 37.f;
    for (int i = 0; i < MAX_LIVES; ++i) {
        if (i >= lives) continue;
        float ix = lifeStartX + i * lifeSpacing;
        peteIcon_.draw(target, {ix, Y(rowY + 1.f)}, false, false, MoveDirection::None, 0.f, 1.f, 1.049f);
    }

    // --- 2b. Dice emoji ----------------------------------------------------
    // SK horizontal .left: drawEmoji centres on pos, so shift right by ~half the
    // glyph box to emulate a left-anchored label.
    {
        float fs = 31.74f;
        drawEmoji(target, EMO_DICE, {pad + 204.f + fs * 0.5f, Y(rowY - 1.f)}, fs,
                  sf::Color(255, 255, 255, (uint8_t)std::round(dimA * 255)));
    }

    // --- 2c. Score ---------------------------------------------------------
    drawLabel(target, menloFont(), std::to_string(score), 31.74f, sf::Color::White,
              pad + 243.f, Y(rowY - 1.f), 0, dimA);

    // --- 2d. TPS checklist (centered, grayed until collected) --------------
    if (tpsA > 0.001f) {
        const float tpsSpacing = 56.13f;
        const float fs = 34.5f;
        int count = (int)Machine::REQUIRED.size();
        for (int i = 0; i < count; ++i) {
            const std::string& name = Machine::REQUIRED[i];
            bool has = reportItems.count(name) > 0;
            float localX = ((float)i - (float)(count - 1) / 2.f) * tpsSpacing;
            float itemA = (has ? 1.0f : 0.4f) * tpsA;
            drawEmoji(target, machineEmoji(name), {W / 2.f + localX, sfRowY}, fs,
                      sf::Color(255, 255, 255, (uint8_t)std::round(itemA * 255)));
        }
    }

    // --- 2i / 4a. Current traveler indicator (top-right) -------------------
    // Container at (W - pad - 24.15, rowY). Only the current level's traveler.
    const float indicatorX = W - pad - 24.15f; // W - 36.15
    {
        int idx = travelerIndexForLevel(level);
        bool flip = travelerFlip(idx);
        // image travelers (the stapler) mirror + shrink 20%; emoji travelers don't.
        float ptSize = 45.18f * (flip ? 0.8f : 1.0f);
        float xOff = flip ? -1.5f : 0.f;
        float yOff = flip ? -2.f : 0.f;
        drawEmoji(target, TRAVELERS[idx].emoji, {indicatorX + xOff, Y(rowY + yOff)}, ptSize,
                  sf::Color::White, flip);
    }

    // --- 4b. Reports / gun / ammo positioned relative to the indicator -----
    const float spacing = 50.2f;
    const float gap = 9.f;
    const float booksReserve = 4.f * 41.07f; // 164.28
    const float groupShift = -8.f;
    const float gunWidth = 41.07f;
    const float indicatorLeft = indicatorX - spacing / 2.f; // W - 61.25
    const float booksRight = indicatorLeft - gap;           // W - 70.25
    const float reportsX = booksRight - 15.5f;              // W - 85.75 (last book anchor)
    const float gunNaturalRight = booksRight - booksReserve - gap - groupShift; // W - 235.53
    const float gunX = gunNaturalRight + 13.f;              // W - 222.53 (right edge of 🔫)
    const float ammoX = gunNaturalRight - gunWidth + 2.f;   // W - 274.6 (right-most dot)
    const float ammoYsk = rowY - 4.f;

    // --- 2e. Report books (right-anchored group, last book at reportsX) ----
    {
        const float bookSpacing = 35.f;
        const float fs = 36.5f;
        int n = 4;
        int shown = tpsReports <= 0 ? 0 : (tpsReports - 1) % n + 1;
        for (int i = 0; i < n; ++i) {
            if (i >= shown) continue;
            float localX = (float)(i - (n - 1)) * bookSpacing; // -105,-70,-35,0
            drawEmoji(target, REPORT_BOOKS[i], {reportsX + localX, sfRowY}, fs);
        }
    }

    // --- 2f / 2g. Water gun + 8 ammo dots ----------------------------------
    // neverPickedUp: hide both. Drawn as shapes (the mono fonts lack ●/○).
    if (waterGunVisible) {
        bool empty = !waterGunActive || waterGunPellets == 0;
        // blueMode (gold disc) = systemBlue @ 0.5; else empty=systemRed, full=systemBlue.
        sf::Color base = goldDiscActive ? sf::Color(10, 122, 255, 128)
                         : (empty ? sf::Color(255, 69, 58) : sf::Color(10, 122, 255));
        base.a = (uint8_t)std::round(base.a * dimA);

        // Gun emoji, SK horizontal .right -> anchor at gunX, shift left by ~half box.
        float gunFs = 36.5f;
        uint8_t gunAlpha = (uint8_t)std::round((goldDiscActive ? 0.5f : (empty ? 0.5f : 1.f)) * dimA * 255);
        drawEmoji(target, EMO_GUN, {gunX - gunFs * 0.5f, sfRowY}, gunFs,
                  sf::Color(255, 255, 255, gunAlpha));

        const float ammoSpacing = 19.f;
        const float r = 28.87f * 0.32f; // dot glyph point size -> shape radius
        float ammoSfY = Y(ammoYsk);
        for (int i = 0; i < WATER_GUN_PELLETS; ++i) {
            float cx = ammoX + (float)(i - 7) * ammoSpacing; // dot 7 at ammoX
            sf::CircleShape dot(r, 24);
            dot.setOrigin(r, r);
            dot.setPosition(cx, ammoSfY);
            if (i < waterGunPellets) {
                dot.setFillColor(base);
            } else {
                dot.setFillColor(sf::Color::Transparent);
                dot.setOutlineColor(base);
                dot.setOutlineThickness(2.f);
            }
            target.draw(dot);
        }
    }

    // --- 3. Bottom row (100% only) -----------------------------------------
    if (extraRow) {
        float sfBottomY = Y(bottomY);

        // 3a. High score (💎 N), left-anchored. The mono font can't rasterize the
        // diamond glyph (it tofu-boxes), so draw it through the emoji texture path
        // like every other HUD glyph, then the number left-anchored after it. The
        // Swift label is "💎 \(highScore)": one glyph box + a space before digits.
        {
            const float fs = 24.84f;
            const float anchorX = lifeStartX - 13.8f;
            drawEmoji(target, EMO_DIAMOND, {anchorX + fs * 0.5f, sfBottomY}, fs);
            drawLabel(target, menloFont(), std::to_string(highScore), fs, sf::Color::White,
                      anchorX + fs + fs * 0.62f, sfBottomY, 0);
        }

        // 3b. Dots counter (zero-padded to the total's width), centered at W/2+3.4.
        std::string totalStr = std::to_string(dotCount);
        std::string dc = std::to_string(collectedDots);
        while (dc.size() < totalStr.size()) dc = "0" + dc;
        float counterX = W / 2.f + 3.4f;
        drawLabel(target, menloFont(), dc, 24.84f, sf::Color::White, counterX, sfBottomY, 1);

        // 3c. Yellow bullet, fixed 9.66 left of the centered counter's left edge.
        // Drawn as a filled circle (the mono font lacks ●). SK position math:
        // charW = 24.84*0.62; halfW = dc.count*charW/2; x = counterX - halfW - 9.66.
        {
            float charW = 24.84f * 0.62f;
            float halfW = (float)dc.size() * charW / 2.f;
            float bx = counterX - halfW - 9.66f;
            float r = 19.32f * 0.34f;
            sf::CircleShape bullet(r, 20);
            bullet.setOrigin(r, r);
            bullet.setPosition(bx - r, sfBottomY); // .right anchor: sit left of bx
            bullet.setFillColor(sf::Color(255, 214, 10)); // systemYellow
            target.draw(bullet);
        }

        // 3d. Bottom traveler accumulation: one glyph per level played, right-
        // anchored so the most recent sits at the container origin.
        float btX = W - pad - 19.32f; // W - 31.32
        const float bottomPointSize = 35.88f;
        const float bottomSpacing = 41.4f;
        int count = std::max(1, level);
        for (int i = 0; i < count; ++i) {
            int idx = travelerIndexForLevel(i + 1);
            bool flip = travelerFlip(idx);
            float ptSize = bottomPointSize * (flip ? 0.8f : 1.0f);
            float xOff = flip ? -2.f : 0.f;
            float yOff = flip ? -2.5f : 0.f;
            float localX = (float)(i - (count - 1)) * bottomSpacing + xOff;
            drawEmoji(target, TRAVELERS[idx].emoji, {btX + localX, Y(bottomY + yOff)}, ptSize,
                      sf::Color::White, flip);
        }
    }

    // --- 2h. Message / PAUSED overlay (centered, MarkerFelt, all-caps) ------
    if (msgA > 0.001f && !message_.empty()) {
        drawLabel(target, markerFeltFont(), message_, messageSize_, sf::Color::White,
                  W / 2.f, sfRowY, 1, msgA);
    }
}

} // namespace bm
