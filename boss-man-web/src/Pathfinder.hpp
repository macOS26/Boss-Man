#pragma once
#include "GridMap.hpp"
#include "MoveDirection.hpp"
#include <queue>
#include <unordered_map>

namespace bm {

class Pathfinder {
public:
    const GridMap& map;

    Pathfinder(const GridMap& m) : map(m) {}

    static float manhattanDist(GridPos a, GridPos b) {
        return (float)(abs(a.x - b.x) + abs(a.y - b.y));
    }

    GridPos shortestStep(GridPos start, GridPos goal) const {
        auto path = shortestPath(start, goal);
        if (path.size() > 1) return path[1];
        return start;
    }

    std::vector<GridPos> shortestPath(GridPos start, GridPos goal) const {
        std::queue<GridPos> frontier;
        std::unordered_map<GridPos, GridPos> cameFrom;

        frontier.push(start);
        cameFrom[start] = start;

        while (!frontier.empty()) {
            GridPos current = frontier.front();
            frontier.pop();

            if (current == goal) {
                std::vector<GridPos> path = {current};
                GridPos step = current;
                while (step != start) {
                    auto it = cameFrom.find(step);
                    if (it == cameFrom.end()) return {};
                    step = it->second;
                    path.push_back(step);
                }
                std::reverse(path.begin(), path.end());
                return path;
            }

            for (auto& next : map.walkableNeighbors(current)) {
                if (cameFrom.find(next) == cameFrom.end()) {
                    frontier.push(next);
                    cameFrom[next] = current;
                }
            }
        }
        return {};
    }
};

} // namespace bm