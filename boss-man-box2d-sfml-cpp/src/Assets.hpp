#pragma once
#include <string>
#include <SFML/Graphics/Texture.hpp>
#include <SFML/Graphics/Font.hpp>
#include <SFML/Audio/SoundBuffer.hpp>

namespace bm {

// Read-only assets are compiled into the binary (see CMRC in CMakeLists). Paths
// are the original "assets/..." strings; nothing is read from disk at runtime.
bool assetExists(const std::string& path);
bool loadTexture(sf::Texture& tex, const std::string& path);
bool loadFont(sf::Font& font, const std::string& path);
bool loadSoundBuffer(sf::SoundBuffer& buf, const std::string& path);
std::string loadText(const std::string& path); // "" if missing

} // namespace bm
