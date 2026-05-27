#pragma once
#include "../System.hpp"
#include "Rect.hpp"
#include "Image.hpp"

namespace sf {

// MARK: - Texture
// Thin handle around a JS image (img_* / rt_image). loadFromFile resolves a
// preloaded image by basename. loadFromMemory/loadFromImage can't decode or upload
// pixels through the current ABI, so they return false; the Assets-porting agent
// switches those call sites to loadFromFile (see report). A handle of 0 means
// "not loaded".
class Texture {
public:
    Texture() = default;

    bool loadFromFile(const std::string& path, const IntRect& = IntRect()) {
        std::string key = detail::assetKey(path);
        m_handle = img_by_name(key.c_str(), (int)key.size());
        return m_handle != 0;
    }

    bool loadFromMemory(const void*, std::size_t, const IntRect& = IntRect()) {
        return false;
    }

    bool loadFromImage(const Image& img, const IntRect& = IntRect()) {
        Vector2u sz = img.getSize();
        const Uint8* px = img.getPixelsPtr();
        if (!px || sz.x == 0 || sz.y == 0) return false;
        m_handle = img_from_rgba(px, (int)sz.x, (int)sz.y);
        return m_handle != 0;
    }

    Vector2u getSize() const {
        if (m_handle == 0) return Vector2u(0, 0);
        return Vector2u((unsigned)img_width(m_handle), (unsigned)img_height(m_handle));
    }

    void setSmooth(bool s) { m_smooth = s; }
    bool isSmooth() const { return m_smooth; }
    void setRepeated(bool r) { m_repeated = r; }
    bool isRepeated() const { return m_repeated; }

    int handle() const { return m_handle; }

    void setHandle(int h) { m_handle = h; }

private:
    int  m_handle{0};
    bool m_smooth{false};
    bool m_repeated{false};
};

}  // namespace sf
