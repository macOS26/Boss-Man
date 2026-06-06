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
    // Horizontal centering offset (web centres a narrow maze in a fixed-width
    // scene). Defaults to 0 so apple — whose scene matches the maze width —
    // is unchanged. With this in point(for:), a Pete/boss node placed at
    // gridMap.point(for:) lands centred without any per-mover offset, so apple's
    // WorkerController (which positions via gridMap.point) drops in unchanged.
    var xOffset: CGFloat = 0
    private(set) var rows: [String] = []
    private var byteRows: [[UInt8]] = []
    private var tunnelPairs: [(CGPoint, CGPoint)] = []

    init(tileSize: CGFloat, rows: [String] = []) {
        self.tileSize = tileSize
        self.rows = rows
        byteRows = rows.map { Array($0.utf8) }
        rebuildTunnels()
    }

    func setRows(_ rows: [String]) {
        self.rows = rows
        byteRows = rows.map { Array($0.utf8) }
        rebuildTunnels()
    }

    var columnCount: Int { byteRows.first?.count ?? 0 }
    var rowCount: Int    { byteRows.count }

    // World-coordinate center of the tile at `grid` (col, row) in y-up space.
    func point(for grid: CGPoint) -> CGPoint {
        CGPoint(x: grid.x * tileSize + tileSize / 2 + xOffset,
                y: grid.y * tileSize + tileSize / 2 + yOffset)
    }

    // The character at this grid coordinate, treating row 0 as the bottom row
    // and rows.first as the top of the maze.
    func tile(at grid: CGPoint) -> UInt8? {
        let row = byteRows.count - 1 - Int(grid.y)
        let column = Int(grid.x)
        guard row >= 0, row < byteRows.count,
              column >= 0, column < byteRows[row].count else { return nil }
        return byteRows[row][column]
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

    // The side-to-side doorway: the row whose left and right edges are both
    // open (walkable) straight across. Returns the right mouth (spawn) and the
    // left mouth (exit), or nil if no row has an aligned horizontal tunnel.
    func horizontalDoorway() -> (spawn: CGPoint, exit: CGPoint)? {
        let cols = columnCount
        guard cols > 1 else { return nil }
        for y in 0..<rowCount {
            let yf = CGFloat(y)
            if isWalkable(CGPoint(x: 0, y: yf)) && isWalkable(CGPoint(x: CGFloat(cols - 1), y: yf)) {
                return (CGPoint(x: CGFloat(cols - 1), y: yf), CGPoint(x: 0, y: yf))
            }
        }
        return nil
    }

    private func rebuildTunnels() {
        tunnelPairs.removeAll()
        guard let firstRow = byteRows.first, !firstRow.isEmpty, byteRows.count >= 2 else { return }
        let cols = firstRow.count
        let lastCol = cols - 1
        let topY = byteRows.count - 1
        let floor = Strings.Tile.floorChar

        // Vertical wrap: top-row floor + bottom-row floor in the same column.
        let topChars    = byteRows[0]
        let bottomChars = byteRows[byteRows.count - 1]
        for col in 0..<cols where col < topChars.count && col < bottomChars.count {
            if topChars[col] == floor && bottomChars[col] == floor {
                tunnelPairs.append((CGPoint(x: col, y: topY), CGPoint(x: col, y: 0)))
            }
        }
        // Horizontal wrap: any row with floor at both edges links its ends.
        for rowIndex in 0..<byteRows.count {
            let chars = byteRows[rowIndex]
            guard chars.count >= cols, chars.first == floor, chars[lastCol] == floor else { continue }
            let gridY = byteRows.count - 1 - rowIndex
            tunnelPairs.append((CGPoint(x: 0, y: gridY), CGPoint(x: lastCol, y: gridY)))
        }
    }
}
