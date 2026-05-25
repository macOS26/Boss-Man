import CoreGraphics

final class GridMap {
    let tileSize: CGFloat
    var yOffset: CGFloat = 0
    private(set) var rows: [String]
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

    private func rebuildTunnels() {
        tunnelPairs.removeAll()
        guard let firstRow = rows.first, !firstRow.isEmpty, rows.count >= 2 else { return }
        let rowCount = rows.count
        let colCount = firstRow.count
        let topY = rowCount - 1
        let lastCol = colCount - 1
        let floor = Strings.Tile.floorChar

        let topChars = Array(rows[0])
        let bottomChars = Array(rows[rowCount - 1])
        for col in 0..<colCount where col < topChars.count && col < bottomChars.count {
            if topChars[col] == floor && bottomChars[col] == floor {
                tunnelPairs.append((CGPoint(x: col, y: topY), CGPoint(x: col, y: 0)))
            }
        }
        for rowIndex in 0..<rowCount {
            let chars = Array(rows[rowIndex])
            guard chars.count >= colCount, chars.first == floor, chars[lastCol] == floor else { continue }
            let gridY = rowCount - 1 - rowIndex
            tunnelPairs.append((CGPoint(x: 0, y: gridY), CGPoint(x: lastCol, y: gridY)))
        }
    }

    func point(for grid: CGPoint) -> CGPoint {
        CGPoint(x: grid.x * tileSize + tileSize / 2,
                y: grid.y * tileSize + tileSize / 2 + yOffset)
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
