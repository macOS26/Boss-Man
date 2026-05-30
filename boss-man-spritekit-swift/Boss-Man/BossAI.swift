import SpriteKit

enum BossPersonality {
    case directChase
    case ambushAhead(tiles: Int)
    case timidScatter(scatterGrid: CGPoint, threshold: CGFloat)
    case flanker(pivotTiles: Int)
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

    func planNextStep(workerGrid: CGPoint, workerDirection: MoveDirection?, blinkyGrid: CGPoint? = nil, flee: Bool = false) -> Move? {
        let next: CGPoint?
        if flee {
            next = stepAwayFrom(workerGrid)
        } else {
            let target = chaseTarget(workerGrid: workerGrid, workerDirection: workerDirection, blinkyGrid: blinkyGrid)
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

    private func chaseTarget(workerGrid: CGPoint, workerDirection: MoveDirection?, blinkyGrid: CGPoint?) -> CGPoint {
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
        case .flanker(let pivotTiles):
            guard let dir = workerDirection, let blinky = blinkyGrid else { return workerGrid }
            let delta = dir.delta
            let pivot = CGPoint(x: workerGrid.x + CGFloat(delta.dx * pivotTiles),
                                y: workerGrid.y + CGFloat(delta.dy * pivotTiles))
            return CGPoint(x: 2 * pivot.x - blinky.x, y: 2 * pivot.y - blinky.y)
        }
    }

    private func stepAwayFrom(_ target: CGPoint) -> CGPoint? {
        var options = map.walkableNeighbors(of: grid)
        if let previousGrid, options.count > 1 {
            options.removeAll { $0 == previousGrid }
        }
        return options.max(by: {
            Pathfinder.manhattanDistance($0, target) < Pathfinder.manhattanDistance($1, target)
        })
    }

    private func randomStep() -> CGPoint? {
        var options = map.walkableNeighbors(of: grid)
        if let previousGrid, options.count > 1 {
            options.removeAll { $0 == previousGrid }
        }
        return options.randomElement()
    }
}
