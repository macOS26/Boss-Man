import CoreGraphics

/// Per-boss chase personality — mirrors the four classic Pac-Man ghosts.
enum BossPersonality {
    /// Blinky-style: head straight for the worker's tile.
    case directChase
    /// Pinky-style: aim for the tile N steps ahead of the worker's current direction.
    case ambushAhead(tiles: Int)
    /// Clyde-style: chase until inside `threshold` tiles of the worker, then retreat to `scatterGrid`.
    case timidScatter(scatterGrid: CGPoint, threshold: CGFloat)
}

final class BossAI {
    struct Move {
        let from: CGPoint
        let to: CGPoint
    }

    let homeGrid: CGPoint
    let detectionRange: CGFloat
    let personality: BossPersonality
    private(set) var grid: CGPoint
    private var previousGrid: CGPoint?
    private let pathfinder: Pathfinder
    private let map: GridMap

    init(homeGrid: CGPoint, detectionRange: CGFloat, personality: BossPersonality, pathfinder: Pathfinder, map: GridMap) {
        self.homeGrid = homeGrid
        self.detectionRange = detectionRange
        self.personality = personality
        self.pathfinder = pathfinder
        self.map = map
        self.grid = homeGrid
    }

    func teleport(to grid: CGPoint) {
        previousGrid = nil
        self.grid = grid
    }

    func planNextStep(workerGrid: CGPoint, workerDirection: MoveDirection?, flee: Bool = false) -> Move? {
        let next: CGPoint?
        if flee {
            next = stepAwayFrom(workerGrid)
        } else {
            let target = chaseTarget(workerGrid: workerGrid, workerDirection: workerDirection)
            // Try personality target first; if unreachable (wall, off-grid), degrade to direct
            // chase, then to a random step so the boss never freezes.
            next = pathfinder.shortestStep(from: grid, to: target)
                ?? pathfinder.shortestStep(from: grid, to: workerGrid)
                ?? randomStep()
        }
        guard let next else { return nil }
        let from = grid
        previousGrid = from
        grid = next
        return Move(from: from, to: next)
    }

    private func chaseTarget(workerGrid: CGPoint, workerDirection: MoveDirection?) -> CGPoint {
        switch personality {
        case .directChase:
            return workerGrid
        case .ambushAhead(let tiles):
            guard let dir = workerDirection else { return workerGrid }
            let delta = dir.delta
            return CGPoint(x: workerGrid.x + CGFloat(delta.dx * tiles),
                           y: workerGrid.y + CGFloat(delta.dy * tiles))
        case .timidScatter(let scatter, let threshold):
            return Pathfinder.manhattanDistance(grid, workerGrid) > threshold ? workerGrid : scatter
        }
    }

    private func stepAwayFrom(_ target: CGPoint) -> CGPoint? {
        var options = map.walkableNeighbors(of: grid)
        if let previousGrid, options.count > 1 {
            options.removeAll { $0 == previousGrid }
        }
        var bestOption: CGPoint?
        var bestDistance = -1
        for option in options {
            let distance = pathfinder.shortestPath(from: option, to: target)?.count ?? Int.max
            if distance > bestDistance {
                bestDistance = distance
                bestOption = option
            }
        }
        return bestOption
    }

    private func randomStep() -> CGPoint? {
        var options = map.walkableNeighbors(of: grid)
        if let previousGrid, options.count > 1 {
            options.removeAll { $0 == previousGrid }
        }
        return options.randomElement()
    }
}
