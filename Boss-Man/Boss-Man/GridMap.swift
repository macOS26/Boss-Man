import CoreGraphics

final class GridMap {
    let tileSize: CGFloat
    private(set) var rows: [String]
    // Stored as ordered pairs (a,b) → on lookup we check both sides.
    // Using a small array (typically ≤ 4 pairs) avoids the macOS-15-only
    // CGPoint:Hashable conformance.
    private var tunnelPairs: [(CGPoint, CGPoint)] = []

    init(tileSize: CGFloat, rows: [String] = []) {
        self.tileSize = tileSize
        self.rows = rows
        rebuildTunnels()
    }

    func setRows(_ rows: [String]) {
        self.rows = rows
        rebuildTunnels()
    }

    /// Auto-detect tunnels from gaps in the perimeter:
    ///   - any column with a space (floor) in BOTH the top and bottom row pairs (col, topY) ↔ (col, 0)
    ///   - any row with a space in BOTH the leftmost and rightmost columns pairs (0, y) ↔ (lastCol, y)
    /// Levels control tunnel placement just by painting floor in the wall ring.
    private func rebuildTunnels() {
        tunnelPairs.removeAll()
        guard let firstRow = rows.first, !firstRow.isEmpty, rows.count >= 2 else { return }
        let rowCount = rows.count
        let colCount = firstRow.count
        let topY = rowCount - 1
        let lastCol = colCount - 1
        let floor = Strings.Tile.floorChar

        // Top/bottom border (vertical tunnels).
        let topChars = Array(rows[0])
        let bottomChars = Array(rows[rowCount - 1])
        for col in 0..<colCount where col < topChars.count && col < bottomChars.count {
            if topChars[col] == floor && bottomChars[col] == floor {
                tunnelPairs.append((CGPoint(x: col, y: topY), CGPoint(x: col, y: 0)))
            }
        }
        // Left/right border (horizontal tunnels).
        for rowIndex in 0..<rowCount {
            let chars = Array(rows[rowIndex])
            guard chars.count >= colCount, chars.first == floor, chars[lastCol] == floor else { continue }
            let gridY = rowCount - 1 - rowIndex
            tunnelPairs.append((CGPoint(x: 0, y: gridY), CGPoint(x: lastCol, y: gridY)))
        }
    }

    func point(for grid: CGPoint) -> CGPoint {
        CGPoint(x: grid.x * tileSize + tileSize / 2,
                y: grid.y * tileSize + tileSize / 2)
    }

    func tile(at grid: CGPoint) -> Character? {
        let row = rows.count - 1 - Int(grid.y)
        let column = Int(grid.x)
        guard row >= 0, row < rows.count,
              column >= 0, column < rows[row].count else { return nil }
        return Array(rows[row])[column]
    }

    func isWalkable(_ grid: CGPoint) -> Bool {
        guard let character = tile(at: grid) else { return false }
        return character != Strings.Tile.wallChar
    }

    func tunnelPartner(of grid: CGPoint) -> CGPoint? {
        for (a, b) in tunnelPairs {
            if a == grid { return b }
            if b == grid { return a }
        }
        return nil
    }

    func isHideout(_ grid: CGPoint) -> Bool {
        tile(at: grid) == Strings.Tile.hideoutChar
    }

    func walkableNeighbors(of grid: CGPoint) -> [CGPoint] {
        var result: [CGPoint] = []
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let next = CGPoint(x: grid.x + CGFloat(dx), y: grid.y + CGFloat(dy))
            if isWalkable(next) && !isHideout(next) { result.append(next) }
        }
        if let partner = tunnelPartner(of: grid), isWalkable(partner), !isHideout(partner) {
            result.append(partner)
        }
        return result
    }
}
