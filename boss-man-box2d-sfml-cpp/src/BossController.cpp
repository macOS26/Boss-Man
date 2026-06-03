#include "BossController.hpp"
#include "SoundManager.hpp"
#include "TextLabel.hpp"
#include "Assets.hpp"
#include "Settings.hpp"
#include <cstdlib>
#include <algorithm>
#include <cmath>

namespace bm {

// Per-step variable speed ramp, ported from the Swift TileMover. lo =
// 1/tunnelSlowdown is the slow floor. A tunnel-entry step (kind 1) runs full
// speed for its first half then ramps full->lo; a tunnel-exit step (kind 2)
// ramps lo->full over its first half then full. Everything else is full speed.
static float tunnelSpeedFraction(int kind, float p, float tunnelSlowdown) {
    float lo = 1.0f / tunnelSlowdown;
    switch (kind) {
    case 1: return p < 0.5f ? 1.0f : 1.0f + (lo - 1.0f) * (p - 0.5f) * 2.0f;
    case 2: return p < 0.5f ? lo + (1.0f - lo) * p * 2.0f : 1.0f;
    default: return 1.0f;
    }
}

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
    currentSpawnOverrides_ = overrides; // remembered for mid-level resets
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
        // Boss Tracks (title screen): "Square" (default) = classic glide-then-dwell
        // (0.36 interval / 0.22 glide => 0.14 centre dwell); "Smooth" = continuous
        // 0.16 glide with no dwell, matching the SuperBox64 / wasm Smooth mode.
        // Square runs 15% faster (x1.15 on speed = 15% less per-tile time) while
        // keeping the 0.22-glide / 0.14-dwell cadence; smooth uses the base speed.
        // Matches the Swift master's BossController.buildEntity.
        const bool square = Settings::bossTracksSquare();
        const float speed = square ? (bp.speed * 1.15f) : bp.speed;
        ent.moveInterval = (square ? BOSS_MOVE_INTERVAL : 0.16f) / speed;
        ent.moveDuration = (square ? BOSS_MOVE_DURATION : 0.16f) / speed;
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

        // Capture phase 1: scale up + fade out where the boss was caught (0.25s),
        // then snap to its spawn (still invisible) and start the reappear phase.
        if (boss.isCaptured) {
            boss.captureAnimTimer -= dt;
            float t = std::clamp(1.0f - boss.captureAnimTimer / 0.25f, 0.0f, 1.0f);
            boss.captureScale = 1.0f + 0.6f * t; // 1.0 -> 1.6
            boss.captureAlpha = 1.0f - t;        // 1 -> 0
            if (boss.captureAnimTimer <= 0) {
                boss.isCaptured = false;
                boss.ai.teleport(boss.spawn);
                boss.grid = boss.spawn;
                boss.pixelPos = map.pointFor(boss.spawn);
                if (boss.captureCount >= 3) {
                    // Escaped — stays gone until gold-disc mode ends, then respawns.
                    boss.isActive = false;
                    boss.respawnTimer = 999.0f;
                    boss.captureScale = 1.0f;
                    boss.captureAlpha = 1.0f;
                } else {
                    boss.captureReturning = true;
                    boss.captureAnimTimer = 0.2f;
                }
            }
            continue;
        }

