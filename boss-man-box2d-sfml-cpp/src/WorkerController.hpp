#pragma once
#include <SFML/Graphics.hpp>
#include "GridMap.hpp"
#include "MoveDirection.hpp"
#include "PixelPersonRenderer.hpp"

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
        : grid(spawn), mapPtr(&map), renderer(PersonConfig{PETE_BODY, PETE_TIE, PETE_HAIR, PETE_SHOE_OUT, PETE_PANTS, 1.0f, false}) {
        pixelPos = map.pointFor(spawn);
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

        moveTimer -= dt;
        if (moveTimer <= 0) {
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
        } else {
            // Interpolate position
            float t = 1.0f - (moveTimer / WORKER_MOVE_DUR);
            pixelPos = startPos + (targetPos - startPos) * t;
        }

        // Walk phase
        if (isMoving) walkPhase += dt;
    }

    void draw(sf::RenderTarget& target) {
        float alpha = 1.0f;
        if (isShielded) {
            // Blink effect
            alpha = 0.5f + 0.5f * std::sin(shieldTimer * 5.0f);
        }
        renderer.draw(target, pixelPos, facingLeft, isMoving, direction, walkPhase, alpha);

        // Name tag (centered like SpriteKit SKLabelNode)
        static sf::Font font;
        static bool fontLoaded = false;
        if (!fontLoaded) {
            fontLoaded = font.loadFromFile("assets/fonts/JetBrainsMono-Bold.ttf") ||
                         font.loadFromFile("/System/Library/Fonts/Menlo.ttc") ||
                         font.loadFromFile("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf");
        }
        sf::Text nameTag;
        nameTag.setFont(font);
        nameTag.setString(Worker::PETE);
        nameTag.setCharacterSize(9);
        nameTag.setFillColor(sf::Color::White);
        auto lb = nameTag.getLocalBounds();
        nameTag.setOrigin(lb.left + lb.width/2, lb.top + lb.height/2);
        nameTag.setPosition(pixelPos.x, pixelPos.y - 24);
        target.draw(nameTag);
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

        isMoving = true;
        startPos = map->pointFor(grid);
        targetPos = map->pointFor(next);
        grid = next;
        moveTimer = WORKER_MOVE_DUR;
    }
};

} // namespace bm