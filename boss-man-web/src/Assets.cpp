#include "Assets.hpp"
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
