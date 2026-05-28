import SpriteKit

// Verbatim port of boss-man-spritekit-swift/Boss-Man/BossAI.swift.
// Owns the boss's grid position and previousGrid (the cell it just left,
// used to avoid U-turns in the random-wander fallback). The controller
// asks for the next step at every tile-centre arrival; BossAI advances
// its own grid and returns the Move so the controller can animate.
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

// Per-blueprint config matching bossman-apple's BossController.blueprints.
// Indices 0..3 map to Bill / Dom / Bob / Stan with their personality + speed.
enum BossBlueprint {
    static let table: [(personality: BossPersonality, speed: Double)] = [
        (.directChase,                                                          1.00),  // Bill
        (.ambushAhead(tiles: 4),                                                0.85),  // Dom
        (.flanker(pivotTiles: 2),                                               0.78),  // Bob
        (.timidScatter(scatterGrid: CGPoint(x: 1, y: 1), threshold: 8),         0.70),  // Stan
    ]
}
