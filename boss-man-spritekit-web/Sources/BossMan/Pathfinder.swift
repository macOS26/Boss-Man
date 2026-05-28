import SpriteKit

// BFS shortest-path planner over the maze grid. Used by BossAI to pick the
// next direction at each tile centre: ask "from where the boss is now, which
// of the (up to four) walkable neighbours is one step closer to Pete?" and
// pick the corresponding direction.
//
// Honors tunnel wraps (GridMap.walkableNeighbors already includes the
// partner tile) and excludes hideouts (only the boss-spawn cells can be
// hideouts and we never want pathfinding through them).
enum Pathfinder {
    // Returns the next grid coord on the shortest path from `start` to
    // `target`, or nil if there's no reachable path. Visits are limited to
    // rows*cols cells so worst-case BFS is linear in maze size.
    static func nextStep(from start: CGPoint, to target: CGPoint, on map: GridMap) -> CGPoint? {
        if start == target { return nil }

        // Each entry: the grid coord, plus the FIRST step we took from start
        // to reach it. Carrying the first-step makes the answer fall out of
        // BFS without rebuilding the parent chain.
        var queue: [(node: CGPoint, firstStep: CGPoint)] = []
        var visited = Set<CGPoint>()
        visited.insert(start)
        for n in map.walkableNeighbors(of: start) {
            if n == target { return n }
            queue.append((n, n))
            visited.insert(n)
        }
        while !queue.isEmpty {
            let (node, firstStep) = queue.removeFirst()
            if node == target { return firstStep }
            for n in map.walkableNeighbors(of: node) where !visited.contains(n) {
                if n == target { return firstStep }
                queue.append((n, firstStep))
                visited.insert(n)
            }
        }
        return nil
    }
}
