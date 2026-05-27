#include "EmojiText.hpp"
#include "Assets.hpp"
#include <unordered_map>
#include <memory>

namespace bm {

static constexpr int kEmojiBasePx = 64; // CoreText fallback rasterization size

// Lowercase hex of the UTF-8 bytes — matches the filenames produced by
// scripts/extract_emoji.py (e.g. fish 🐟 -> f09f909f.png).
static std::string utf8Hex(const std::string& s) {
    static const char* H = "0123456789abcdef";
    std::string out;
    out.reserve(s.size() * 2);
    for (unsigned char c : s) {
        out.push_back(H[c >> 4]);
        out.push_back(H[c & 0xF]);
    }
    return out;
}

static const sf::Texture* emojiTexture(const std::string& utf8) {
    static std::unordered_map<std::string, std::unique_ptr<sf::Texture>> cache;
    auto it = cache.find(utf8);
    if (it != cache.end()) return it->second.get(); // may be null (tried, unavailable)

    // 1) Bundled PNG extracted from Apple Color Emoji — cross-platform, no CoreText.
    {
        auto tex = std::make_unique<sf::Texture>();
        if (loadTexture(*tex, "assets/emoji/" + utf8Hex(utf8) + ".png")) {
            tex->setSmooth(true);
            const sf::Texture* ptr = tex.get();
            cache.emplace(utf8, std::move(tex));
            return ptr;
        }
    }

    // 2) Fallback: rasterize via the OS text stack (CoreText on macOS).
    std::vector<unsigned char> rgba;
    int w = 0, h = 0;
    if (!platformRenderEmojiRGBA(utf8, kEmojiBasePx, rgba, w, h)) {
        cache.emplace(utf8, nullptr);
        return nullptr;
    }
    sf::Image img;
    img.create((unsigned)w, (unsigned)h, rgba.data());
    auto tex = std::make_unique<sf::Texture>();
    if (!tex->loadFromImage(img)) {
        cache.emplace(utf8, nullptr);
        return nullptr;
    }
    tex->setSmooth(true);
    const sf::Texture* ptr = tex.get();
    cache.emplace(utf8, std::move(tex));
    return ptr;
}

void drawEmoji(sf::RenderTarget& target, const std::string& utf8, sf::Vector2f pos,
               float targetSize, sf::Color color, bool flipX) {
    const sf::Texture* tex = emojiTexture(utf8);
    if (!tex) return; // no bundled PNG and no platform rasterizer

    sf::Sprite sprite(*tex);
    auto sz = tex->getSize();
    sprite.setOrigin(sz.x / 2.f, sz.y / 2.f);
    float s = targetSize / (float)sz.y; // display the glyph box at targetSize tall
    sprite.setScale(flipX ? -s : s, s);
    sprite.setColor(color);
    sprite.setPosition(pos);
    target.draw(sprite);
}

} // namespace bm
