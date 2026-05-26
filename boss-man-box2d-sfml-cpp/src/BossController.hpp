#pragma once
#include <SFML/Graphics.hpp>
#include <vector>
#include "GridMap.hpp"
#include "Pathfinder.hpp"
#include "BossAI.hpp"
#include "PixelPersonRenderer.hpp"
#include "MoveDirection.hpp"

namespace bm {

class BossController;
class SoundManager;

struct BossEntity {
    std::string name;
    Color baseColor;
    Color tieColor;
    Color pantsColor;
    GridPos spawn;
    BossAI ai;
    PixelPersonRenderer renderer;
    float moveInterval;
    float moveDuration;
    float moveTimer = 0.0f;
    GridPos grid;
    sf::Vector2f pixelPos;
    bool isImmobilized = true;
    bool isInFleeMode = false;
    int captureCount = 0;
    bool mustExitDoorway = false;
    float freezeTimer = 0.0f;
    float fadeInAlpha = 0.0f;
    int blueprintIndex = 0;
    bool isActive = true;
    float respawnTimer = -1.0f;
    MoveDirection lookDir = MoveDirection::None;
    bool facingLeft = false;  // preserved across up/down moves, like SpriteKit
    float walkPhase = 0.0f;
    float throbTimer = 0.0f;  // post-spawn pulse (scale 1.0->1.18, 3x)
    bool isMoving = false;
    sf::Vector2f startPos, targetPos;

    // Capture animation
    bool isCaptured = false;
    float captureAnimTimer = 0.0f;
    float captureScale = 1.0f;
    float captureAlpha = 1.0f;
};

class BossController {
public:
    std::vector<BossEntity> entities;
    int captureStreak = 0;
    int currentLevel = 1;
    std::vector<std::pair<int, GridPos>> currentOverrides; // map spawn positions; reused on respawn
    SoundManager* sound = nullptr;

    BossController() = default;

    void setSound(SoundManager* s) { sound = s; }

    void spawn(int level, const GridMap& map, const Pathfinder& pf,
               const std::vector<std::pair<int, GridPos>>& overrides = {});

    void update(float dt, const GridMap& map, const Pathfinder& pf,
                GridPos workerGrid, MoveDirection workerDir, bool isGoldDiscMode, bool isPeteShielded);

    void draw(sf::RenderTarget& target);

    void setGoldDiscActive(bool active);
    void teleportAllToSpawn(const GridMap& map, const Pathfinder& pf);
    void clear();
    void stopAll();

    bool isInFleeMode(int index) const;
    bool isImmobilized(int index) const;
    void capture(int index, const GridMap& map);
    void splash(int index, const GridMap& map, const Pathfinder& pf);

    GridPos firstBossGrid() const;

private:
    void stepOne(int index, const GridMap& map, const Pathfinder& pf,
                 GridPos workerGrid, MoveDirection workerDir, bool isGoldDiscMode, bool isPeteShielded);
    void relocateToSpawn(int index, const GridMap& map);
    void applySpawnFreeze(int index);
};

} // namespace bm