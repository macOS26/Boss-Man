#pragma once
#include <SFML/Graphics.hpp>
#include "GridMap.hpp"
#include "Constants.hpp"
#include <vector>

namespace bm {

class MazeRenderer {
public:
    const GridMap& map;
    Color cubicleColor = CUBICLE_COLORS[0];

    // Dot tracking
    std::vector<std::vector<bool>> dotPresence;
    int dotCount = 0;

    // Spawn info from map
    GridPos workerSpawnFromMap = {-1, -1};
    std::vector<std::pair<int, GridPos>> bossSpawnsFromMap;
    std::vector<GridPos> goldDiscPositionsFromMap;
    std::vector<GridPos> waterGunPositionsFromMap;
    std::vector<GridPos> waterPelletPositionsFromMap;

    // Pickup entities
    struct Pickup {
        GridPos grid;
        sf::Vector2f pixelPos;
        char type; // 'O', 'G', 'A', 'P', 'F', 'C', 'M', 'D'
        std::string machineName;
        bool active = true;
        float cooldownTimer = 0.0f; // machines: dim + uncollectable while > 0
    };
    std::vector<Pickup> pickups;
    int placedGoldDiscs = 0;

    sf::RenderTexture backgroundTexture;
    sf::Sprite backgroundSprite;
    sf::Clock animClock; // absolute-time source for pickup throb
    // All pellet dots batched into ONE VertexArray -> a single draw call per
    // frame (matches the apple master's single SKTileMapNode, vs the old
    // per-dot sf::RectangleShape draw loop). Eaten dots collapse to a zero-area
    // quad so they stop drawing entirely.
    sf::VertexArray dotVerts{sf::Quads};
    std::unordered_map<int, int> dotGridToQuad; // key: rowIndex*1000+col -> quad ordinal

    MazeRenderer(const GridMap& m) : map(m) {}

    int build();
    void drawBackground(sf::RenderTarget& target);
    void drawDots(sf::RenderTarget& target, float dt);
    void drawPickups(sf::RenderTarget& target, float dt);
    bool collectDot(int col, int row);

private:
    void buildBackground();
};

} // namespace bm