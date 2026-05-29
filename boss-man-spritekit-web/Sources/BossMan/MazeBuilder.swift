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
    // Per-level cubicle color, written by GameScene before each build().
    // bossman-apple stores this as MazeBuilder.cubicleColor: NSColor.
    var cubicleColor: SKColor = SpriteFactory.cubicleColors[0]

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

    // One shared dot texture (color-invariant) baked once, reused for every
    // pellet — mirrors bossman-apple's single pelletTexture. Cached across
    // levels so we only pay the offscreen bake one time.
    private var dotTexture: SKTexture?

    init(map: GridMap) { self.map = map }

    @discardableResult
    func build(in scene: SKNode, view: SKView? = nil) -> Int {
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

        // Bake the single shared dot texture once (color-invariant yellow square).
        if dotTexture == nil, let view {
            dotTexture = view.texture(from: SpriteFactory.dotVisual())
        }

        // Floor checker + wall VISUALS are static for the level, so we collect
        // them in a throwaway tree, bake it to one texture, and draw a single
        // sprite each frame instead of ~1500 SKShapeNodes (the bossman-apple
        // approach: a pre-rendered maze sheet). Wall PHYSICS stays as separate
        // bodies-only nodes so collision is unchanged. Falls back to the live
        // tree if no view is available to bake with.
        let staticTree = SKNode()

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
                staticTree.addChild(floor)

                switch char {
                case Strings.Tile.wallChar:
                    addWall(at: position, into: staticTree, scene: scene)

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

        // Collapse the static floor+wall tree into a single baked sprite.
        if let view, let tex = view.texture(from: staticTree) {
            let frame = staticTree.calculateAccumulatedFrame()
            let sheet = SKSpriteNode(texture: tex, size: tex.size)
            sheet.anchorPoint = .zero
            sheet.position = CGPoint(x: frame.minX, y: frame.minY)
            sheet.zPosition = -9
            scene.addChild(sheet)
        } else {
            // No view to bake with: fall back to the live (slower) node tree.
            for child in staticTree.children { child.removeFromParent(); scene.addChild(child) }
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

    // Wall VISUAL goes into the baked static sheet; the PHYSICS body rides on
    // a separate, invisible bodies-only node added live to the scene so
    // collision is identical to before (the body draws nothing, so it costs
    // nothing per frame beyond the tree walk).
    private func addWall(at position: CGPoint, into staticTree: SKNode, scene: SKNode) {
        let wall = SpriteFactory.wallTile(size: map.tileSize, color: cubicleColor)
        wall.position = position
        wall.zPosition = 0
        staticTree.addChild(wall)

        let bodyNode = SKNode()
        bodyNode.position = position
        let body = SKPhysicsBody(rectangleOf: CGSize(width: map.tileSize,
                                                     height: map.tileSize))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.wall
        body.collisionBitMask = PhysicsCategory.worker | PhysicsCategory.boss
        body.contactTestBitMask = 0
        bodyNode.physicsBody = body
        scene.addChild(bodyNode)
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

    // Tracks which machine tiles are currently grayed (in cooldown).
    // bossman-apple drops the contactTestBitMask while grayed; we just
    // skip the collectable flag here.
    private var grayedMachines: Set<CGPoint> = []

    // bossman-apple's grayOutMachine + collectable test rolled into one.
    // Returns the machine name + position if it's collectable on this
    // tile right now (not currently grayed). 15s after the call the
    // machine fades back to alpha 1 and re-enters the collectable pool.
    @discardableResult
    func collectMachine(at grid: CGPoint, cooldown: TimeInterval = 15) -> (name: String, position: CGPoint)? {
        guard let m = machineNodes[grid], !grayedMachines.contains(grid) else { return nil }
        grayedMachines.insert(grid)
        m.node.alpha = 0.55
        m.node.removeAction(forKey: Strings.ActionKey.machineCooldown)
        m.node.run(.sequence([
            .wait(forDuration: cooldown),
            .run { [weak self, weak n = m.node] in
                n?.alpha = 1
                self?.grayedMachines.remove(grid)
            }
        ]), withKey: Strings.ActionKey.machineCooldown)
        return (m.name, m.node.position)
    }

    // Re-enable every grayed machine immediately. bossman-apple calls
    // resetGrayedMachines after a TPS report is delivered so Pete can
    // start a fresh round on the same level.
    func resetGrayedMachines() {
        for grid in grayedMachines {
            guard let m = machineNodes[grid] else { continue }
            m.node.removeAction(forKey: Strings.ActionKey.machineCooldown)
            m.node.alpha = 1
        }
        grayedMachines.removeAll()
    }

    // Returns the scene position of the brown box at this grid, or nil.
    func touchedBrownBox(at grid: CGPoint) -> CGPoint? {
        guard let n = brownBoxNodes[grid] else { return nil }
        return n.position
    }

    private func addDot(at position: CGPoint, in scene: SKNode) -> SKNode? {
        let dot: SKNode
        if let tex = dotTexture {
            dot = SKSpriteNode(texture: tex, size: tex.size)
        } else {
            dot = SpriteFactory.dotVisual()
        }
        dot.position = position
        dot.zPosition = 1
        scene.addChild(dot)
        return dot
    }
}
