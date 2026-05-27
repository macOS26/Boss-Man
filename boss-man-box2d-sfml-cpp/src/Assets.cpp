#include "Assets.hpp"

#if defined(BOSS_MAN_WEB)

#include "abi.h"

namespace bm {

// On web, assets are preloaded by runtime.js and resolved by basename. The sf::
// layer's loadFromFile extracts the asset key, so every loader just forwards the
// path; runtime.js maps it to the decoded image/font/sound handle.

bool assetExists(const std::string& path) {
    return asset_exists(path.c_str(), (int)path.size()) != 0;
}

bool loadTexture(sf::Texture& tex, const std::string& path) {
    return tex.loadFromFile(path);
}

bool loadTexturePremultiplied(sf::Texture& tex, const std::string& path) {
    return tex.loadFromFile(path);
}

bool loadFont(sf::Font& font, const std::string& path) {
    return font.loadFromFile(path);
}

bool loadImage(sf::Image& img, const std::string& path) {
    return img.loadFromFile(path);
}

bool loadSoundBuffer(sf::SoundBuffer& buf, const std::string& path) {
    return buf.loadFromFile(path);
}

std::string loadText(const std::string& path) {
    int len = asset_text(path.c_str(), (int)path.size(), nullptr, 0);
    if (len < 0) return {};
    std::string s(len, '\0');
    if (len > 0) asset_text(path.c_str(), (int)path.size(), s.data(), len);
    return s;
}

} // namespace bm

#else

#include <cmrc/cmrc.hpp>

CMRC_DECLARE(bmassets);

namespace bm {

static const cmrc::embedded_filesystem& fs() {
    static cmrc::embedded_filesystem f = cmrc::bmassets::get_filesystem();
    return f;
}

bool assetExists(const std::string& path) {
    return fs().is_file(path);
}

bool loadTexture(sf::Texture& tex, const std::string& path) {
    if (!fs().is_file(path)) return false;
    auto file = fs().open(path);
    return tex.loadFromMemory(file.begin(), file.size());
}

bool loadTexturePremultiplied(sf::Texture& tex, const std::string& path) {
    if (!fs().is_file(path)) return false;
    auto file = fs().open(path);
    sf::Image img;
    if (!img.loadFromMemory(file.begin(), file.size())) return false;
    sf::Vector2u sz = img.getSize();
    for (unsigned y = 0; y < sz.y; ++y) {
        for (unsigned x = 0; x < sz.x; ++x) {
            sf::Color c = img.getPixel(x, y);
            c.r = (sf::Uint8)(c.r * c.a / 255);
            c.g = (sf::Uint8)(c.g * c.a / 255);
            c.b = (sf::Uint8)(c.b * c.a / 255);
            img.setPixel(x, y, c);
        }
    }
    return tex.loadFromImage(img);
}

// Embedded data is static (program-lifetime), so the pointer SFML retains for
// fonts stays valid — unlike a transient heap buffer.
bool loadFont(sf::Font& font, const std::string& path) {
    if (!fs().is_file(path)) return false;
    auto file = fs().open(path);
    return font.loadFromMemory(file.begin(), file.size());
}

bool loadImage(sf::Image& img, const std::string& path) {
    if (!fs().is_file(path)) return false;
    auto file = fs().open(path);
    return img.loadFromMemory(file.begin(), file.size());
}

bool loadSoundBuffer(sf::SoundBuffer& buf, const std::string& path) {
    if (!fs().is_file(path)) return false;
    auto file = fs().open(path);
    return buf.loadFromMemory(file.begin(), file.size());
}

std::string loadText(const std::string& path) {
    if (!fs().is_file(path)) return {};
    auto file = fs().open(path);
    return std::string(file.begin(), file.end());
}

} // namespace bm

#endif
