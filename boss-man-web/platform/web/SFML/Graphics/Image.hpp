#pragma once
#include "../System.hpp"
#include "Color.hpp"
#include <vector>
#include <cstring>

namespace sf {

// MARK: - basename helper
// Web assets are preloaded by JS keyed by basename-without-extension. loadFromFile
// strips the directory and extension and looks the asset up by that key.
namespace detail {
inline std::string assetKey(const std::string& path) {
    std::size_t slash = path.find_last_of("/\\");
    std::size_t start = (slash == std::string::npos) ? 0 : slash + 1;
    std::size_t dot = path.find_last_of('.');
    std::size_t end = (dot == std::string::npos || dot < start) ? path.size() : dot;
    return path.substr(start, end - start);
}
}  // namespace detail

// MARK: - Image
// Holds raw RGBA in C++ memory (so getPixel/setPixel/getPixelsPtr work). Decoding
// of encoded files (PNG bytes) can't happen in wasm, so loadFromMemory returns
// false. loadFromFile resolves a preloaded JS image by basename and reads its
// pixels back through the image handle's RGBA via img_* — but since the ABI has no
// pixel-readback, loadFromFile of an Image likewise can't populate CPU pixels; it
// returns false. The game only uses Image for icon bytes / emoji-RGBA create(),
// both of which go through create(); see report notes.
class Image {
public:
    Image() = default;

    void create(unsigned width, unsigned height, const Color& color = Color(0, 0, 0)) {
        m_size = {width, height};
        m_pixels.assign(std::size_t(width) * height * 4, 0);
        for (std::size_t i = 0; i < m_pixels.size(); i += 4) {
            m_pixels[i] = color.r; m_pixels[i + 1] = color.g;
            m_pixels[i + 2] = color.b; m_pixels[i + 3] = color.a;
        }
    }
    void create(unsigned width, unsigned height, const Uint8* pixels) {
        m_size = {width, height};
        std::size_t n = std::size_t(width) * height * 4;
        m_pixels.assign(n, 0);
        if (pixels) std::memcpy(m_pixels.data(), pixels, n);
    }

    bool loadFromFile(const std::string&) { return false; }
    bool loadFromMemory(const void*, std::size_t) { return false; }

    Vector2u getSize() const { return m_size; }
    const Uint8* getPixelsPtr() const { return m_pixels.empty() ? nullptr : m_pixels.data(); }

    Color getPixel(unsigned x, unsigned y) const {
        std::size_t i = (std::size_t(y) * m_size.x + x) * 4;
        if (i + 3 >= m_pixels.size()) return Color();
        return Color(m_pixels[i], m_pixels[i + 1], m_pixels[i + 2], m_pixels[i + 3]);
    }
    void setPixel(unsigned x, unsigned y, const Color& c) {
        std::size_t i = (std::size_t(y) * m_size.x + x) * 4;
        if (i + 3 >= m_pixels.size()) return;
        m_pixels[i] = c.r; m_pixels[i + 1] = c.g; m_pixels[i + 2] = c.b; m_pixels[i + 3] = c.a;
    }

private:
    Vector2u m_size{0, 0};
    std::vector<Uint8> m_pixels;
};

}  // namespace sf
