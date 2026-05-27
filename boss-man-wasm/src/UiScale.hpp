#pragma once

namespace bm {

// Global UI/text scale = the window's Retina backing factor (2.0 on HiDPI). SFML
// renders shapes at the native backing resolution but font glyph atlases are
// rasterized at their character size, so on Retina they get magnified and blur.
// Text helpers rasterize at characterSize * uiScale() and then setScale(1/uiScale())
// so glyphs land 1:1 on backing pixels and stay crisp. Set once at window creation.
inline float& uiScale() {
    static float s = 1.0f;
    return s;
}

} // namespace bm
