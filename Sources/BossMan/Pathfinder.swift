import CoreGraphics

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
        var cameFrom = [gridKey(start): start]
        var head = 0

        while head < frontier.count {
            let current = frontier[head]
            head += 1

            if current == goal {
                var path = [current]
                var step = current
                while step != start {
                    guard let previous = cameFrom[gridKey(step)] else { return nil }
                    step = previous
                    path.append(step)
                }
                return path.reversed()
            }

            for neighbor in map.walkableNeighbors(of: current) where cameFrom[gridKey(neighbor)] == nil {
                frontier.append(neighbor)
                cameFrom[gridKey(neighbor)] = current
            }
        }
        return nil
    }

    private func gridKey(_ grid: CGPoint) -> String {
        "\(Int(grid.x)),\(Int(grid.y))"
    }
}
