#pragma once
#include <SFML/Graphics.hpp>
#include <string>
#include <vector>

namespace bm {

// SFML's sf::Text cannot rasterize color emoji (Apple Color Emoji etc.): the
// glyphs load but render blank. SpriteKit draws emoji through CoreText (SKLabelNode);
// the equivalent here is to rasterize the glyph to an RGBA buffer with the OS text
// stack and draw it as a textured sprite. This is the platform hook that does that.
// Returns false when no platform implementation is available (caller skips drawing).
bool platformRenderEmojiRGBA(const std::string& utf8, int pixelSize,
                             std::vector<unsigned char>& outRGBA, int& outW, int& outH);

// Draw an emoji centered at pos, scaled to targetSize (≈ point size, like SpriteKit
// fontSize). Textures are cached. color tints/fades (white = true emoji colors).
void drawEmoji(sf::RenderTarget& target, const std::string& utf8, sf::Vector2f pos,
               float targetSize, sf::Color color = sf::Color::White, bool flipX = false);

} // namespace bm
