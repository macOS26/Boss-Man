#include "TitleScreen.hpp"
#include "UiScale.hpp"
#include "Assets.hpp"
#include "EmojiText.hpp"
#include "Settings.hpp"
#include "PixelPersonRenderer.hpp"
#include <algorithm>
#include <cmath>
#include <string>

namespace bm {

namespace {
// halign: 0=left, 1=center, 2=right. Always vertically centered at (x,y).
// Rasterized at size*uiScale and counter-scaled so it stays crisp on Retina.
sf::FloatRect drawText(sf::RenderTarget& t, const sf::Font& f, const std::string& s, unsigned size,
              sf::Color color, float x, float y, int halign = 1,
              float rotationDeg = 0.f, uint8_t alpha = 255, const char* baselineRef = nullptr,
              bool vCenter = false) {
    float dpi = uiScale();
    sf::Text txt;
    txt.setFont(f);
    txt.setString(sf::String::fromUtf8(s.begin(), s.end())); // interpret bytes as UTF-8
    txt.setCharacterSize((unsigned)(size * dpi));
    color.a = alpha;
    txt.setFillColor(color);
    auto lb = txt.getLocalBounds();
    float ox = (halign == 0) ? 0.f : (halign == 2 ? lb.left + lb.width : lb.left + lb.width / 2.f);
    // SpriteKit SKLabelNode uses baseline vertical alignment by default: the node's
    // y is the text baseline and glyphs sit above it. Anchor on the bounding-box
    // bottom, which equals the baseline for all-caps labels. Pass baselineRef to
    // anchor on a MASTER string's baseline instead, so sibling labels (the
    // "(P)lay"/"(E)ditor" buttons) share "(E)ditor"'s baseline rather than each
    // drifting by its own descender.
    float oy = vCenter ? (lb.top + lb.height / 2.f) : (lb.top + lb.height);
    if (baselineRef) {
        sf::Text ref;
        ref.setFont(f);
        ref.setString(std::string(baselineRef));
        ref.setCharacterSize((unsigned)(size * dpi));
        auto rb = ref.getLocalBounds();
        oy = vCenter ? (rb.top + rb.height / 2.f) : (rb.top + rb.height);
    }
    txt.setOrigin(ox, oy);
    txt.setScale(1.f / dpi, 1.f / dpi);
    txt.setPosition(x, y);
    txt.setRotation(rotationDeg);
    t.draw(txt);
    return txt.getGlobalBounds();
}
} // namespace

namespace {
// Signed distance from point (px,py) to a rounded rectangle centered at origin.
float sdRoundRect(float px, float py, float halfW, float halfH, float r) {
    float qx = std::abs(px) - (halfW - r);
    float qy = std::abs(py) - (halfH - r);
    float outside = std::sqrt(std::max(qx, 0.f) * std::max(qx, 0.f) +
                              std::max(qy, 0.f) * std::max(qy, 0.f));
    float inside = std::min(std::max(qx, qy), 0.f);
    return outside + inside - r;
}

// Rounded rect matching SKShapeNode(rect:cornerRadius:): a filled convex body with
// a stroked border drawn over it. Anti-aliased by the window's 8x MSAA context.
void drawRoundedRect(sf::RenderTarget& t, const sf::FloatRect& r, float radius,
                     sf::Color fill, sf::Color stroke, float lineWidth) {
    const int seg = 8; // arc subdivisions per corner
    float x0 = r.left, y0 = r.top, x1 = r.left + r.width, y1 = r.top + r.height;
    float rad = std::min(radius, std::min(r.width, r.height) * 0.5f);
    struct C { float cx, cy, a0; };
    const C corners[4] = {
        {x1 - rad, y1 - rad, 0.f},                          // bottom-right
        {x0 + rad, y1 - rad, (float)M_PI / 2.f},            // bottom-left
        {x0 + rad, y0 + rad, (float)M_PI},                  // top-left
        {x1 - rad, y0 + rad, (float)M_PI * 1.5f},           // top-right
    };
    sf::ConvexShape body;
    body.setPointCount((seg + 1) * 4);
    int p = 0;
    for (const C& c : corners) {
        for (int i = 0; i <= seg; ++i) {
            float a = c.a0 + (float)M_PI / 2.f * (float)i / (float)seg;
            body.setPoint(p++, sf::Vector2f(c.cx + std::cos(a) * rad, c.cy + std::sin(a) * rad));
        }
    }
    body.setFillColor(fill);
    t.draw(body);
    if (lineWidth > 0.f && stroke.a > 0) {
        sf::ConvexShape border = body;
        border.setFillColor(sf::Color::Transparent);
        border.setOutlineColor(stroke);
        border.setOutlineThickness(lineWidth);
        t.draw(border);
    }
}
} // namespace

void TitleScreen::ensureLoaded() {
    if (loaded_) return;
    loaded_ = true;
    loadFont(fontWide_, "assets/fonts/MarkerFelt-Wide.ttf");
    loadFont(fontThin_, "assets/fonts/MarkerFelt-Thin.ttf");
    loadFont(fontMono_, "assets/fonts/JetBrainsMono-Bold.ttf");
    staplerLoaded_ = loadTexturePremultiplied(stapler_, "assets/images/red-stapler.png");
    if (staplerLoaded_) stapler_.setSmooth(true);

    // Build a soft drop-shadow texture once: a rounded rect with a feathered alpha
    // falloff (a cheap Gaussian-like blur). Panel is 320x400. Tuned light + wide to read
    // like the wasm/Xcode soft shadow (0.24 black, CIGaussianBlur 12.5 + framework softening).
    const float feather = 21.f, baseAlpha = 36.f, radius = 12.f;
    // Inset ~5px inside the 320x400 panel so the feathered halo tucks behind the
    // post-it on the sides/top; the 5px-down draw offset lets it read as a drop shadow.
    const float halfW = 155.f, halfH = 195.f;
    int texW = (int)(halfW * 2 + feather * 2);
    int texH = (int)(halfH * 2 + feather * 2);
    sf::Image img;
    img.create((unsigned)texW, (unsigned)texH, sf::Color(0, 0, 0, 0));
    float cx = texW / 2.f, cy = texH / 2.f;
    for (int y = 0; y < texH; ++y) {
        for (int x = 0; x < texW; ++x) {
            float sd = sdRoundRect(x + 0.5f - cx, y + 0.5f - cy, halfW, halfH, radius);
            float tt = std::clamp(sd / feather, 0.f, 1.f);
            float a = baseAlpha * (1.f - tt * tt * (3.f - 2.f * tt)); // smoothstep falloff
            if (a > 0.f) img.setPixel((unsigned)x, (unsigned)y, sf::Color(0, 0, 0, (uint8_t)a));
        }
    }
    panelShadow_.loadFromImage(img);
    panelShadow_.setSmooth(true);
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
    const float panelCY = H * 0.5f - 20.f;
    const float panelLeft = panelCX - panelW / 2.f;
    const float panelTop = panelCY - panelH / 2.f;

    // Soft, feathered drop shadow (pre-rendered texture), offset down-right.
    {
        sf::Sprite sh(panelShadow_);
        auto ss = panelShadow_.getSize();
        sh.setOrigin(ss.x / 2.f, ss.y / 2.f);
        sh.setPosition(panelCX, panelCY + 3.f);
        target.draw(sh);
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
    drawText(target, fontWide_, "LEADERBOARD", 24, sf::Color(46, 26, 10), panelCX, headerY + 2.f, 1);
    sf::RectangleShape underline(sf::Vector2f(panelW - 44.f, 2.f));
    underline.setFillColor(sf::Color(0, 0, 0, 102)); // alpha 0.40
    underline.setPosition(panelLeft + 22.f, headerY + 14.f);
    target.draw(underline);

    // Entries (or a placeholder when empty)
    if (board.empty()) {
        drawText(target, fontThin_, "No local scores yet.", 18, sf::Color(0, 0, 0, 178),
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

    // --- Credit (SpriteKit y = height*0.95 - 15, top-left flipped) ---
    drawText(target, fontThin_, "Game Design by Todd Bruss", 24, ink, W / 2.f, H * 0.05f + 15.f, 1);

    // --- Red stapler, fit to ~290px, tilted (zRotation -0.06) ---
    if (staplerLoaded_) {
        sf::Sprite sp(stapler_);
        auto ts = stapler_.getSize();
        float fit = 290.f / (float)std::max(ts.x, ts.y);
        sp.setOrigin(ts.x / 2.f, ts.y / 2.f);
        sp.setScale(fit, fit);
        sp.setRotation(3.4f);
        // SpriteKit centers the stapler sprite at height*0.46 + 8 (i.e. 0.54 from top, raised 8px).
        sp.setPosition(W / 2.f, H * 0.54f - 8.f);
        // Premultiplied blend (texture is premultiplied) — clean edges over the
        // yellow background instead of a gray fringe from straight-alpha scaling.
        target.draw(sp, sf::RenderStates(sf::BlendMode(sf::BlendMode::One, sf::BlendMode::OneMinusSrcAlpha)));
    }

    // --- PLAY / EDITOR title buttons (makeTitleButton) ---
    // SpriteKit (y-up): rounded fill dimmed 30% toward black + white 0.55 border,
    // 42pt emoji icon left, white Marker Felt Wide label left of it. promptY is
    // size.height*0.15+20 from the bottom; SFML is y-down so flip about H.
    {
        const sf::Color border(255, 255, 255, 140); // SKColor(white:1, alpha:0.55)
        const float bw = 240.f, bh = 52.f, gap = 28.f;
        const float yc = H - (H * 0.15f + 20.f);
        // makeTitleButton: textDY is a y-up offset → subtract in SFML.
        auto button = [&](float cx, sf::Color fill, const char* emoji,
                          const char* label, float textDY) -> sf::FloatRect {
            sf::FloatRect r(cx - bw / 2.f, yc - bh / 2.f, bw, bh);
            drawRoundedRect(target, r, 12.f, fill, border, 2.f);
            float ly = yc - textDY;
            drawEmoji(target, emoji, sf::Vector2f(cx - bw / 2.f + 40.f, ly), 42.f);
            drawText(target, fontWide_, label, 34, sf::Color::White,
                     cx - bw / 2.f + 84.f, ly, 0, 0.f, 255, "EDITOR", true);
            return r;
        };
        playRect_   = button(W / 2.f - bw / 2.f - gap / 2.f, sf::Color(33, 157, 64),
                             "\xf0\x9f\x95\xb9\xef\xb8\x8f", "PLAY", -1.f);   // 🕹️ systemGreen
        editorRect_ = button(W / 2.f + bw / 2.f + gap / 2.f, sf::Color(0, 108, 192),
                             "\xe2\x9c\x8f\xef\xb8\x8f", "EDITOR", 0.f);      // ✏️ systemBlue
    }

    // --- High score ---
    if (highScore > 0) {
        drawText(target, fontThin_, "HIGH SCORE " + std::to_string(highScore), 26, ink,
                 W / 2.f, H * 0.94f - 10.f, 1);
    }

    // --- Controls hint, bottom-center, HUD mono font ---
    drawText(target, fontMono_, "Cursor key to Move \xC2\xB7 Space to Fire Water Pistol", 16, ink,
             W / 2.f, H - 18.f, 1);

    // --- Five side toggle buttons (makeHint) ---
    // Rounded fill dimmed 30% toward black + white 0.55 border, a fixed-position
    // 42pt emoji icon, and the left-aligned ALL-CAPS value in Marker Felt Wide
    // (white). Fixed icon/value offsets mean a value change never re-centres the
    // row (no jump). Right column hugs the right edge; left column hugs the left.
    // SpriteKit y (40/114/188) is from the bottom; SFML is y-down so flip about H.
    {
        const sf::Color border(255, 255, 255, 140); // SKColor(white:1, alpha:0.55)
        const float btnW = 292.f, btnH = 50.f, margin = 16.f;
        const float cxRight = W - margin - btnW / 2.f;
        const float cxLeft = margin + btnW / 2.f;
        auto hint = [&](float cx, float ySK, sf::Color fill, const char* emoji,
                        const std::string& value, bool bossIcon = false) -> sf::FloatRect {
            float yc = H - ySK;
            sf::FloatRect r(cx - btnW / 2.f, yc - btnH / 2.f, btnW, btnH);
            drawRoundedRect(target, r, 12.f, fill, border, 2.f);
            if (bossIcon) {
                const BossBlueprint& bp = BOSS_BLUEPRINTS[1];   // Dom = the pink boss
                PersonConfig cfg;
                cfg.bodyColor = bp.bodyColor;
                cfg.tieColor = bp.tieColor;
                cfg.hairColor = BOSS_HAIR;
                cfg.shoeOutlineColor = BOSS_SHOE_GOLD;
                cfg.pantsColor = bp.pantsColor;
                cfg.headYOffset = 1.0f;
                PixelPersonRenderer boss(cfg);
                auto m = boss.metrics();
                float sc = 42.f / m.height;
                float ox = cx - btnW / 2.f + 38.f;
                float oy = yc - (m.feetOffset - m.headOffset) / 2.f * sc;
                boss.draw(target, sf::Vector2f(ox, oy), false, false, MoveDirection::None, 0.f, 1.f, sc);
            } else {
                drawEmoji(target, emoji, sf::Vector2f(cx - btnW / 2.f + 38.f, yc), 42.f);
            }
            drawText(target, fontWide_, value, 32, sf::Color::White,
                     cx - btnW / 2.f + 80.f, yc, 0, 0.f, 255, "WINDOW", true);
            return r;
        };
        fullscreenRect_ = hint(cxRight, 40.f, sf::Color(192, 47, 50),
            "\xf0\x9f\x93\xba", "FULLSCREEN");                           // 📺 systemRed
        windowRect_     = hint(cxRight, 114.f, sf::Color(0, 157, 168),
            "\xf0\x9f\xaa\x9f", "WINDOW");                               // 🪟 systemTeal
        mazeZoomRect_   = hint(cxRight, 188.f, sf::Color(164, 41, 182),
            "", MazeZoom::label(), true);                               // pink boss (Dom) icon, systemPurple
        bossTracksRect_ = hint(cxLeft, 40.f, sf::Color(80, 92, 192),
            "\xf0\x9f\x91\xbb", Settings::bossTracksSquare() ? "HUNTER" : "SPEEDY"); // 👻 systemIndigo
        waterGunRect_   = hint(cxLeft, 114.f, sf::Color(192, 108, 33),
            "\xf0\x9f\x94\xab",                                          // 🔫 systemOrange
            Settings::waterGunHide() ? "HIDDEN" : (Settings::waterGunLeft() ? "LEFT" : "RIGHT"));
    }
}

TitleScreen::Hit TitleScreen::hitTest(float x, float y) const {
    // Whole button is tappable: each rect is the button's full container frame
    // (matches SpriteKit calculateAccumulatedFrame), so hit-test the rect directly.
    auto in = [&](const sf::FloatRect& r) { return r.contains(x, y); };
    if (in(playRect_))        return Hit::Play;
    if (in(editorRect_))      return Hit::Editor;
    if (in(bossTracksRect_))  return Hit::BossTracks;
    if (in(waterGunRect_))    return Hit::WaterGun;
    if (in(mazeZoomRect_))    return Hit::MazeZoom;
    if (in(fullscreenRect_))  return Hit::Fullscreen;
    if (in(windowRect_))      return Hit::Window;
    return Hit::None;
}

} // namespace bm
