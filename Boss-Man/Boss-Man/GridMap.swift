import CoreGraphics

final class GridMap {
    let tileSize: CGFloat
    private(set) var rows: [String]

    init(tileSize: CGFloat, rows: [String] = []) {
        self.tileSize = tileSize
        self.rows = rows
    }

    func setRows(_ rows: [String]) {
        self.rows = rows
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
        let x = Int(grid.x), y = Int(grid.y)
        if y == 8 && x == 0 { return CGPoint(x: 35, y: 8) }
        if y == 8 && x == 35 { return CGPoint(x: 0, y: 8) }
        if x == 18 && y == 0 { return CGPoint(x: 18, y: 16) }
        if x == 18 && y == 16 { return CGPoint(x: 18, y: 0) }
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
