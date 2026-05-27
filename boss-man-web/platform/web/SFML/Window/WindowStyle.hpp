#pragma once

namespace sf {

// MARK: - Style
// Window decoration flags (ignored on web, the canvas has no chrome). Kept so the
// game's window construction compiles unchanged.
namespace Style {
enum {
    None       = 0,
    Titlebar   = 1 << 0,
    Resize     = 1 << 1,
    Close      = 1 << 2,
    Fullscreen = 1 << 3,
    Default    = Titlebar | Resize | Close
};
}  // namespace Style

// MARK: - ContextSettings
class ContextSettings {
public:
    explicit ContextSettings(unsigned int depth = 0, unsigned int stencil = 0,
                             unsigned int antialiasing = 0, unsigned int major = 1,
                             unsigned int minor = 1, unsigned int attributes = 0,
                             bool sRgb = false)
        : depthBits(depth), stencilBits(stencil), antialiasingLevel(antialiasing),
          majorVersion(major), minorVersion(minor), attributeFlags(attributes), sRgbCapable(sRgb) {}

    unsigned int depthBits;
    unsigned int stencilBits;
    unsigned int antialiasingLevel;
    unsigned int majorVersion;
    unsigned int minorVersion;
    unsigned int attributeFlags;
    bool         sRgbCapable;
};

}  // namespace sf
