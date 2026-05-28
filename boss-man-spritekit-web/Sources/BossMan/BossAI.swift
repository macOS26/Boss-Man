import SpriteKit

// Personality + next-step planner for one boss. Ported verbatim from
// boss-man-spritekit-swift/Boss-Man/BossAI.swift so the four bosses behave
// the same in bossman-web as they do in bossman-apple:
//
//   .directChase                 — Bill, heads straight at Pete.
//   .ambushAhead(tiles:)         — Dom, targets the tile a few squares
//                                  ahead of where Pete is walking.
//   .timidScatter(scatter,thresh) — Stan, chases when close, retreats to
//                                   a scatter corner when far.
//   .flanker(pivotTiles:)        — Bob, reflects Bill's position about a
//                                   point a few tiles ahead of Pete.
//
// On every tile-centre arrival, BossController calls planNextStep which
// picks a target (per personality), asks Pathfinder for the shortest step
// toward it, and falls back to randomStep when no path exists (Pete is
// hidden, target is unreachable, etc.) so the boss keeps wandering.
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
    private weak var map: GridMap?

    init(homeGrid: CGPoint, detectionRange: CGFloat, personality: BossPersonality, map: GridMap) {
        self.homeGrid = homeGrid
        self.detectionRange = detectionRange
        self.personality = personality
        self.map = map
        self.grid = homeGrid
    }

    func teleport(to grid: CGPoint) {
        previousGrid = nil
        self.grid = grid
    }

    func planNextStep(workerGrid: CGPoint, workerDirection: MoveDirection?, blinkyGrid: CGPoint? = nil, flee: Bool = false) -> Move? {
        guard let map = map else { return nil }
        let next: CGPoint?
        if flee {
            next = stepAwayFrom(workerGrid, on: map)
        } else {
            let target = chaseTarget(workerGrid: workerGrid, workerDirection: workerDirection, blinkyGrid: blinkyGrid)
            next = Pathfinder.nextStep(from: grid, to: target, on: map)
                ?? Pathfinder.nextStep(from: grid, to: workerGrid, on: map)
                ?? randomStep(on: map)
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
            return manhattan(grid, workerGrid) > threshold ? workerGrid : scatter
        case .flanker(let pivotTiles):
            guard let dir = workerDirection, let blinky = blinkyGrid else { return workerGrid }
            let delta = dir.delta
            let pivot = CGPoint(x: workerGrid.x + CGFloat(delta.dx * pivotTiles),
                                y: workerGrid.y + CGFloat(delta.dy * pivotTiles))
            return CGPoint(x: 2 * pivot.x - blinky.x, y: 2 * pivot.y - blinky.y)
        }
    }

    private func stepAwayFrom(_ target: CGPoint, on map: GridMap) -> CGPoint? {
        var options = map.walkableNeighbors(of: grid)
        if let previousGrid, options.count > 1 {
            options.removeAll { $0 == previousGrid }
        }
        return options.max(by: {
            manhattan($0, target) < manhattan($1, target)
        })
    }

    private func randomStep(on map: GridMap) -> CGPoint? {
        var options = map.walkableNeighbors(of: grid)
        if let previousGrid, options.count > 1 {
            options.removeAll { $0 == previousGrid }
        }
        return options.randomElement()
    }

    private func manhattan(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        abs(a.x - b.x) + abs(a.y - b.y)
    }
}

// Per-blueprint config matching bossman-apple's BossController.blueprints.
// Index 0..3 -> Bill / Dom / Bob / Stan with their personalities + speeds.
enum BossBlueprint {
    static let table: [(personality: BossPersonality, speed: Double)] = [
        (.directChase,                                                          1.00),  // Bill
        (.ambushAhead(tiles: 4),                                                0.85),  // Dom
        (.flanker(pivotTiles: 2),                                               0.78),  // Bob
        (.timidScatter(scatterGrid: CGPoint(x: 1, y: 1), threshold: 8),         0.70),  // Stan
    ]
}
