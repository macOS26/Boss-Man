import SpriteKit

// MazeBuilder — common to both ports. Scans the level grid and builds the maze:
// floor + wall VISUALS are gathered into a throwaway tree and baked to one
// sprite via SKView.texture(from:); pickups (gold disc, water gun, water
// pellet), TPS machines, and the brown box are placed as nodes; dots are kept by
// grid. Pickups/machines/dots are collected by grid (collectX(at:)), not by
// physics contact. The ONLY platform branch is wall PHYSICS: per-wall Box2D
// bodies on wasm, one compound body on apple. build(in:view:) returns the dot
// count so GameScene knows when the level is cleared.
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
    private var dotNodes: [Int: SKNode] = [:]
    private var goldNodes: [Int: SKNode] = [:]
    private var waterPelletNodes: [Int: SKNode] = [:]
    private var waterGunNodes: [Int: SKNode] = [:]
    // Machine name (Strings.Machine.*) + scene node, indexed by tile.
    // bossman-apple stores these in a [String: SKNode] via the node's
    // SKNode.name; we go by grid so handlePeteArrival can look up by tile.
    private(set) var machineNodes: [Int: (name: String, node: SKNode)] = [:]
    private(set) var brownBoxNodes: [Int: SKNode] = [:]

    // One shared dot texture (color-invariant) baked once, reused for every
    // pellet — mirrors bossman-apple's single pelletTexture. Cached across
    // levels so we only pay the offscreen bake one time.
    private var dotTexture: SKTexture?
    // The baked floor+wall sheet is re-rendered every level; hold its texture so
    // we can free the previous level's canvas instead of leaking one per level.
    private var mazeSheetTexture: SKTexture?

    init(map: GridMap) { self.map = map }

    // Free baked textures on scene teardown (call from GameScene.willMove). The
    // per-level maze sheet is also freed at the top of build().
    func releaseTextures() {
        mazeSheetTexture?.releaseImage(); mazeSheetTexture = nil
        dotTexture?.releaseImage();       dotTexture = nil
    }

    @discardableResult
    func build(in scene: SKNode, view: SKView? = nil) -> Int {
        // Reset every map-derived collection so a level rebuild starts clean
        // instead of accumulating the previous level's spawns / pickups / stale
        // node handles (bossman-apple resets these at the top of build()).
        workerSpawn = nil
        bossSpawns = []
        goldDiscPositions = []
        waterGunPositions = []
        waterPelletPositions = []
        dotNodes = [:]
        goldNodes = [:]
        waterPelletNodes = [:]
        waterGunNodes = [:]
        machineNodes = [:]
        brownBoxNodes = [:]

        // Free last level's baked floor+wall sheet so its canvas is reclaimed
        // instead of leaking one full-size image per level.
        mazeSheetTexture?.releaseImage()
        mazeSheetTexture = nil

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
        var wallCenters: [CGPoint] = []

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
                    addWallVisual(at: position, into: staticTree)
                    wallCenters.append(position)

                case Strings.Tile.dotChar, Strings.Tile.hideoutChar:
                    if let dot = addDot(at: position, in: scene) {
                        dotNodes[tileKey(grid)] = dot; dotCount += 1
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
                    goldNodes[tileKey(grid)] = gold

                case Strings.Tile.waterGunChar:
                    waterGunPositions.append(grid)
                    let gun = SKNode()
                    let gunGlyph = SKLabelNode(text: Strings.Emoji.waterGun)
                    gunGlyph.fontSize = map.tileSize * 0.55 * SpriteFactory.worldRenderScale
                    gunGlyph.verticalAlignmentMode = .center
                    gunGlyph.horizontalAlignmentMode = .center
                    gunGlyph.setScale(1 / SpriteFactory.worldRenderScale)
                    gun.addChild(gunGlyph)
                    gun.position = position
                    gun.zPosition = 6
                    gun.run(.repeatForever(.sequence([
                        .scale(to: 1.25, duration: 0.35),
                        .scale(to: 1.0,  duration: 0.35),
                    ])))
                    scene.addChild(gun)
                    waterGunNodes[tileKey(grid)] = gun

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
                    waterPelletNodes[tileKey(grid)] = pellet

                case Strings.Tile.printerChar:
                    let n = addMachineEmoji(Strings.Emoji.printer, at: position, in: scene)
                    machineNodes[tileKey(grid)] = (Strings.Machine.printer, n)
                case Strings.Tile.faxChar:
                    let n = addMachineEmoji(Strings.Emoji.fax, at: position, in: scene)
                    machineNodes[tileKey(grid)] = (Strings.Machine.fax, n)
                case Strings.Tile.coverSheetChar:
                    let n = addMachineEmoji(Strings.Emoji.coverSheet, at: position, in: scene)
                    machineNodes[tileKey(grid)] = (Strings.Machine.coverSheet, n)
                case Strings.Tile.bookBinderChar:
                    let n = addMachineEmoji(Strings.Emoji.bookBinder, at: position, in: scene)
                    machineNodes[tileKey(grid)] = (Strings.Machine.bookBinder, n)
                case Strings.Tile.brownBoxChar:
                    let n = addBrownBoxEmoji(Strings.Emoji.brownBox, at: position, in: scene)
                    brownBoxNodes[tileKey(grid)] = n

                case Strings.Tile.workerChar:
                    workerSpawn = grid
                    // Worker tile is walkable + has a dot underneath.
                    if let dot = addDot(at: position, in: scene) {
                        dotNodes[tileKey(grid)] = dot; dotCount += 1
                    }

                case Strings.Tile.boss1Char: bossSpawns.append((0, grid))
                case Strings.Tile.boss2Char: bossSpawns.append((1, grid))
                case Strings.Tile.boss3Char: bossSpawns.append((2, grid))
                case Strings.Tile.boss4Char: bossSpawns.append((3, grid))

                default: break
                }
            }
        }

        addWallPhysics(centers: wallCenters, in: scene)

        // Collapse the static floor+wall tree into a single baked sprite. Bake at
        // the live DISPLAY pixel density (view size vs scene size, e.g. fullscreen
        // on a 5K panel) times the maze zoom, so the camera magnifies a matching-
        // resolution texture (crisp, square cubicle edges) instead of upscaling a
        // scene-res bake into a soft, rounded blur. Capped at 5x to bound the
        // texture memory. WASM (view==scene) bakes at ~zoom and stays crisp.
        let frame = staticTree.calculateAccumulatedFrame()
        // Apple bakes the maze to one bitmap; RenderScale.mazeBake sizes it to the
        // display so the camera magnifies a sharp sheet (WASM bakes 1:1, redrawn
        // live). The sheet is then drawn back down by the same factor.
        let bakeScale = RenderScale.mazeBake(sceneWidth: frame.width,
                                             zoom: max(1, CGFloat(MazeZoom.zoomPercent) / 100))
        staticTree.setScale(bakeScale)
        let baked = view?.texture(from: staticTree)
        staticTree.setScale(1)
        if let baked {
            baked.filteringMode = .linear
            let sheet = SKSpriteNode(texture: baked)
            sheet.setScale(1 / bakeScale)
            sheet.position = CGPoint(x: frame.midX, y: frame.midY)
            sheet.zPosition = -9
            scene.addChild(sheet)
            mazeSheetTexture = baked
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
        guard let node = dotNodes[tileKey(grid)] else { return false }
        node.removeFromParent()
        dotNodes.removeValue(forKey: tileKey(grid))
        return true
    }
    @discardableResult
    func collectGold(at grid: CGPoint) -> Bool {
        guard let node = goldNodes[tileKey(grid)] else { return false }
        node.removeFromParent()
        goldNodes.removeValue(forKey: tileKey(grid))
        return true
    }
    @discardableResult
    func collectWaterPellet(at grid: CGPoint) -> Bool {
        guard let node = waterPelletNodes[tileKey(grid)] else { return false }
        node.removeFromParent()
        waterPelletNodes.removeValue(forKey: tileKey(grid))
        return true
    }
    @discardableResult
    func collectWaterGun(at grid: CGPoint) -> Bool {
        guard let node = waterGunNodes[tileKey(grid)] else { return false }
        node.removeFromParent()
        waterGunNodes.removeValue(forKey: tileKey(grid))
        return true
    }

    // MARK: - Helpers

    // Wall VISUAL goes into the baked static sheet (drawn once, one sprite).
    private func addWallVisual(at position: CGPoint, into staticTree: SKNode) {
        let wall = SpriteFactory.wallTile(size: map.tileSize, color: cubicleColor)
        wall.position = position
        wall.zPosition = 0
        staticTree.addChild(wall)
    }

    // The one platform branch. wasm: a per-wall static Box2D body (Box2D handles
    // many small static bodies well, and per-wall avoids the hero/traveler
    // stutter a compound body caused). apple/SpriteKit: one compound body.
    private func addWallPhysics(centers: [CGPoint], in scene: SKNode) {
        guard !centers.isEmpty else { return }
        let bodySize = CGSize(width: map.tileSize, height: map.tileSize)
        // One static body per wall cell. A compound body (SKPhysicsBody(bodies:))
        // would be lighter on Apple, but the wasm Box2D bridge doesn't support
        // compound shapes, so both platforms use individual cells.
        for c in centers {
            let bodyNode = SKNode()
            bodyNode.position = c
            let body = SKPhysicsBody(rectangleOf: bodySize)
            body.isDynamic = false
            body.categoryBitMask = PhysicsCategory.wall
            body.collisionBitMask = PhysicsCategory.worker | PhysicsCategory.boss
            body.contactTestBitMask = 0
            bodyNode.physicsBody = body
            scene.addChild(bodyNode)
        }
    }


    // TPS printer / fax / cover-sheet / book-binder — 26pt emoji label,
    // no pulse (matches bossman-apple's machine glyphs).
    private func addMachineEmoji(_ emoji: String, at position: CGPoint, in scene: SKNode) -> SKNode {
        let label = SKLabelNode(text: emoji)
        label.fontSize = 26 * SpriteFactory.worldRenderScale
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.setScale(1 / SpriteFactory.worldRenderScale)
        label.position = position
        label.zPosition = 6
        scene.addChild(label)
        return label
    }

    // Brown TPS delivery box. Slightly larger glyph (28pt) and sits one
    // z-layer below the other machines, matching bossman-apple.
    private func addBrownBoxEmoji(_ emoji: String, at position: CGPoint, in scene: SKNode) -> SKNode {
        let label = SKLabelNode(text: emoji)
        label.fontSize = 28 * SpriteFactory.worldRenderScale
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.setScale(1 / SpriteFactory.worldRenderScale)
        label.position = position
        label.zPosition = 4
        scene.addChild(label)
        return label
    }

    // Tile char -> machine emoji, used by the level editor's palette glyphs.
    static func emoji(forSymbol symbol: String) -> String {
        guard let char = symbol.first else { return symbol }
        switch char {
        case Strings.Tile.printerChar:    return Strings.Emoji.printer
        case Strings.Tile.faxChar:        return Strings.Emoji.fax
        case Strings.Tile.coverSheetChar: return Strings.Emoji.coverSheet
        case Strings.Tile.bookBinderChar: return Strings.Emoji.bookBinder
        case Strings.Tile.brownBoxChar:   return Strings.Emoji.brownBox
        case Strings.Tile.waterGunChar:   return Strings.Emoji.waterGun
        default: return symbol
        }
    }

    // Tracks which machine tiles are currently grayed (in cooldown).
    // bossman-apple drops the contactTestBitMask while grayed; we just
    // skip the collectable flag here.
    private var grayedMachines: Set<Int> = []

    // CGPoint isn't Hashable before macOS 15, so key per-tile lookups by an
    // integer grid coordinate (row-major), which is Hashable on every OS.
    private func tileKey(_ grid: CGPoint) -> Int { Int(grid.y) * 100_000 + Int(grid.x) }

    // bossman-apple's grayOutMachine + collectable test rolled into one.
    // Returns the machine name + position if it's collectable on this
    // tile right now (not currently grayed). 15s after the call the
    // machine fades back to alpha 1 and re-enters the collectable pool.
    @discardableResult
    func collectMachine(at grid: CGPoint, cooldown: TimeInterval = 15,
                        shouldCollect: (String) -> Bool) -> (name: String, position: CGPoint)? {
        // Only dim/collect when the caller actually wants this item (not already
        // in the report) — touching a machine you've collected leaves it bright.
        let k = tileKey(grid)
        guard let m = machineNodes[k], !grayedMachines.contains(k),
              shouldCollect(m.name) else { return nil }
        grayedMachines.insert(k)
        m.node.alpha = 0.55
        m.node.removeAction(forKey: Strings.ActionKey.machineCooldown)
        m.node.run(.sequence([
            .wait(forDuration: cooldown),
            .run { [weak self, weak n = m.node] in
                n?.alpha = 1
                self?.grayedMachines.remove(k)
            }
        ]), withKey: Strings.ActionKey.machineCooldown)
        return (m.name, m.node.position)
    }

    // Re-enable every grayed machine immediately. bossman-apple calls
    // resetGrayedMachines after a TPS report is delivered so Pete can
    // start a fresh round on the same level.
    func resetGrayedMachines() {
        for k in grayedMachines {
            guard let m = machineNodes[k] else { continue }
            m.node.removeAction(forKey: Strings.ActionKey.machineCooldown)
            m.node.alpha = 1
        }
        grayedMachines.removeAll()
    }

    // Returns the scene position of the brown box at this grid, or nil.
    func touchedBrownBox(at grid: CGPoint) -> CGPoint? {
        guard let n = brownBoxNodes[tileKey(grid)] else { return nil }
        return n.position
    }

    // Dim the brown box on a TPS-report turn-in, same fade + cooldown as a collected
    // machine: alpha 0.55 for `cooldown` seconds, then back to 1.
    private var grayedBrownBoxes: Set<Int> = []
    @discardableResult
    func collectBrownBox(at grid: CGPoint, cooldown: TimeInterval = 15) -> CGPoint? {
        let k = tileKey(grid)
        guard let n = brownBoxNodes[k], !grayedBrownBoxes.contains(k) else { return nil }
        grayedBrownBoxes.insert(k)
        n.alpha = 0.55
        n.removeAction(forKey: Strings.ActionKey.machineCooldown)
        n.run(.sequence([
            .wait(forDuration: cooldown),
            .run { [weak self, weak nn = n] in nn?.alpha = 1; self?.grayedBrownBoxes.remove(k) }
        ]), withKey: Strings.ActionKey.machineCooldown)
        return n.position
    }

    private func addDot(at position: CGPoint, in scene: SKNode) -> SKNode? {
        let dot: SKNode
        if let tex = dotTexture {
            dot = SKSpriteNode(texture: tex)
        } else {
            dot = SpriteFactory.dotVisual()
        }
        dot.position = position
        dot.zPosition = 1
        scene.addChild(dot)
        return dot
    }
}

#if os(macOS)
// The kit frees the baked offscreen canvas on wasm; macOS GCs SKTextures, so
// the call is a no-op there. Keeps the common builder free of #if at the call site.
extension SKTexture { func releaseImage() {} }
#endif
