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
    float stepDuration = 0.0f;       // glide time of the current step (x2 in tunnels)
    float stepTotal = 0.0f;          // glide + idle pause; the full step period
    bool arrivedAtDoorway = false;   // just slid onto a tunnel doorway; cross next step
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

    // Capture animation (two phases, matching SpriteKit):
    //  isCaptured       — phase 1: scale 1.0->1.6 + fade out where caught (0.25s)
    //  captureReturning — phase 2: at spawn, scale 1.6->1.0 + fade in (0.2s)
    bool isCaptured = false;
    bool captureReturning = false;
    float captureAnimTimer = 0.0f;
    float captureScale = 1.0f;
    float captureAlpha = 1.0f;
};

class BossController {
public:
    std::vector<BossEntity> entities;
    int captureStreak = 0;
    int currentLevel = 1;
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

    // Boss tiles parsed from the current level, remembered so a mid-level reset
    // (e.g. after a boss catches the worker) re-spawns from the same level
    // positions — never from hardcoded coordinates.
    std::vector<std::pair<int, GridPos>> currentSpawnOverrides_;
};

} // namespace bm