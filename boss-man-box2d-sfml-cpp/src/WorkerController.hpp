#pragma once
#include <SFML/Graphics.hpp>
#include <functional>
#include <algorithm>
#include "GridMap.hpp"
#include "MoveDirection.hpp"
#include "PixelPersonRenderer.hpp"
#include "TextLabel.hpp"
#include "Assets.hpp"

namespace bm {

class WorkerController {
public:
    GridPos grid;
    MoveDirection direction = MoveDirection::None;
    MoveDirection queuedDirection = MoveDirection::None;
    bool isMoving = false;
    bool isShielded = false;
    bool facingLeft = false;  // preserved across up/down moves, like SpriteKit
    float walkPhase = 0.0f;
    PixelPersonRenderer renderer;
    sf::Vector2f pixelPos;
    float moveTimer = 0.0f;

    WorkerController(GridPos spawn, const GridMap& map)
        : grid(spawn), mapPtr(&map), renderer(PersonConfig{PETE_BODY, PETE_TIE, PETE_HAIR, PETE_SHOE_OUT, PETE_PANTS, SKIN_COLOR}) {
        pixelPos = map.pointFor(spawn);
    }

    // Per-step variable speed ramp: a tunnel-entry step runs full speed for its
    // first half then ramps full->lo over the second; a tunnel-exit step ramps
    // lo->full over its first half then full. lo = 1/tunnelSlowdown is the slow
    // floor. Everything else runs at full speed. Ported from the Swift TileMover.
    enum class StepKind { Normal, Enter, Exit };

    static float tunnelSpeedFraction(StepKind kind, float p, float tunnelSlowdown) {
        float lo = 1.0f / tunnelSlowdown;
        switch (kind) {
        case StepKind::Enter: return p < 0.5f ? 1.0f : 1.0f + (lo - 1.0f) * (p - 0.5f) * 2.0f;
        case StepKind::Exit:  return p < 0.5f ? lo + (1.0f - lo) * p * 2.0f : 1.0f;
        default:              return 1.0f;
        }
    }

    void queueDirection(MoveDirection dir) {
        queuedDirection = dir;
        if (direction == MoveDirection::None) direction = dir;
        if (!isMoving) attemptStep(mapPtr);
    }

    void resetMotion() {
        direction = MoveDirection::None;
        queuedDirection = MoveDirection::None;
        isMoving = false;
        moveTimer = 0.0f;
        prog = 0.0f;
        stepKind = StepKind::Normal;
    }

    void teleport(GridPos target, const GridMap& map) {
        grid = target;
        pixelPos = map.pointFor(target);
    }

    void applySpawnShield() {
        isShielded = true;
        shieldTimer = SPAWN_SHIELD_DUR;
    }

    void update(float dt, const GridMap& map) {
        // Shield timer
        if (isShielded) {
            shieldTimer -= dt;
            if (shieldTimer <= 0) isShielded = false;
        }

        if (!isMoving) return;

        // prog 0..1 over one cell; the per-frame increment is scaled by the
        // tunnel speed fraction, with a 0.001 floor and leftover-time accounting
        // on arrival, matching the Swift TileMover.advance step model.
        float v = std::max(0.001f, tunnelSpeedFraction(stepKind, prog, WORKER_TUNNEL_SLOWDOWN));
        float dp = (dt / WORKER_MOVE_DUR) * v;
        float rem = 0.0f;
        if (prog + dp < 1.0f) {
            prog += dp;
        } else {
            rem = std::max(0.0f, dt - ((1.0f - prog) / v) * WORKER_MOVE_DUR);
            prog = 1.0f;
        }
        pixelPos = startPos + (targetPos - startPos) * prog;

        if (prog >= 1.0f) {
            // Arrived at next tile
            pixelPos = map.pointFor(grid);
            isMoving = false;
            if (lastTileCallback) lastTileCallback(grid);

            // Check tunnel
            GridPos partner = map.tunnelPartner(grid);
            if (partner.x >= 0 && map.isWalkable(partner)) {
                grid = partner;
                pixelPos = map.pointFor(partner);
                if (lastTileCallback) lastTileCallback(partner);
            }

            attemptStep(&map);
            // Spend the leftover time slice on the freshly latched step so a fast
            // dt slice can begin advancing the next cell this frame.
            if (isMoving && rem > 0.0f) {
                float v2 = std::max(0.001f, tunnelSpeedFraction(stepKind, prog, WORKER_TUNNEL_SLOWDOWN));
                prog += (rem / WORKER_MOVE_DUR) * v2;
                if (prog > 1.0f) prog = 1.0f;
                pixelPos = startPos + (targetPos - startPos) * prog;
            }
        }

        // Walk phase
        if (isMoving) walkPhase += dt;
    }

    void draw(sf::RenderTarget& target) {
        float alpha = 1.0f;
        if (isShielded) {
            float elapsed = SPAWN_SHIELD_DUR - shieldTimer;
            if (elapsed < 0.6f)
                alpha = 1.0f - 0.65f * (elapsed / 0.6f);
            else if (elapsed < 1.2f)
                alpha = 0.35f + 0.65f * ((elapsed - 0.6f) / 0.6f);
        }
        renderer.draw(target, pixelPos, facingLeft, isMoving, direction, walkPhase, alpha);

        // Name tag: SpriteKit SKLabelNode, Menlo-Bold 9, white, baseline 24 above
        // center. Rendered via the crisp uiScale text path so it isn't blurry on
        // Retina (it was previously rasterized at raw 9px).
        static sf::Font font;
        static bool fontLoaded = false;
        if (!fontLoaded) {
            fontLoaded = loadFont(font, "assets/fonts/JetBrainsMono-Bold.ttf");
        }
        drawNameLabel(target, font, Worker::PETE, 9, sf::Color::White,
                      pixelPos.x, pixelPos.y - 24);
    }

    std::function<void(GridPos)> lastTileCallback;

    sf::Vector2f startPos, targetPos;

private:
    const GridMap* mapPtr = nullptr;
    float shieldTimer = 0.0f;

    void attemptStep(const GridMap* map) {
        if (queuedDirection != MoveDirection::None && map) {
            GridPos queued = bm::neighbor(grid, queuedDirection);
            if (map->isWalkable(queued)) {
                direction = queuedDirection;
                queuedDirection = MoveDirection::None;
            }
        }
        if (direction == MoveDirection::None) return;
        GridPos next = bm::neighbor(grid, direction);
        if (!map || !map->isWalkable(next)) return;

        // Facing only changes on horizontal moves; vertical moves keep prior facing.
        if (direction == MoveDirection::Left) facingLeft = true;
        else if (direction == MoveDirection::Right) facingLeft = false;

        // Tunnel slowdown ramp: stepping INTO a tunnel-mouth cell ramps
        // full->slow over the step's back half; stepping OUT of one ramps
        // slow->full over the front half. Otherwise full speed.
        if (map->tunnelPartner(next).x >= 0)      stepKind = StepKind::Enter;
        else if (map->tunnelPartner(grid).x >= 0) stepKind = StepKind::Exit;
        else                                      stepKind = StepKind::Normal;

        isMoving = true;
        startPos = map->pointFor(grid);
        targetPos = map->pointFor(next);
        grid = next;
        prog = 0.0f;
        moveTimer = WORKER_MOVE_DUR;
    }

    float prog = 0.0f;
    StepKind stepKind = StepKind::Normal;
};

} // namespace bm