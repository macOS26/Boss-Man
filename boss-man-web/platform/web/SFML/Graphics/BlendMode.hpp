#pragma once
#include "../System.hpp"

namespace sf {

// MARK: - BlendMode
// Mirrors the SFML 2.6 factor/equation enums so source compiles unchanged. The
// web backend only distinguishes a handful of modes (gfx_set_blend takes 0 alpha,
// 1 add, 2 multiply, 3 none); RenderTarget maps a BlendMode to one of those by
// matching the common SFML presets.
class BlendMode {
public:
    enum Factor {
        Zero,
        One,
        SrcColor,
        OneMinusSrcColor,
        DstColor,
        OneMinusDstColor,
        SrcAlpha,
        OneMinusSrcAlpha,
        DstAlpha,
        OneMinusDstAlpha
    };

    enum Equation {
        Add,
        Subtract,
        ReverseSubtract,
        Min,
        Max
    };

    BlendMode()
        : colorSrcFactor(SrcAlpha), colorDstFactor(OneMinusSrcAlpha), colorEquation(Add),
          alphaSrcFactor(One), alphaDstFactor(OneMinusSrcAlpha), alphaEquation(Add) {}

    BlendMode(Factor srcFactor, Factor dstFactor, Equation eq = Add)
        : colorSrcFactor(srcFactor), colorDstFactor(dstFactor), colorEquation(eq),
          alphaSrcFactor(srcFactor), alphaDstFactor(dstFactor), alphaEquation(eq) {}

    BlendMode(Factor colorSrc, Factor colorDst, Equation colorEq,
              Factor alphaSrc, Factor alphaDst, Equation alphaEq)
        : colorSrcFactor(colorSrc), colorDstFactor(colorDst), colorEquation(colorEq),
          alphaSrcFactor(alphaSrc), alphaDstFactor(alphaDst), alphaEquation(alphaEq) {}

    Factor   colorSrcFactor;
    Factor   colorDstFactor;
    Equation colorEquation;
    Factor   alphaSrcFactor;
    Factor   alphaDstFactor;
    Equation alphaEquation;

    bool operator==(const BlendMode& o) const {
        return colorSrcFactor == o.colorSrcFactor && colorDstFactor == o.colorDstFactor &&
               colorEquation == o.colorEquation && alphaSrcFactor == o.alphaSrcFactor &&
               alphaDstFactor == o.alphaDstFactor && alphaEquation == o.alphaEquation;
    }
    bool operator!=(const BlendMode& o) const { return !(*this == o); }
};

extern const BlendMode BlendAlpha;
extern const BlendMode BlendAdd;
extern const BlendMode BlendMultiply;
extern const BlendMode BlendNone;

// MARK: - web blend lowering
// Returns the gfx_set_blend code (0 alpha, 1 add, 2 multiply, 3 none) for a mode.
inline int webBlendCode(const BlendMode& bm) {
    if (bm.colorSrcFactor == BlendMode::One && bm.colorDstFactor == BlendMode::One)
        return 1;
    if (bm.colorSrcFactor == BlendMode::DstColor && bm.colorDstFactor == BlendMode::Zero)
        return 2;
    if (bm.colorSrcFactor == BlendMode::One && bm.colorDstFactor == BlendMode::Zero)
        return 3;
    return 0;
}

}  // namespace sf
