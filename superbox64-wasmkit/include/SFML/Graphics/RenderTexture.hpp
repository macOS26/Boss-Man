#pragma once
#include "../System.hpp"
#include "RenderTarget.hpp"
#include "Texture.hpp"
#include "../Window/WindowStyle.hpp"

namespace sf {

// MARK: - RenderTexture
// Offscreen draw surface. create(w,h) mints a target handle via rt_create; the
// backing image (rt_image) is wrapped in a Texture returned by getTexture().
// display() is a no-op (the canvas backend has no flush step).
class RenderTexture : public RenderTarget {
public:
    RenderTexture() = default;

    bool create(unsigned int width, unsigned int height, const ContextSettings& = ContextSettings()) {
        m_size = {width, height};
        m_target = rt_create((int)width, (int)height);
        if (m_target <= 0) return false;
        m_texture.setHandle(rt_image(m_target));
        return true;
    }

    bool create(unsigned int width, unsigned int height, bool) { return create(width, height); }

    void setSmooth(bool s) { m_texture.setSmooth(s); }
    bool isSmooth() const { return m_texture.isSmooth(); }
    void setRepeated(bool r) { m_texture.setRepeated(r); }
    bool isRepeated() const { return m_texture.isRepeated(); }

    void display() {}

    const Texture& getTexture() const { return m_texture; }
    Vector2u getSize() const override { return m_size; }

private:
    Vector2u m_size{0, 0};
    Texture  m_texture;
};

}  // namespace sf
