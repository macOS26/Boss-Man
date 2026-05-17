import CoreGraphics

final class BossAI {
    struct Move {
        let from: CGPoint
        let to: CGPoint
    }

    let homeGrid: CGPoint
    let detectionRange: CGFloat
    private(set) var grid: CGPoint
    private var previousGrid: CGPoint?
    private let pathfinder: Pathfinder
    private let map: GridMap

    init(homeGrid: CGPoint, detectionRange: CGFloat, pathfinder: Pathfinder, map: GridMap) {
        self.homeGrid = homeGrid
        self.detectionRange = detectionRange
        self.pathfinder = pathfinder
        self.map = map
        self.grid = homeGrid
    }

    func teleport(to grid: CGPoint) {
        previousGrid = nil
        self.grid = grid
    }

    func planNextStep(towards target: CGPoint, flee: Bool = false) -> Move? {
        let next: CGPoint?
        if flee {
            next = stepAwayFrom(target)
        } else {
            next = pathfinder.shortestStep(from: grid, to: target) ?? randomStep()
        }
        guard let next else { return nil }
        let from = grid
        previousGrid = from
        grid = next
        return Move(from: from, to: next)
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
