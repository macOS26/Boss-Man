#pragma once
#include "../System.hpp"
#include "Color.hpp"

namespace sf {

// MARK: - PrimitiveType
// SFML 2.6 primitive kinds. Quads is what the games batch (dot pellets); the
// triangle kinds are handled too so any future batched geometry just works.
enum PrimitiveType {
    Points,
    Lines,
    LineStrip,
    Triangles,
    TriangleStrip,
    TriangleFan,
    Quads,
    LinesStrip     = LineStrip,      // deprecated SFML 2.x aliases
    TrianglesStrip = TriangleStrip,
    TrianglesFan   = TriangleFan
};

// MARK: - Vertex
// A point with a color and texture coords. The web backend fills flat-shaded
// polygons (one color per primitive), so texCoords are carried for API
// compatibility but not sampled, and a primitive takes its first vertex's color.
class Vertex {
public:
    Vector2f position;
    Color    color;
    Vector2f texCoords;

    Vertex() : position(0.f, 0.f), color(Color::White), texCoords(0.f, 0.f) {}
    Vertex(const Vector2f& pos) : position(pos), color(Color::White), texCoords(0.f, 0.f) {}
    Vertex(const Vector2f& pos, const Color& col) : position(pos), color(col), texCoords(0.f, 0.f) {}
    Vertex(const Vector2f& pos, const Vector2f& tex) : position(pos), color(Color::White), texCoords(tex) {}
    Vertex(const Vector2f& pos, const Color& col, const Vector2f& tex) : position(pos), color(col), texCoords(tex) {}
};

}  // namespace sf
