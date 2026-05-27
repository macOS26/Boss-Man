#pragma once
#include <SFML/Graphics.hpp>
#include "Constants.hpp"
#include <string>
#include <vector>

namespace bm {

class GridMap {
public:
    float tileSize = TILE_SIZE;
    float yOffset = 0.0f;
    std::vector<std::string> rows;

    GridMap() = default;
    GridMap(float ts, const std::vector<std::string>& r = {})
        : tileSize(ts), rows(r) { rebuildTunnels(); }

    void setRows(const std::vector<std::string>& r) {
        rows = r;
        rebuildTunnels();
    }

    sf::Vector2f pointFor(GridPos grid) const {
        // SFML Y-down: grid y=0 (bottom row) maps to bottom of maze area
        // grid y=GRID_ROWS-1 (top row) maps to top of maze area
        float pixelY = yOffset + (GRID_ROWS - 1 - grid.y) * tileSize + tileSize / 2.0f;
        return {grid.x * tileSize + tileSize / 2.0f, pixelY};
    }

    char tileAt(GridPos grid) const {
        int row = (int)rows.size() - 1 - grid.y;
        int col = grid.x;
        if (row < 0 || row >= (int)rows.size() || col < 0 || col >= (int)rows[row].size())
            return '\0';
        return rows[row][col];
    }

    bool isWalkable(GridPos grid) const {
        char c = tileAt(grid);
        return c != '\0' && c != Tile::wall;
    }

    GridPos tunnelPartner(GridPos grid) const {
        for (auto& [a, b] : tunnelPairs) {
            if (a == grid) return b;
            if (b == grid) return a;
        }
        return {-1, -1};
    }

    bool hasTunnelPartner(GridPos grid) const {
        for (auto& [a, b] : tunnelPairs) {
            if (a == grid || b == grid) return true;
        }
        return false;
    }

    bool isHideout(GridPos grid) const {
        return tileAt(grid) == Tile::hideout;
    }

    std::vector<GridPos> walkableNeighbors(GridPos grid) const {
        std::vector<GridPos> result;
        int dx[] = {1, -1, 0, 0};
        int dy[] = {0, 0, 1, -1};
        for (int i = 0; i < 4; ++i) {
            GridPos next = {grid.x + dx[i], grid.y + dy[i]};
            if (isWalkable(next) && !isHideout(next))
                result.push_back(next);
        }
        GridPos partner = tunnelPartner(grid);
        if (partner.x >= 0 && isWalkable(partner) && !isHideout(partner))
            result.push_back(partner);
        return result;
    }

private:
    std::vector<std::pair<GridPos, GridPos>> tunnelPairs;

    void rebuildTunnels() {
        tunnelPairs.clear();
        if (rows.empty() || rows[0].empty() || rows.size() < 2) return;
        int rowCount = (int)rows.size();
        int colCount = (int)rows[0].size();
        int topY = rowCount - 1;
        int lastCol = colCount - 1;

        // Top-bottom vertical tunnels
        for (int col = 0; col < colCount; ++col) {
            if (col < (int)rows[0].size() && col < (int)rows[rowCount-1].size()) {
                if (rows[0][col] == Tile::floor && rows[rowCount-1][col] == Tile::floor) {
                    tunnelPairs.push_back({{col, topY}, {col, 0}});
                }
            }
        }
        // Left-right horizontal tunnels
        for (int rowIdx = 0; rowIdx < rowCount; ++rowIdx) {
            auto& row = rows[rowIdx];
            if ((int)row.size() >= colCount && row[0] == Tile::floor && row[lastCol] == Tile::floor) {
                int gridY = rowCount - 1 - rowIdx;
                tunnelPairs.push_back({{0, gridY}, {lastCol, gridY}});
            }
        }
    }
};

} // namespace bm

// Hash for GridPos
namespace std {
template<> struct hash<bm::GridPos> {
    size_t operator()(const bm::GridPos& g) const {
        return g.x * 1000 + g.y;
    }
};
}