        // Capture phase 2: reappear at spawn — scale 1.6 -> 1.0 + fade in (0.2s),
        // then resume immediately (no spawn freeze, matching SpriteKit).
        if (boss.captureReturning) {
            boss.captureAnimTimer -= dt;
            float t = std::clamp(1.0f - boss.captureAnimTimer / 0.2f, 0.0f, 1.0f);
            boss.captureScale = 1.6f - 0.6f * t; // 1.6 -> 1.0
            boss.captureAlpha = t;               // 0 -> 1
            if (boss.captureAnimTimer <= 0) {
                boss.captureReturning = false;
                boss.captureScale = 1.0f;
                boss.captureAlpha = 1.0f;
                boss.fadeInAlpha = 1.0f;
                boss.isImmobilized = false;
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
                    boss.renderer.config.skinColor = FLEE_SKIN;
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

        // Glide first (prog 0..1 over the cell, scaled by the tunnel speed ramp),
        // then dwell at the centre for idleGap, then latch the next step. Matching
        // SpriteKit's TileMover: the ramp applies only to the glide, the hold is a
        // separate post-arrival pause.
        if (boss.isMoving) {
            float v = std::max(0.001f, tunnelSpeedFraction(boss.stepKind, boss.prog, BOSS_TUNNEL_SLOWDOWN));
            float dp = (dt / boss.stepDuration) * v;
            float rem = 0.0f;
            if (boss.prog + dp < 1.0f) {
                boss.prog += dp;
            } else {
                rem = std::max(0.0f, dt - ((1.0f - boss.prog) / v) * boss.stepDuration);
                boss.prog = 1.0f;
            }
            boss.pixelPos = boss.startPos + (boss.targetPos - boss.startPos) * boss.prog;
            if (boss.prog < 1.0f) {
                boss.walkPhase += dt;
            } else {
                // Arrived. Hold at the centre for idleGap, then spend the leftover
                // time slice draining the dwell so a fast frame doesn't stall.
                boss.isMoving = false;
                boss.moveTimer = boss.idleGap - rem;
                if (boss.moveTimer <= 0) {
                    stepOne(i, map, pf, workerGrid, workerDir, isGoldDiscMode, isPeteShielded);
                }
            }
        } else {
            // Latch the next step once the dwell elapses. stepOne sets the next
            // step's glide duration/ramp itself, so we must NOT overwrite moveTimer.
            boss.moveTimer -= dt;
            if (boss.moveTimer <= 0) {
                stepOne(i, map, pf, workerGrid, workerDir, isGoldDiscMode, isPeteShielded);
            }
        }
    }
}

void BossController::stepOne(int index, const GridMap& map, const Pathfinder& pf,
                             GridPos workerGrid, MoveDirection workerDir,
                             bool isGoldDiscMode, bool isPeteShielded) {
    auto& boss = entities[index];

    // Just finished sliding onto a tunnel doorway? Cross to the partner door now
    // (instant), then force an exit on this step so we don't ping-pong back.
    if (boss.arrivedAtDoorway && !boss.mustExitDoorway) {
        boss.arrivedAtDoorway = false;
        GridPos partner = map.tunnelPartner(boss.grid);
        if (partner.x >= 0 && map.isWalkable(partner)) {
            boss.ai.teleport(partner);
            boss.grid = partner;
            boss.pixelPos = map.pointFor(partner);
            boss.mustExitDoorway = true;
        }
    }

    BossAI::Move move;
    if (boss.mustExitDoorway) {
        // Force exit from tunnel doorway to a non-doorway neighbor.
        int dx[] = {1,-1,0,0}, dy[] = {0,0,1,-1};
        bool found = false;
        for (int i = 0; i < 4; ++i) {
            GridPos next = {boss.grid.x+dx[i], boss.grid.y+dy[i]};
            if (map.isWalkable(next) && map.tunnelPartner(next).x < 0) {
                move = {boss.grid, next};
                boss.ai.teleport(next); // keep the AI's grid in sync with the exit,
                                        // else the next step is planned from the
                                        // doorway and the boss snaps back in.
                boss.mustExitDoorway = false;
                found = true;
                break;
            }
        }
        if (!found) { boss.mustExitDoorway = false; return; }
    } else {
        MoveDirection dodgeAxis = delegate ? delegate->dropletAxisThreatening(boss.grid)
                                           : MoveDirection::None;
        const MoveDirection* dodge = (dodgeAxis != MoveDirection::None) ? &dodgeAxis : nullptr;
        move = boss.ai.planNextStep(workerGrid, workerDir, firstBossGrid(), isGoldDiscMode, dodge);
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

    const float idleGap = boss.moveInterval - boss.moveDuration; // pause between steps

    // A partner-edge move (the AI picked the far doorway directly) is an instant
    // teleport with no glide.
    bool isPartnerEdge = abs(move.to.x - move.from.x) + abs(move.to.y - move.from.y) > 1;
    if (isPartnerEdge) {
        boss.pixelPos = map.pointFor(move.to);
        boss.grid = move.to;
        boss.isMoving = false;
        boss.arrivedAtDoorway = false;
        boss.stepDuration = boss.moveDuration;
        boss.idleGap = idleGap;
        boss.moveTimer = boss.moveInterval;
        boss.stepTotal = boss.moveInterval;
        boss.prog = 1.0f;
        boss.stepKind = 0;
    } else {
        boss.isMoving = true;
        boss.startPos = map.pointFor(move.from);
        boss.targetPos = map.pointFor(move.to);
        boss.grid = move.to;
        boss.prog = 0.0f;
        // Tunnel slowdown ramp (full->slow->full across an enter/exit pair, the
        // slowdown produced by the speed fraction itself, not a doubled glide):
        // stepping INTO a tunnel-mouth cell ramps full->slow over the back half;
        // stepping OUT of one ramps slow->full over the front half.
        if (map.tunnelPartner(move.to).x >= 0)        boss.stepKind = 1;
        else if (map.tunnelPartner(move.from).x >= 0) boss.stepKind = 2;
        else                                          boss.stepKind = 0;
        boss.stepDuration = boss.moveDuration;
        boss.idleGap = idleGap;
        boss.stepTotal = boss.moveDuration + idleGap; // total step time = glide + idle pause
        boss.moveTimer = boss.stepTotal;
        // If we just slid ONTO a doorway, mark it so the next step crosses over.
        boss.arrivedAtDoorway = (map.tunnelPartner(move.to).x >= 0);
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
        fontLoaded = loadFont(font, "assets/fonts/JetBrainsMono-Bold.ttf");
    }

    for (auto& boss : entities) {
        if (!boss.isActive && !boss.isCaptured && !boss.captureReturning) continue;
        bool facingLeft = boss.facingLeft;
        float alpha = boss.fadeInAlpha;
        if (boss.isImmobilized) alpha = boss.fadeInAlpha;
        if (boss.isCaptured || boss.captureReturning) alpha = boss.captureAlpha;

        float scale = boss.captureScale;
        if (boss.throbTimer > 0.0f) {
            float progress = 1.0f - boss.throbTimer / SPAWN_THROB_DUR;
            scale *= 1.0f + 0.18f * std::abs(std::sin(progress * 3.14159265f * 3.0f));
        }

        boss.renderer.draw(target, boss.pixelPos, facingLeft, boss.isMoving,
                          boss.lookDir, boss.walkPhase, alpha, scale);

        // Name tag: SpriteKit SKLabelNode, Menlo-Bold 9, baseline 24 above center.
        // White normally; in flee mode it shows the next capture value in yellow.
        // Rendered via the crisp uiScale text path (was raw 9px before).
        int nextCapturePts = 100 * (captureStreak + 1);
        std::string tagText = (boss.isInFleeMode) ? std::to_string(nextCapturePts) : boss.name;
        sf::Color tagColor = boss.isInFleeMode ? PixelPersonRenderer::toSfColor(YELLOW)
                                               : sf::Color::White;
        drawNameLabel(target, font, tagText, 9, tagColor,
                      boss.pixelPos.x, boss.pixelPos.y - 24);
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
            boss.renderer.config.skinColor = FLEE_SKIN;
        } else {
            boss.renderer.config.bodyColor = boss.baseColor;
            boss.renderer.config.tieColor = boss.tieColor;
            boss.renderer.config.skinColor = SKIN_COLOR;
            // Reactivate bosses that were captured 3x (respawnTimer was 999)
            if (!boss.isActive && boss.respawnTimer > 10.0f) {
                boss.respawnTimer = 3.0f;
            }
        }
    }
}

void BossController::teleportAllToSpawn(const GridMap& map, const Pathfinder& pf) {
    // Re-spawn from the level's boss tiles (not empty overrides), so every boss —
    // including any that had escaped — returns to its level home right away.
    spawn(currentLevel, map, pf, currentSpawnOverrides_);
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
    if (boss.isCaptured || boss.captureReturning) return; // already animating a capture
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
    boss.arrivedAtDoorway = false;
    boss.isMoving = false;
    boss.prog = 0.0f;
    boss.stepKind = 0;
    boss.moveTimer = 0.0f;
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