#pragma once
#include <SFML/Graphics.hpp>
#include <vector>
#include <functional>
#include "GridMap.hpp"
#include "Pathfinder.hpp"
#include "BossAI.hpp"
#include "PixelPersonRenderer.hpp"
#include "MoveDirection.hpp"

namespace bm {

class BossController;
class SoundManager;

// Per-step hook for boss water-droplet evasion. The game scans active droplets
// and reports the travel axis of any droplet bearing down on a boss at `grid`
// (None when no threat); the boss then steps perpendicular to dodge it.
class BossControllerDelegate {
public:
    virtual ~BossControllerDelegate() = default;
    virtual MoveDirection dropletAxisThreatening(GridPos bossGrid) = 0;
};

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
    float stepDuration = 0.0f;       // glide time of the current step
    float stepTotal = 0.0f;          // glide + idle pause; the full step period
    float idleGap = 0.0f;            // post-glide dwell at the tile centre
    float prog = 0.0f;               // 0..1 glide progress for the current cell
    int   stepKind = 0;              // 0 normal, 1 enter-tunnel, 2 exit-tunnel
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
    float spawnGrace = 0.0f;
    float frightenedStep = 0.0f;
    float lastMove = 0.0f;
    float walkPhase = 0.0f;
    float throbTimer = 0.0f;
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
    BossControllerDelegate* delegate = nullptr;

    BossController() = default;

    inline int nextCapturePoints() const { return 100 * (captureStreak + 1); }
    bool hasFirstBoss() const { return !entities.empty(); }
    bool isAnyBossSpawning() const;
    void relocateAfterCatch(BossEntity* node, const GridMap& map);

    void setSound(SoundManager* s) { sound = s; }
    void setDelegate(BossControllerDelegate* d) { delegate = d; }

    void spawn(int level, const GridMap& map, const Pathfinder& pf,
               const std::vector<std::pair<int, GridPos>>& overrides = {});

    void update(float dt, const GridMap& map, const Pathfinder& pf,
                GridPos workerGrid, MoveDirection workerDir, bool isGoldDiscMode, bool isPeteShielded,
                std::function<bool(const BossEntity&)> shouldMove = nullptr);

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
    void applyFleeThawTransition();

    // Boss tiles parsed from the current level, remembered so a mid-level reset
    // (e.g. after a boss catches the worker) re-spawns from the same level
    // positions — never from hardcoded coordinates.
    std::vector<std::pair<int, GridPos>> currentSpawnOverrides_;
};

} // namespace bm