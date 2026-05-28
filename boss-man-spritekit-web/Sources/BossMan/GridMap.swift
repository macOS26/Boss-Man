import SpriteKit

// Tile-grid math shared by the maze, Pete, and the boss. Rows are stored top
// to bottom; positions are returned bottom-up (SpriteKit y-up), matching the
// SuperBox64 SpriteKit world.
//
// tunnelPartner builds the Pac-Man-style wrap pairs at parse time: a top-row
// floor that has a matching bottom-row floor (or a left/right edge pair) is
// linked so walkers can step off one side and emerge on the other.
final class GridMap {
    let tileSize: CGFloat
    var yOffset: CGFloat = 0
    private(set) var rows: [String] = []
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

    var columnCount: Int { rows.first?.count ?? 0 }
    var rowCount: Int    { rows.count }

    // World-coordinate center of the tile at `grid` (col, row) in y-up space.
    func point(for grid: CGPoint) -> CGPoint {
        CGPoint(x: grid.x * tileSize + tileSize / 2,
                y: grid.y * tileSize + tileSize / 2 + yOffset)
    }

    // The character at this grid coordinate, treating row 0 as the bottom row
    // and rows.first as the top of the maze.
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

    func isHideout(_ grid: CGPoint) -> Bool {
        tile(at: grid) == Strings.Tile.hideoutChar
    }

    func tunnelPartner(of grid: CGPoint) -> CGPoint? {
        for (a, b) in tunnelPairs {
            if a == grid { return b }
            if b == grid { return a }
        }
        return nil
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

    private func rebuildTunnels() {
        tunnelPairs.removeAll()
        guard let firstRow = rows.first, !firstRow.isEmpty, rows.count >= 2 else { return }
        let cols = firstRow.count
        let lastCol = cols - 1
        let topY = rows.count - 1
        let floor = Strings.Tile.floorChar

        // Vertical wrap: top-row floor + bottom-row floor in the same column.
        let topChars    = Array(rows[0])
        let bottomChars = Array(rows[rows.count - 1])
        for col in 0..<cols where col < topChars.count && col < bottomChars.count {
            if topChars[col] == floor && bottomChars[col] == floor {
                tunnelPairs.append((CGPoint(x: col, y: topY), CGPoint(x: col, y: 0)))
            }
        }
        // Horizontal wrap: any row with floor at both edges links its ends.
        for rowIndex in 0..<rows.count {
            let chars = Array(rows[rowIndex])
            guard chars.count >= cols, chars.first == floor, chars[lastCol] == floor else { continue }
            let gridY = rows.count - 1 - rowIndex
            tunnelPairs.append((CGPoint(x: 0, y: gridY), CGPoint(x: lastCol, y: gridY)))
        }
    }
}
