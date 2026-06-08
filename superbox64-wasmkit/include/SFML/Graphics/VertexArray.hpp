#pragma once
#include "../System.hpp"
#include "Vertex.hpp"
#include "Drawable.hpp"
#include "RenderStates.hpp"
#include "RenderTarget.hpp"
#include "Rect.hpp"
#include <vector>
#include <cstddef>
#include <initializer_list>

namespace sf {

// MARK: - VertexArray
// A growable set of vertices drawn as one primitive batch. The web backend has no
// vertex pipeline, so draw() decomposes the batch into flat-shaded polygons via
// gfx_fill_poly (each primitive uses its first vertex's color). Points/Lines are
// not emitted (the games only batch filled Quads/Triangles).
class VertexArray : public Drawable {
public:
    VertexArray() = default;
    explicit VertexArray(PrimitiveType type, std::size_t vertexCount = 0)
        : m_primitiveType(type), m_vertices(vertexCount) {}

    std::size_t   getVertexCount() const { return m_vertices.size(); }
    Vertex&       operator[](std::size_t i)       { return m_vertices[i]; }
    const Vertex& operator[](std::size_t i) const { return m_vertices[i]; }
    void clear()                  { m_vertices.clear(); }
    void resize(std::size_t n)    { m_vertices.resize(n); }
    void append(const Vertex& v)  { m_vertices.push_back(v); }
    void setPrimitiveType(PrimitiveType t) { m_primitiveType = t; }
    PrimitiveType getPrimitiveType() const { return m_primitiveType; }

    FloatRect getBounds() const {
        if (m_vertices.empty()) return FloatRect();
        float minX = m_vertices[0].position.x, maxX = minX;
        float minY = m_vertices[0].position.y, maxY = minY;
        for (const auto& v : m_vertices) {
            minX = v.position.x < minX ? v.position.x : minX;
            maxX = v.position.x > maxX ? v.position.x : maxX;
            minY = v.position.y < minY ? v.position.y : minY;
            maxY = v.position.y > maxY ? v.position.y : maxY;
        }
        return FloatRect(minX, minY, maxX - minX, maxY - minY);
    }

    void draw(RenderTarget& target, RenderStates states) const override {
        if (m_vertices.empty()) return;
        target.beginDraw(states);
        const std::size_t n = m_vertices.size();
        auto fill = [&](std::initializer_list<std::size_t> idx) {
            float xy[8];
            int k = 0;
            for (std::size_t i : idx) {
                xy[k * 2]     = m_vertices[i].position.x;
                xy[k * 2 + 1] = m_vertices[i].position.y;
                ++k;
            }
            gfx_fill_poly(xy, k, m_vertices[*idx.begin()].color.toInteger());
        };
        switch (m_primitiveType) {
            case Quads:
                for (std::size_t i = 0; i + 4 <= n; i += 4) fill({i, i + 1, i + 2, i + 3});
                break;
            case Triangles:
                for (std::size_t i = 0; i + 3 <= n; i += 3) fill({i, i + 1, i + 2});
                break;
            case TriangleStrip:
                for (std::size_t i = 0; i + 3 <= n; ++i) fill({i, i + 1, i + 2});
                break;
            case TriangleFan:
                for (std::size_t i = 1; i + 1 < n; ++i) fill({(std::size_t)0, i, i + 1});
                break;
            default:
                break;
        }
        target.endDraw();
    }

private:
    PrimitiveType       m_primitiveType{Points};
    std::vector<Vertex> m_vertices;
};

}  // namespace sf
