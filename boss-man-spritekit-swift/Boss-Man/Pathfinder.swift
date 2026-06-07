import SpriteKit

// BFS shortest-path planner. Reuses flat scratch buffers keyed by cell index
// with a generation stamp, so a full BFS allocates nothing but the returned
// path (the earlier Dictionary-per-call version clustered into frame spikes on
// the 6-boss levels and made the hero stutter on the wasm single thread). The
// neighbour visit order matches GridMap.walkableNeighbors (right, left, up,
// down, then tunnel) so ties break identically and the chosen path is the same.
final class Pathfinder {
    let map: GridMap

    private var bufCols = 0
    private var bufRows = 0
    private var parentIdx: [Int] = []
    private var seenGen: [Int] = []
    private var gen = 0
    private var queue: [Int] = []

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
        let cols = map.columnCount, rows = map.rowCount
        guard cols > 0, rows > 0 else { return nil }
        if bufCols != cols || bufRows != rows {
            bufCols = cols
            bufRows = rows
            parentIdx = [Int](repeating: -1, count: cols * rows)
            seenGen   = [Int](repeating: 0,  count: cols * rows)
            gen = 0
        }

        let sc = Int(start.x), sr = Int(start.y)
        guard sc >= 0, sc < cols, sr >= 0, sr < rows else { return nil }
        let startIdx = sr * cols + sc
        let gc = Int(goal.x), gr = Int(goal.y)
        let goalIdx = (gc >= 0 && gc < cols && gr >= 0 && gr < rows) ? gr * cols + gc : -1

        gen += 1
        let g = gen
        queue.removeAll(keepingCapacity: true)
        queue.append(startIdx)
        seenGen[startIdx] = g
        parentIdx[startIdx] = startIdx
        var head = 0

        while head < queue.count {
            let cur = queue[head]
            head += 1
            if cur == goalIdx { return reconstruct(goalIdx: goalIdx, startIdx: startIdx, cols: cols) }
            let cc = cur % cols, cr = cur / cols
            visit(cc + 1, cr, parent: cur, g: g, cols: cols, rows: rows)
            visit(cc - 1, cr, parent: cur, g: g, cols: cols, rows: rows)
            visit(cc, cr + 1, parent: cur, g: g, cols: cols, rows: rows)
            visit(cc, cr - 1, parent: cur, g: g, cols: cols, rows: rows)
            if let partner = map.tunnelPartner(of: CGPoint(x: CGFloat(cc), y: CGFloat(cr))),
               map.isWalkable(partner), !map.isHideout(partner) {
                let pc = Int(partner.x), pr = Int(partner.y)
                if pc >= 0, pc < cols, pr >= 0, pr < rows {
                    let pIdx = pr * cols + pc
                    if seenGen[pIdx] != g {
                        seenGen[pIdx] = g
                        parentIdx[pIdx] = cur
                        queue.append(pIdx)
                    }
                }
            }
        }
        return nil
    }

    @inline(__always)
    private func visit(_ nx: Int, _ ny: Int, parent: Int, g: Int, cols: Int, rows: Int) {
        guard nx >= 0, nx < cols, ny >= 0, ny < rows else { return }
        let pt = CGPoint(x: CGFloat(nx), y: CGFloat(ny))
        guard map.isWalkable(pt), !map.isHideout(pt) else { return }
        let idx = ny * cols + nx
        if seenGen[idx] != g {
            seenGen[idx] = g
            parentIdx[idx] = parent
            queue.append(idx)
        }
    }

    private func reconstruct(goalIdx: Int, startIdx: Int, cols: Int) -> [CGPoint] {
        var idxPath = [goalIdx]
        var step = goalIdx
        while step != startIdx {
            step = parentIdx[step]
            idxPath.append(step)
        }
        return idxPath.reversed().map { CGPoint(x: CGFloat($0 % cols), y: CGFloat($0 / cols)) }
    }
}

