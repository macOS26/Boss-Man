#include "Assets.hpp"
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

// Embedded data is static (program-lifetime), so the pointer SFML retains for
// fonts stays valid — unlike a transient heap buffer.
bool loadFont(sf::Font& font, const std::string& path) {
    if (!fs().is_file(path)) return false;
    auto file = fs().open(path);
    return font.loadFromMemory(file.begin(), file.size());
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
