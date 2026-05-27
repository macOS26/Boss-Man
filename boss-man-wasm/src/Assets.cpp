#include "Assets.hpp"
#include <fstream>
#include <sstream>

namespace bm {

bool assetExists(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return f.good();
}

bool loadTexture(sf::Texture& tex, const std::string& path) {
    return tex.loadFromFile(path);
}

bool loadTexturePremultiplied(sf::Texture& tex, const std::string& path) {
    return loadTexture(tex, path);
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
    std::ifstream f(path, std::ios::binary);
    if (!f.good()) return {};
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

} // namespace bm
