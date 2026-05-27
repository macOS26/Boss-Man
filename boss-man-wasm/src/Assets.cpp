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
    sf::Image img;
    if (!img.loadFromFile(path)) return false;
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
