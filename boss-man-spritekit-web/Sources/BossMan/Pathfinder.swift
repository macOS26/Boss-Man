import SpriteKit

// BFS shortest-path planner. Ported verbatim from
// boss-man-spritekit-swift/Boss-Man/Pathfinder.swift so bossman-web's
// BossAI gets the same chase shape as bossman-apple's:
//
//   - shortestStep returns path[1] (the next tile after `start` on the
//     shortest path to `goal`), nil if no path exists. When Pete sits in
//     a hideout, walkableNeighbors excludes him from the search so this
//     returns nil and BossAI falls back to randomStep -> wander.
//   - shortestPath returns the full path including start and goal.
//   - manhattanDistance is the static metric BossAI uses for the
//     flee target (max-distance neighbour) and the catch test.
final class Pathfinder {
    let map: GridMap

    init(map: GridMap) {
        self.map = map
    }

    static func manhattanDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    func shortestStep(from start: CGPoint, to goal: CGPoint) -> CGPoint? {
        guard let path = shortestPath(from: start, to: goal), path.count > 1 else { return nil }
        return path[1]
    }

    func shortestPath(from start: CGPoint, to goal: CGPoint) -> [CGPoint]? {
        var frontier = [start]
        var cameFrom: [Int: CGPoint] = [Pathfinder.gridKey(start): start]
        var head = 0

        while head < frontier.count {
            let current = frontier[head]
            head += 1

            if current == goal {
                var path = [current]
                var step = current
                while step != start {
                    guard let previous = cameFrom[Pathfinder.gridKey(step)] else { return nil }
                    step = previous
                    path.append(step)
                }
                return path.reversed()
            }

            for neighbor in map.walkableNeighbors(of: current) where cameFrom[Pathfinder.gridKey(neighbor)] == nil {
                frontier.append(neighbor)
                cameFrom[Pathfinder.gridKey(neighbor)] = current
            }
        }
        return nil
    }

    @inline(__always)
    private static func gridKey(_ grid: CGPoint) -> Int {
        Int(grid.x) &* 1000 &+ Int(grid.y)
    }
}
