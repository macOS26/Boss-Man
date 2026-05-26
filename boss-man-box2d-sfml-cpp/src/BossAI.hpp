#pragma once
#include "GridMap.hpp"
#include "Pathfinder.hpp"
#include "MoveDirection.hpp"

namespace bm {

enum class BossPersonality { DirectChase, AmbushAhead, Flanker, TimidScatter };

class BossAI {
public:
    GridPos homeGrid;
    float detectionRange = DETECTION_RANGE;
    BossPersonality personality;
    GridPos grid;
    GridPos previousGrid = {-1, -1};
    int ambushTiles = 4;
    int pivotTiles = 2;
    float scatterThreshold = 8;
    GridPos scatterGrid = {1, 1};
    const Pathfinder* pathfinder = nullptr;
    const GridMap* map = nullptr;

    struct Move {
        GridPos from, to;
    };

    BossAI(GridPos home = {0,0}, float range = DETECTION_RANGE, BossPersonality pers = BossPersonality::DirectChase,
           const Pathfinder* pf = nullptr, const GridMap* m = nullptr)
        : homeGrid(home), detectionRange(range), personality(pers),
          grid(home), pathfinder(pf), map(m) {}

    void teleport(GridPos g) {
        previousGrid = {-1, -1};
        grid = g;
    }

    Move planNextStep(GridPos workerGrid, MoveDirection workerDir, GridPos blinkyGrid, bool flee) {
        GridPos next = grid;
        if (flee) {
            next = stepAwayFrom(workerGrid);
        } else {
            GridPos target = chaseTarget(workerGrid, workerDir, blinkyGrid);
            if (pathfinder) {
                auto step = pathfinder->shortestStep(grid, target);
                if (step == grid) step = pathfinder->shortestStep(grid, workerGrid);
                if (step == grid) step = randomStep();
                next = step;
            } else {
                next = randomStep();
            }
        }
        GridPos from = grid;
        previousGrid = from;
        grid = next;
        return {from, next};
    }

private:
    GridPos chaseTarget(GridPos workerGrid, MoveDirection workerDir, GridPos blinkyGrid) {
        switch (personality) {
        case BossPersonality::DirectChase:
            return workerGrid;
        case BossPersonality::AmbushAhead: {
            auto d = delta(workerDir);
            return {workerGrid.x + d.x * ambushTiles, workerGrid.y + d.y * ambushTiles};
        }
        case BossPersonality::TimidScatter:
            return Pathfinder::manhattanDist(grid, workerGrid) > scatterThreshold ? workerGrid : scatterGrid;
        case BossPersonality::Flanker: {
            auto d = delta(workerDir);
            GridPos pivot = {workerGrid.x + d.x * pivotTiles, workerGrid.y + d.y * pivotTiles};
            return {2 * pivot.x - blinkyGrid.x, 2 * pivot.y - blinkyGrid.y};
        }
        }
        return workerGrid;
    }

    GridPos stepAwayFrom(GridPos target) {
        if (!map) return grid;
        auto options = map->walkableNeighbors(grid);
        if (previousGrid.x >= 0 && options.size() > 1) {
            options.erase(std::remove(options.begin(), options.end(), previousGrid), options.end());
        }
        if (options.empty()) return grid;
        GridPos best = options[0];
        float bestDist = Pathfinder::manhattanDist(best, target);
        for (auto& o : options) {
            float d = Pathfinder::manhattanDist(o, target);
            if (d > bestDist) { bestDist = d; best = o; }
        }
        return best;
    }

    GridPos randomStep() {
        if (!map) return grid;
        auto options = map->walkableNeighbors(grid);
        if (previousGrid.x >= 0 && options.size() > 1) {
            options.erase(std::remove(options.begin(), options.end(), previousGrid), options.end());
        }
        if (options.empty()) return grid;
        return options[rand() % options.size()];
    }
};

} // namespace bm