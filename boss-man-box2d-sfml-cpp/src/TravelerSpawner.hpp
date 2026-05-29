#pragma once
#include "Constants.hpp"
#include "GridMap.hpp"
#include "Pathfinder.hpp"
#include "SoundManager.hpp"
#include <vector>
#include <cstdlib>

namespace bm {

struct Traveler {
    GridPos grid;
    GridPos previousGrid = {-1, -1};
    sf::Vector2f pixelPos;
    sf::Vector2f startPixel;
    sf::Vector2f targetPixel;
    std::string emoji;
    int points;
    bool facesRight = false;
    bool flipX = false; // emoji mirrored to face travel direction (label stays upright)
    bool active = false;
    float moveTimer = 0.0f;
    bool isMoving = false;
    float moveDuration = 0.0f;
    float catchAnimTimer = 0.0f;
    bool catching = false;
    float catchScale = 1.0f;
    float catchAlpha = 1.0f;
};

class TravelerSpawner {
public:
    std::vector<Traveler> travelers;
    float visitTimer = 10.0f;
    int travelerIndex = 0;
    bool scheduled = false;
    const Pathfinder* pathfinder = nullptr;
    SoundManager* sound = nullptr;
    void setSound(SoundManager* s) { sound = s; }

    static constexpr float MOVE_INTERVAL = 0.22f;
    static constexpr float FIRST_VISIT_DELAY = 10.0f;
    static constexpr float RESPAWN_DELAY = 30.0f;
    GridPos spawnGrid = {36, 8};
    GridPos exitGrid = {0, 8};

    void scheduleVisits(int level, const Pathfinder& pf) {
        pathfinder = &pf;
        visitTimer = FIRST_VISIT_DELAY;
        travelerIndex = ((level - 1) % TRAVELER_COUNT);
        scheduled = true;
    }

    void update(float dt, const GridMap& map) {
        if (!scheduled) return;

        visitTimer -= dt;
        if (visitTimer <= 0) {
            bool anyActive = false;
            for (auto& tr : travelers) if (tr.active || tr.catching) { anyActive = true; break; }
            if (!anyActive) spawnNext(map);
        }

        for (auto& tr : travelers) {
            // Catch animation
            if (tr.catching) {
                tr.catchAnimTimer -= dt;
                tr.catchScale = 1.0f + 0.6f * (1.0f - tr.catchAnimTimer / 0.25f);
                tr.catchAlpha = tr.catchAnimTimer / 0.25f;
                if (tr.catchAnimTimer <= 0) {
                    tr.catching = false;
                    tr.active = false;
                }
                continue;
            }

            if (!tr.active) continue;

            // Smooth movement interpolation
            if (tr.isMoving) {
                tr.moveTimer -= dt;
                float t = 1.0f - (tr.moveTimer / tr.moveDuration);
                t = t < 0 ? 0 : (t > 1 ? 1 : t);
                tr.pixelPos = tr.startPixel + (tr.targetPixel - tr.startPixel) * t;
                if (tr.moveTimer <= 0) {
                    tr.pixelPos = tr.targetPixel;
                    tr.isMoving = false;
                }
            }

            // Step timer
            if (!tr.isMoving) {
                tr.moveTimer -= dt;
                if (tr.moveTimer <= 0) {
                    stepTraveler(tr, map);
                    tr.moveTimer = MOVE_INTERVAL;
                }
            }
        }

        // Clean up dead travelers
        travelers.erase(std::remove_if(travelers.begin(), travelers.end(),
            [](const Traveler& tr) { return !tr.active && !tr.catching; }), travelers.end());
    }

    void catchTraveler(Traveler& tr) {
        tr.catching = true;
        tr.catchAnimTimer = 0.25f;
        tr.catchScale = 1.0f;
        tr.catchAlpha = 1.0f;
    }

    void reset() {
        travelers.clear();
        scheduled = false;
    }

private:
    void spawnNext(const GridMap& map) {
        auto& t = TRAVELERS[travelerIndex % TRAVELER_COUNT];
        // The doorway can sit on any row, so resolve it from the current maze
        // each spawn (a level may have moved the tunnel); defaults stand if none.
        map.horizontalDoorway(spawnGrid, exitGrid);
        Traveler tr;
        tr.grid = spawnGrid;
        tr.previousGrid = {-1, -1};
        tr.pixelPos = map.pointFor(spawnGrid);
        tr.emoji = t.emoji;
        tr.points = t.points;
        tr.facesRight = t.facesRight;
        tr.active = true;
        tr.moveTimer = MOVE_INTERVAL;
        tr.isMoving = false;
        travelers.push_back(tr);
        visitTimer = RESPAWN_DELAY;
        // Distinct arrival sound per traveler type (index matches TRAVELERS order).
        if (sound) sound->playTravelerArrive(travelerIndex % TRAVELER_COUNT);
    }

    void stepTraveler(Traveler& tr, const GridMap& map) {
        // Exit check
        if (tr.grid == exitGrid) {
            tr.active = false;
            visitTimer = RESPAWN_DELAY;
            return;
        }

        // Gather walkable neighbors
        int dx[] = {1, -1, 0, 0};
        int dy[] = {0, 0, 1, -1};
        std::vector<GridPos> candidates;
        for (int i = 0; i < 4; ++i) {
            GridPos next = {tr.grid.x + dx[i], tr.grid.y + dy[i]};
            if (map.isWalkable(next))
                candidates.push_back(next);
        }

        // Backtrack prevention: remove previous position if there are alternatives
        if (tr.previousGrid.x >= 0 && candidates.size() > 1) {
            candidates.erase(std::remove_if(candidates.begin(), candidates.end(),
                [&](const GridPos& p) { return p == tr.previousGrid; }), candidates.end());
        }

        if (candidates.empty()) return;

        // Biased random walk: 60% toward exit, 40% random
        GridPos next;
        if (std::rand() % 10 < 6) {
            // Move toward exit (smallest Manhattan distance)
            GridPos best = candidates[0];
            float bestDist = Pathfinder::manhattanDist(best, exitGrid);
            for (auto& c : candidates) {
                float d = Pathfinder::manhattanDist(c, exitGrid);
                if (d < bestDist) { bestDist = d; best = c; }
            }
            next = best;
        } else {
            next = candidates[std::rand() % candidates.size()];
        }

        // Flip the emoji to face the travel direction (only on horizontal moves).
        // Left-facing glyphs flip when moving right; the stapler (right-facing) is
        // the reverse. The points label is drawn separately and never flips.
        int hdx = next.x - tr.grid.x;
        if (hdx != 0) tr.flipX = tr.facesRight ? (hdx < 0) : (hdx > 0);

        // Start smooth movement
        tr.previousGrid = tr.grid;
        tr.grid = next;
        tr.startPixel = tr.pixelPos;
        tr.targetPixel = map.pointFor(next);
        tr.isMoving = true;
        tr.moveDuration = MOVE_INTERVAL;
        tr.moveTimer = MOVE_INTERVAL;
    }
};

} // namespace bm