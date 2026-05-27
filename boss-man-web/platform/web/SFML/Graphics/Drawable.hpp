#pragma once
#include "RenderStates.hpp"

namespace sf {

class RenderTarget;

// MARK: - Drawable
// SFML's abstract drawable. On the web backend every concrete drawable lowers
// itself to gfx_* calls inside draw(); RenderTarget::draw simply forwards to it.
class Drawable {
public:
    virtual ~Drawable() = default;

protected:
    friend class RenderTarget;
    virtual void draw(RenderTarget& target, RenderStates states) const = 0;
};

}  // namespace sf
