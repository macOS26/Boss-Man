import SpriteKit

// MazeBuilder, wasm port — first pass.
//
// The macOS original ships a richer pipeline (SKTileMapNode dot layer, a
// pre-rendered wall texture batched into one sprite, machine-emoji glyphs,
// brown-box decor). The wasm version we ship today is the leanest thing
// that puts something playable on the screen:
//
//   - Every '#' cell becomes a SpriteFactory.wallTile node + a static
//     rectangle Box2D body so Pete and the boss collide with the maze.
//   - Every '.', 'H', or boss-spawn cell drops a small dot circle the
//     worker can sweep up.
//   - Goldener tiles ('O') become gold-disc pickups via SpriteFactory.
//   - Water-pellet ('A') and water-gun ('G') drops are recorded but
//     rendered as the same gold/water visuals from SpriteFactory.
//   - Spawn positions for Pete (W) and bosses (1..4) are exposed via
//     readonly properties so the scene can place the actors after build.
//
// build(in:) returns the dot count so GameScene knows when the level is
// cleared.
final class MazeBuilder {
    let map: GridMap

    private(set) var workerSpawn: CGPoint?
    private(set) var bossSpawns: [(index: Int, position: CGPoint)] = []
    private(set) var goldDiscPositions: [CGPoint] = []
    private(set) var waterGunPositions: [CGPoint] = []
    private(set) var waterPelletPositions: [CGPoint] = []

    // Sprite handles by grid coord, so the game can collect pellets/dots
    // later without re-walking the whole tree.
    private var dotNodes: [CGPoint: SKNode] = [:]
    private var goldNodes: [CGPoint: SKNode] = [:]

    init(map: GridMap) { self.map = map }

    @discardableResult
    func build(in scene: SKScene) -> Int {
        // Backdrop — solid dark fill behind the maze.
        let bg = SKShapeNode(rect: CGRect(x: 0, y: 0,
                                          width: CGFloat(map.columnCount) * map.tileSize,
                                          height: CGFloat(map.rowCount) * map.tileSize))
        bg.fillColor = SpriteFactory.mazeBackground
        bg.strokeColor = .clear
        bg.position.y = map.yOffset
        bg.zPosition = -10
        scene.addChild(bg)

        var dotCount = 0

        for (rowIndex, row) in map.rows.reversed().enumerated() {
            for (columnIndex, char) in row.enumerated() {
                let grid = CGPoint(x: columnIndex, y: rowIndex)
                let position = map.point(for: grid)

                switch char {
                case Strings.Tile.wallChar:
                    addWall(at: position, in: scene)

                case Strings.Tile.dotChar, Strings.Tile.hideoutChar:
                    if let dot = addDot(at: position, in: scene) {
                        dotNodes[grid] = dot; dotCount += 1
                    }

                case Strings.Tile.goldDiscChar:
                    goldDiscPositions.append(grid)
                    let gold = SpriteFactory.goldDiscVisual(radius: map.tileSize * 0.32)
                    gold.position = position
                    gold.zPosition = 1
                    scene.addChild(gold)
                    goldNodes[grid] = gold

                case Strings.Tile.waterGunChar:
                    waterGunPositions.append(grid)
                    let pellet = SpriteFactory.waterPelletVisual(radius: map.tileSize * 0.30)
                    pellet.position = position
                    pellet.zPosition = 1
                    scene.addChild(pellet)

                case Strings.Tile.waterPelletChar:
                    waterPelletPositions.append(grid)
                    let pellet = SpriteFactory.waterPelletVisual(radius: map.tileSize * 0.22)
                    pellet.position = position
                    pellet.zPosition = 1
                    scene.addChild(pellet)

                case Strings.Tile.workerChar:
                    workerSpawn = grid
                    // Worker tile is walkable + has a dot underneath.
                    if let dot = addDot(at: position, in: scene) {
                        dotNodes[grid] = dot; dotCount += 1
                    }

                case Strings.Tile.boss1Char: bossSpawns.append((0, grid))
                case Strings.Tile.boss2Char: bossSpawns.append((1, grid))
                case Strings.Tile.boss3Char: bossSpawns.append((2, grid))
                case Strings.Tile.boss4Char: bossSpawns.append((3, grid))

                default: break
                }
            }
        }

        return dotCount
    }

    // Collect (visually + bookkeeping) the dot at this grid coord. Returns
    // true if a dot was actually consumed.
    @discardableResult
    func collectDot(at grid: CGPoint) -> Bool {
        guard let node = dotNodes[grid] else { return false }
        node.removeFromParent()
        dotNodes.removeValue(forKey: grid)
        return true
    }
    @discardableResult
    func collectGold(at grid: CGPoint) -> Bool {
        guard let node = goldNodes[grid] else { return false }
        node.removeFromParent()
        goldNodes.removeValue(forKey: grid)
        return true
    }

    // MARK: - Helpers

    private func addWall(at position: CGPoint, in scene: SKScene) {
        let wall = SpriteFactory.wallTile(size: map.tileSize)
        wall.position = position
        wall.zPosition = 0
        let body = SKPhysicsBody(rectangleOf: CGSize(width: map.tileSize,
                                                     height: map.tileSize))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.wall
        body.collisionBitMask = PhysicsCategory.worker | PhysicsCategory.boss
        body.contactTestBitMask = 0
        wall.physicsBody = body
        scene.addChild(wall)
    }

    private func addDot(at position: CGPoint, in scene: SKScene) -> SKNode? {
        let dot = SpriteFactory.dotVisual(radius: map.tileSize * 0.10)
        dot.position = position
        dot.zPosition = 1
        scene.addChild(dot)
        return dot
    }
}
