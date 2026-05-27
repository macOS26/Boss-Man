#pragma once
#include "../System.hpp"
#include "../../abi.h"

namespace sf {

// MARK: - VideoMode
class VideoMode {
public:
    VideoMode() = default;
    VideoMode(unsigned int width, unsigned int height, unsigned int bpp = 32)
        : width(width), height(height), bitsPerPixel(bpp) {}

    static VideoMode getDesktopMode() {
        return VideoMode((unsigned)win_width(), (unsigned)win_height(), 32);
    }

    bool isValid() const { return width > 0 && height > 0; }

    unsigned int width{0};
    unsigned int height{0};
    unsigned int bitsPerPixel{32};
};

}  // namespace sf
