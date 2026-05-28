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
    private var waterPelletNodes: [CGPoint: SKNode] = [:]
    private var waterGunNodes: [CGPoint: SKNode] = [:]
    // Machine name (Strings.Machine.*) + scene node, indexed by tile.
    // bossman-apple stores these in a [String: SKNode] via the node's
    // SKNode.name; we go by grid so handlePeteArrival can look up by tile.
    private(set) var machineNodes: [CGPoint: (name: String, node: SKNode)] = [:]
    private(set) var brownBoxNodes: [CGPoint: SKNode] = [:]

    init(map: GridMap) { self.map = map }

    @discardableResult
    func build(in scene: SKNode) -> Int {
        // Backdrop — solid dark fill behind the maze. The per-tile floor
        // checker sits at z=-9; walls and pickups go on top.
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

                // Floor checker tile under every cell. The macOS edition
                // bakes this into a single texture; we draw one SKShapeNode
                // per tile because we don't have offscreen CG rendering.
                let alt = (rowIndex + columnIndex).isMultiple(of: 2)
                let floor = SpriteFactory.floorTile(size: map.tileSize, alternate: alt)
                floor.position = position
                floor.zPosition = -9
                scene.addChild(floor)

                switch char {
                case Strings.Tile.wallChar:
                    addWall(at: position, in: scene)

                case Strings.Tile.dotChar, Strings.Tile.hideoutChar:
                    if let dot = addDot(at: position, in: scene) {
                        dotNodes[grid] = dot; dotCount += 1
                    }

                case Strings.Tile.goldDiscChar:
                    goldDiscPositions.append(grid)
                    let gold = SpriteFactory.goldDiscVisual(radius: map.tileSize * 0.28)
                    gold.position = position
                    gold.zPosition = 6
                    gold.run(.repeatForever(.sequence([
                        .scale(to: 1.25, duration: 0.35),
                        .scale(to: 1.0,  duration: 0.35),
                    ])))
                    scene.addChild(gold)
                    goldNodes[grid] = gold

                case Strings.Tile.waterGunChar:
                    waterGunPositions.append(grid)
                    let gun = SKLabelNode(text: Strings.Emoji.waterGun)
                    gun.fontSize = map.tileSize * 0.55
                    gun.verticalAlignmentMode = .center
                    gun.horizontalAlignmentMode = .center
                    gun.position = position
                    gun.zPosition = 6
                    gun.run(.repeatForever(.sequence([
                        .scale(to: 1.25, duration: 0.35),
                        .scale(to: 1.0,  duration: 0.35),
                    ])))
                    scene.addChild(gun)
                    waterGunNodes[grid] = gun

                case Strings.Tile.waterPelletChar:
                    waterPelletPositions.append(grid)
                    let pellet = SpriteFactory.waterPelletVisual(radius: map.tileSize * 0.32)
                    pellet.position = position
                    pellet.zPosition = 6
                    pellet.run(.repeatForever(.sequence([
                        .scale(to: 1.3, duration: 0.4),
                        .scale(to: 1.0, duration: 0.4),
                    ])))
                    scene.addChild(pellet)
                    waterPelletNodes[grid] = pellet

                case Strings.Tile.printerChar:
                    let n = addMachineEmoji(Strings.Emoji.printer, at: position, in: scene)
                    machineNodes[grid] = (Strings.Machine.printer, n)
                case Strings.Tile.faxChar:
                    let n = addMachineEmoji(Strings.Emoji.fax, at: position, in: scene)
                    machineNodes[grid] = (Strings.Machine.fax, n)
                case Strings.Tile.coverSheetChar:
                    let n = addMachineEmoji(Strings.Emoji.coverSheet, at: position, in: scene)
                    machineNodes[grid] = (Strings.Machine.coverSheet, n)
                case Strings.Tile.bookBinderChar:
                    let n = addMachineEmoji(Strings.Emoji.bookBinder, at: position, in: scene)
                    machineNodes[grid] = (Strings.Machine.bookBinder, n)
                case Strings.Tile.brownBoxChar:
                    let n = addBrownBoxEmoji(Strings.Emoji.brownBox, at: position, in: scene)
                    brownBoxNodes[grid] = n

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
    @discardableResult
    func collectWaterPellet(at grid: CGPoint) -> Bool {
        guard let node = waterPelletNodes[grid] else { return false }
        node.removeFromParent()
        waterPelletNodes.removeValue(forKey: grid)
        return true
    }
    @discardableResult
    func collectWaterGun(at grid: CGPoint) -> Bool {
        guard let node = waterGunNodes[grid] else { return false }
        node.removeFromParent()
        waterGunNodes.removeValue(forKey: grid)
        return true
    }

    // MARK: - Helpers

    private func addWall(at position: CGPoint, in scene: SKNode) {
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


    // TPS printer / fax / cover-sheet / book-binder — 26pt emoji label,
    // no pulse (matches bossman-apple's machine glyphs).
    private func addMachineEmoji(_ emoji: String, at position: CGPoint, in scene: SKNode) -> SKNode {
        let label = SKLabelNode(text: emoji)
        label.fontSize = 26
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = position
        label.zPosition = 6
        scene.addChild(label)
        return label
    }

    // Brown TPS delivery box. Slightly larger glyph (28pt) and sits one
    // z-layer below the other machines, matching bossman-apple.
    private func addBrownBoxEmoji(_ emoji: String, at position: CGPoint, in scene: SKNode) -> SKNode {
        let label = SKLabelNode(text: emoji)
        label.fontSize = 28
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = position
        label.zPosition = 4
        scene.addChild(label)
        return label
    }

    // Mark a machine collected: fade it to 0.55 alpha (matching bossman-
    // apple's grayOutMachine) and drop it from the active map so Pete
    // can't double-collect. Returns the machine name + scene position.
    @discardableResult
    func collectMachine(at grid: CGPoint) -> (name: String, position: CGPoint)? {
        guard let m = machineNodes[grid] else { return nil }
        machineNodes.removeValue(forKey: grid)
        m.node.run(.fadeAlpha(to: 0.55, duration: 0.2))
        return (m.name, m.node.position)
    }

    // Returns true if Pete stepped onto a brown box tile.
    func touchedBrownBox(at grid: CGPoint) -> CGPoint? {
        guard let n = brownBoxNodes[grid] else { return nil }
        return n.position
    }

    private func addDot(at position: CGPoint, in scene: SKNode) -> SKNode? {
        let dot = SpriteFactory.dotVisual()
        dot.position = position
        dot.zPosition = 1
        scene.addChild(dot)
        return dot
    }
}
