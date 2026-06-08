#pragma once
#include "Transform.hpp"
#include "BlendMode.hpp"

namespace sf {

class Texture;
class Shader;

// MARK: - RenderStates
class RenderStates {
public:
    RenderStates() = default;
    RenderStates(const BlendMode& bm) : blendMode(bm) {}
    RenderStates(const Transform& t) : transform(t) {}
    RenderStates(const Texture* tex) : texture(tex) {}
    RenderStates(const BlendMode& bm, const Transform& t,
                 const Texture* tex, const Shader* sh)
        : blendMode(bm), transform(t), texture(tex), shader(sh) {}

    BlendMode      blendMode = BlendMode();
    Transform      transform = Transform();
    const Texture* texture = nullptr;
    const Shader*  shader = nullptr;

    static const RenderStates Default;
};

}  // namespace sf
