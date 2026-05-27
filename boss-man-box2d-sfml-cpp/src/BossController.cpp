#include "BossController.hpp"
#include "SoundManager.hpp"
#include <cstdlib>
#include <algorithm>
#include <cmath>

namespace bm {

static BossPersonality personalityFromIndex(int idx) {
    switch (idx) {
    case 0: return BossPersonality::DirectChase;
    case 1: return BossPersonality::AmbushAhead;
    case 2: return BossPersonality::Flanker;
    case 3: return BossPersonality::TimidScatter;
    default: return BossPersonality::DirectChase;
    }
}

void BossController::spawn(int level, const GridMap& map, const Pathfinder& pf,
                           const std::vector<std::pair<int, GridPos>>& overrides) {
    clear();
    currentLevel = level;
    currentOverrides = overrides; // remember map spawns so respawns keep their home
    bool isMIB = (level % 12 == 0);

    auto createBoss = [&](int bpIdx, GridPos spawnPos) {
        auto& bp = BOSS_BLUEPRINTS[bpIdx];
        Color bodyColor = isMIB ? BLACK : bp.bodyColor;
        Color tieColor = isMIB ? BLACK : bp.tieColor;
        Color pantsColor = isMIB ? Color{0.0f,0.0f,0.0f,1.0f} : bp.pantsColor;

        PersonConfig cfg;
        cfg.bodyColor = bodyColor;
        cfg.tieColor = tieColor;
        cfg.hairColor = BOSS_HAIR;
        cfg.shoeOutlineColor = BOSS_SHOE_GOLD;
        cfg.pantsColor = pantsColor;
        cfg.wearsSunglasses = isMIB;
        cfg.headYOffset = 1.0f;

        BossAI ai(spawnPos, DETECTION_RANGE, personalityFromIndex(bp.personality), &pf, &map);
        ai.teleport(spawnPos);

        BossEntity ent;
        ent.name = bp.name;
        ent.baseColor = bodyColor;
        ent.tieColor = tieColor;
        ent.pantsColor = pantsColor;
        ent.spawn = spawnPos;
        ent.ai = ai;
        ent.renderer = PixelPersonRenderer(cfg);
        ent.moveInterval = BOSS_MOVE_INTERVAL / bp.speed;
        ent.moveDuration = BOSS_MOVE_DURATION / bp.speed;
        ent.grid = spawnPos;
        ent.pixelPos = map.pointFor(spawnPos);
        ent.blueprintIndex = bpIdx;
        entities.push_back(ent);
        applySpawnFreeze(entities.size() - 1);
    };

    // Boss home positions come exclusively from the level map (the '1'..'4'
    // tiles parsed into `overrides`). There is no hardcoded fallback: a boss
    // with no tile in the level simply does not spawn. Every other path
    // (respawn, relocate, teleport-to-spawn) reuses the per-boss `spawn` set
    // here, so the home is always sourced from the level.
    for (auto& [idx, pos] : overrides) {
        if (idx >= 0 && idx < 4) createBoss(idx, pos);
    }
}

void BossController::update(float dt, const GridMap& map, const Pathfinder& pf,
                            GridPos workerGrid, MoveDirection workerDir,
                            bool isGoldDiscMode, bool isPeteShielded) {

    for (int i = 0; i < (int)entities.size(); ++i) {
        auto& boss = entities[i];

        // Capture animation (scale up + fade out, then teleport to spawn)
        if (boss.isCaptured) {
            boss.captureAnimTimer -= dt;
            float t = 1.0f - (boss.captureAnimTimer / 0.25f);
            boss.captureScale = 1.0f + 0.6f * t;
            boss.captureAlpha = 1.0f - t;
            if (boss.captureAnimTimer <= 0) {
                boss.isCaptured = false;
                boss.captureScale = 1.0f;
                boss.captureAlpha = 1.0f;
                // Teleport back to spawn
                bool hasEscaped = boss.captureCount >= 3;
                boss.ai.teleport(boss.spawn);
                boss.grid = boss.spawn;
                boss.pixelPos = map.pointFor(boss.spawn);
                if (hasEscaped) {
                    boss.isActive = false;
                    boss.respawnTimer = 999.0f;
                } else {
                    applySpawnFreeze(i);
                }
            }
            continue;
        }

        if (!boss.isActive) {
            // Respawn timer
            boss.respawnTimer -= dt;
            if (boss.respawnTimer <= 0) {
                boss.isActive = true;
                relocateToSpawn(i, map);
                applySpawnFreeze(i);
                if (isGoldDiscMode) {
                    boss.isInFleeMode = true;
                    boss.renderer.config.bodyColor = FLEE_BODY;
                    boss.renderer.config.tieColor = FLEE_TIE;
                    boss.renderer.config.shoeOutlineColor = BOSS_SHOE_GOLD;
                }
            }
            continue;
        }

        // Freeze timer
        if (boss.isImmobilized) {
            boss.freezeTimer -= dt;
            boss.fadeInAlpha = std::min(1.0f, boss.fadeInAlpha + dt / 1.5f);
            if (boss.freezeTimer <= 0) {
                boss.isImmobilized = false;
                boss.fadeInAlpha = 1.0f;
                boss.throbTimer = SPAWN_THROB_DUR; // pulse starts as the boss wakes
            }
            continue;
        }

        // Post-spawn throb pulse
        if (boss.throbTimer > 0.0f) boss.throbTimer -= dt;

        // Movement
        boss.moveTimer -= dt;
        if (boss.moveTimer <= 0) {
            stepOne(i, map, pf, workerGrid, workerDir, isGoldDiscMode, isPeteShielded);
            boss.moveTimer = boss.moveInterval;
        }

        // Interpolate position
        if (boss.isMoving) {
            float t = 1.0f - (boss.moveTimer / boss.moveDuration);
            t = std::clamp(t, 0.0f, 1.0f);
            boss.pixelPos = boss.startPos + (boss.targetPos - boss.startPos) * t;
            boss.walkPhase += dt;
        }
    }
}

void BossController::stepOne(int index, const GridMap& map, const Pathfinder& pf,
                             GridPos workerGrid, MoveDirection workerDir,
                             bool isGoldDiscMode, bool isPeteShielded) {
    auto& boss = entities[index];

    BossAI::Move move;
    if (boss.mustExitDoorway) {
        // Force exit from tunnel doorway
        int dx[] = {1,-1,0,0}, dy[] = {0,0,1,-1};
        bool found = false;
        for (int i = 0; i < 4; ++i) {
            GridPos next = {boss.grid.x+dx[i], boss.grid.y+dy[i]};
            if (map.isWalkable(next) && map.tunnelPartner(next).x < 0) {
                move = {boss.grid, next};
                boss.grid = next;
                boss.mustExitDoorway = false;
                found = true;
                break;
            }
        }
        if (!found) return;
    } else {
        move = boss.ai.planNextStep(workerGrid, workerDir, firstBossGrid(), isGoldDiscMode);
    }

    // Set look direction
    int mdx = move.to.x - move.from.x;
    int mdy = move.to.y - move.from.y;
    if (abs(mdx) > abs(mdy)) {
        boss.lookDir = mdx < 0 ? MoveDirection::Left : MoveDirection::Right;
        boss.facingLeft = (mdx < 0);  // facing only changes on horizontal moves
    } else if (mdy != 0) {
        boss.lookDir = mdy > 0 ? MoveDirection::Up : MoveDirection::Down;
    }

    // Check if this is a tunnel teleport
    bool isPartnerEdge = abs(move.to.x - move.from.x) + abs(move.to.y - move.from.y) > 1;
    if (isPartnerEdge) {
        boss.pixelPos = map.pointFor(move.to);
        boss.grid = move.to;
        boss.isMoving = false;
    } else {
        boss.isMoving = true;
        boss.startPos = map.pointFor(move.from);
        boss.targetPos = map.pointFor(move.to);
        boss.grid = move.to;
        float stepDur = boss.moveDuration;
        if (map.hasTunnelPartner(move.from) || map.hasTunnelPartner(move.to))
            stepDur *= 2.0f;
        boss.moveTimer = stepDur;
    }

    // Check worker collision
    if (Pathfinder::manhattanDist(move.to, workerGrid) < 0.5f) {
        if (boss.isInFleeMode) {
            capture(index, map);
        } else if (!isPeteShielded) {
            // Boss caught worker - handled by game
        }
    }
}

void BossController::draw(sf::RenderTarget& target) {
    static sf::Font font;
    static bool fontLoaded = false;
    if (!fontLoaded) {
        fontLoaded = font.loadFromFile("assets/fonts/JetBrainsMono-Bold.ttf") ||
                     font.loadFromFile("/System/Library/Fonts/Menlo.ttc") ||
                     font.loadFromFile("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf");
    }

    for (auto& boss : entities) {
        if (!boss.isActive && !boss.isCaptured) continue;
        bool facingLeft = boss.facingLeft;
        float alpha = boss.fadeInAlpha;
        if (boss.isImmobilized) alpha = boss.fadeInAlpha;
        if (boss.isCaptured) alpha = boss.captureAlpha;

        float scale = boss.captureScale;
        if (boss.throbTimer > 0.0f) {
            float progress = 1.0f - boss.throbTimer / SPAWN_THROB_DUR;
            scale *= 1.0f + 0.18f * std::abs(std::sin(progress * 3.14159265f * 3.0f));
        }

        boss.renderer.draw(target, boss.pixelPos, facingLeft, boss.isMoving,
                          boss.lookDir, boss.walkPhase, alpha, scale);

        // Name tag (centered like SpriteKit SKLabelNode)
        int nextCapturePts = 100 * (captureStreak + 1);
        std::string tagText = (boss.isInFleeMode) ? std::to_string(nextCapturePts) : boss.name;
        sf::Text nameTag;
        nameTag.setFont(font);
        nameTag.setString(tagText);
        nameTag.setCharacterSize(9);
        nameTag.setFillColor(boss.isInFleeMode ? PixelPersonRenderer::toSfColor(YELLOW) : sf::Color::White);
        auto lb = nameTag.getLocalBounds();
        nameTag.setOrigin(lb.left + lb.width/2, lb.top + lb.height/2);
        nameTag.setPosition(boss.pixelPos.x, boss.pixelPos.y - 24);
        target.draw(nameTag);
    }
}

void BossController::setGoldDiscActive(bool active) {
    captureStreak = 0;
    for (auto& boss : entities) {
        boss.captureCount = 0;
        boss.isInFleeMode = active;
        if (active) {
            boss.renderer.config.bodyColor = FLEE_BODY;
            boss.renderer.config.tieColor = FLEE_TIE;
            boss.renderer.config.shoeOutlineColor = BOSS_SHOE_GOLD;
        } else {
            boss.renderer.config.bodyColor = boss.baseColor;
            boss.renderer.config.tieColor = boss.tieColor;
            // Reactivate bosses that were captured 3x (respawnTimer was 999)
            if (!boss.isActive && boss.respawnTimer > 10.0f) {
                boss.respawnTimer = 3.0f;
            }
        }
    }
}

void BossController::teleportAllToSpawn(const GridMap& map, const Pathfinder& pf) {
    auto overrides = currentOverrides; // keep the level's map spawns (don't fall back to blueprints)
    spawn(currentLevel, map, pf, overrides);
}

void BossController::clear() {
    entities.clear();
    captureStreak = 0;
}

void BossController::stopAll() {
    for (auto& boss : entities) {
        boss.isMoving = false;
    }
}

bool BossController::isInFleeMode(int index) const {
    return index >= 0 && index < (int)entities.size() && entities[index].isInFleeMode;
}

bool BossController::isImmobilized(int index) const {
    return index >= 0 && index < (int)entities.size() && entities[index].isImmobilized;
}

void BossController::capture(int index, const GridMap& map) {
    auto& boss = entities[index];
    captureStreak++;
    boss.captureCount++;
    boss.isCaptured = true;
    boss.captureAnimTimer = 0.25f;
    boss.captureScale = 1.0f;
    boss.captureAlpha = 1.0f;
    boss.isMoving = false;
}

void BossController::splash(int index, const GridMap& map, const Pathfinder& pf) {
    if (index < 0 || index >= (int)entities.size()) return;
    auto& boss = entities[index];
    boss.isActive = false;
    boss.respawnTimer = 5.0f;
    boss.isInFleeMode = false;
}

GridPos BossController::firstBossGrid() const {
    if (entities.empty()) return {-1, -1};
    for (auto& e : entities) {
        if (e.isActive && !e.isImmobilized) return e.grid;
    }
    return entities[0].grid;
}

void BossController::relocateToSpawn(int index, const GridMap& map) {
    auto& boss = entities[index];
    boss.ai.teleport(boss.spawn);
    boss.grid = boss.spawn;
    boss.pixelPos = map.pointFor(boss.spawn);
    boss.captureCount = 0;
    boss.isInFleeMode = false;
    boss.mustExitDoorway = false;
    boss.isMoving = false;
}

void BossController::applySpawnFreeze(int index) {
    auto& boss = entities[index];
    boss.isImmobilized = true;
    boss.freezeTimer = SPAWN_FREEZE_DUR;
    boss.fadeInAlpha = 0.0f;
    boss.throbTimer = 0.0f;
    if (sound) sound->playTeleport();
}

} // namespace bm