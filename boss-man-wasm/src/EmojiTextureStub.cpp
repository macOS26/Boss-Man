#include "EmojiText.hpp"

namespace bm {

// No OS color-glyph rasterizer on this platform; callers skip emoji drawing.
bool platformRenderEmojiRGBA(const std::string&, int,
                             std::vector<unsigned char>&, int&, int&) {
    return false;
}

} // namespace bm
