#pragma once
#include "../System.hpp"
#include "Image.hpp"

namespace sf {

// MARK: - Font
// On web, text is drawn by Canvas2D fillText (gfx_draw_text/txt_width) using a font
// resolved by name; loadFromFile resolves a preloaded font by basename. There is no
// glyph atlas in C++, so loadFromMemory returns false (the Assets-porting agent
// switches font loads to loadFromFile). A handle of 0 means the default font.
class Font {
public:
    Font() = default;

    bool loadFromFile(const std::string& path) {
        std::string key = detail::assetKey(path);
        m_handle = font_by_name(key.c_str(), (int)key.size());
        return m_handle != 0;
    }
    bool loadFromMemory(const void*, std::size_t) { return false; }

    int handle() const { return m_handle; }

private:
    int m_handle{0};
};

}  // namespace sf
