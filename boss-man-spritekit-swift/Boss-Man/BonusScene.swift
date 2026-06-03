import SpriteKit
import AppKit

// 3D bonus round: the office maze (level 1) rendered first/third-person with flat
// 2D graphics — a Wolfenstein-style DDA raycaster for the walls, a smooth blended
// sunset sky, and billboarded game sprites (pellets, gold discs, bosses) standing
// in the corridors. The camera trails behind Pete so you see him walking ahead of
// you. A top-down radar sits at the bottom. Common to both ports.
final class BonusScene: SKScene, BossControllerDelegate {

    // MARK: - Maze (level 1)
    private let map: [[Character]] = Levels.officeMaps.first.map { $0.map(Array.init) } ?? []
    private var rowsCount: Int { map.count }
    private var colsCount: Int { map.first?.count ?? 0 }

    private func isWall(_ x: Double, _ y: Double) -> Bool {
        let c = Int(x.rounded(.down)), r = Int(y.rounded(.down))
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return true }
        return map[r][c] == Strings.Tile.wallChar
    }

    // MARK: - Pete + chase camera (grid coords; y increases down the rows array)
    private var px = 1.5, py = 1.5, angle = 0.0
    private var moveDir = (x: 1, y: 0)       // current lane direction (cardinal)
    private var wantDir: (x: Int, y: Int)? = nil   // queued turn (taken at the next junction)
    private var tcx = 1.5, tcy = 1.5, targetAngle = 0.0
    private let camBack = 0.65               // how far the camera trails behind Pete

    private func open(_ c: Int, _ r: Int) -> Bool {
        guard r >= 0, r < rowsCount else { return false }
        var cc = c
        if cc < 0 || cc >= colsCount {                 // off a side edge: only a tunnel row wraps
            guard isTunnelRow(r) else { return false }
            cc = ((cc % colsCount) + colsCount) % colsCount
        }
        return cc < map[r].count && map[r][cc] != Strings.Tile.wallChar
    }
    // A side-warp row: both end cells are walkable, so walking off one edge comes
    // out the other (Pac-Man tunnel).
    private func isTunnelRow(_ r: Int) -> Bool {
        guard r >= 0, r < rowsCount, map[r].count > 1 else { return false }
        return map[r].first != Strings.Tile.wallChar && map[r].last != Strings.Tile.wallChar
    }
    private func cardinal(_ d: (x: Int, y: Int)) -> Double {
        if d.x > 0 { return 0 }; if d.x < 0 { return .pi }
        return d.y > 0 ? .pi / 2 : -.pi / 2
    }

    // MARK: - Layout / projection
    private let columns = 200
    private let planeScale = 0.5773          // tan(fov/2), fov 60° (no tan() on wasm)
    private var radarH: CGFloat = 180
    private var viewH: CGFloat { size.height - radarH }
    private var viewMidY: CGFloat { radarH + viewH * 0.70 }   // horizon, lifted for a look-down view
    private var bars: [SKShapeNode] = []
    private var zbuf: [Double] = []

    // MARK: - Billboards (pooled: built once, projected each frame)
    private struct Billboard { let node: SKNode; let nativeH: CGFloat; let worldH: CGFloat; let x, y: Double; var alive: Bool }
    private var billboards: [Billboard] = []

    // MARK: - Bosses — the REAL BossController from the 100% game (speed, square +
    // smooth modes, flee/splash/capture/respawn all inherited; nothing hand-rolled).
    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var bossController: BossController!
    private var bossMapNodes: [ObjectIdentifier: PixelPerson] = [:]   // radar mirror per boss node
    private var bossNativeH: [ObjectIdentifier: CGFloat] = [:]        // cached unscaled height for projection
    private var peteShielded = false
    private struct Shot { var x, y: Double; let dir: (x: Int, y: Int); let node: SKNode; let nativeH: CGFloat; let mapNode: SKNode; var alive: Bool }
    private var shots: [Shot] = []
    private var gameOver = false
    private var pressed = Set<Int>()
    private var collected = Set<Int>()
    private let sound = SoundManager()

    // MARK: - On-screen controls (same layout/sizing as the 100% game)
    private let joystickRadius: CGFloat = 112.5
    private let joystickKnobRadius: CGFloat = 45
    private let joystickDeadzone: CGFloat = 32.5
    private var joystickCenter = CGPoint.zero
    private var joystickActive = false
    private var joystickThumb: SKShapeNode?
    private var fireButtonCenter = CGPoint.zero
    private let fireButtonRadius: CGFloat = 112.5
    private var controlsShown = false

    private let spriteLayer = SKNode()
    private var pete: PixelPerson!
    private var peteBaseY: CGFloat = 0
    private var bob = 0.0

    private var hud: HUD!
    private let uiLayer = SKNode()
    private let state = RoundState()
    private let waterGun = WaterGunState()
    private var waterGunPickedUp = false
    private var spawnPx = 1.5, spawnPy = 1.5
    private var isUserPaused = false

    // MARK: - Minimap (the real 2D level, centered at the bottom)
    private let mapLayer = SKNode()
    private var mapPete: PixelPerson!
    private var mapPickups: [Int: SKNode] = [:]
    private let mapCell: CGFloat = 32
    private var mapScale: CGFloat = 1

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        anchorPoint = .zero
        backgroundColor = .black
        zbuf = Array(repeating: 0, count: columns)
        placeStart()
        buildSky()
        buildColumns()
        spriteLayer.zPosition = 1
        addChild(spriteLayer)
        buildBillboards()
        buildPete()
        buildMap()
        setupBossController()
        buildHUD()
        buildControls()
        render()
        sound.startBackgroundMusic()
    }

    // MARK: - Setup
    private func placeStart() {
        var sc = 1, sr = 1, found = false
        outer: for r in 0..<rowsCount {
            for c in 0..<map[r].count where map[r][c] == Strings.Tile.workerChar { sc = c; sr = r; found = true; break outer }
        }
        if !found {
            search: for r in 0..<rowsCount {
                for c in 0..<map[r].count where map[r][c] != Strings.Tile.wallChar { sc = c; sr = r; break search }
            }
        }
        px = Double(sc) + 0.5; py = Double(sr) + 0.5; tcx = px; tcy = py
        spawnPx = px; spawnPy = py
        for d in [(x: 1, y: 0), (x: 0, y: 1), (x: -1, y: 0), (x: 0, y: -1)] where open(sc + d.x, sr + d.y) {
            moveDir = d; break
        }
        targetAngle = cardinal(moveDir); angle = targetAngle
    }

    private func buildSky() {
        // 2D office palette: a dark ceiling (maze background) blending toward the
        // horizon over the dark checker-floor colour. One thin band per device row
        // so the gradient is smooth, then baked to a single sprite (the bands are
        // static, so this is ~240 fewer draw calls per frame on Apple).
        let tree = SKNode()
        let horC: (CGFloat, CGFloat, CGFloat) = (0.10, 0.10, 0.13)   // maze background, lit at horizon
        let topC: (CGFloat, CGFloat, CGFloat) = (0.02, 0.02, 0.035)  // darker toward the ceiling
        let skyBottom = viewMidY, skyTop = size.height
        let n = max(1, Int(skyTop - skyBottom))
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(max(1, n - 1))      // 0 horizon .. 1 ceiling
            let col = SKColor(red: horC.0 + (topC.0 - horC.0) * t,
                              green: horC.1 + (topC.1 - horC.1) * t,
                              blue: horC.2 + (topC.2 - horC.2) * t, alpha: 1)
            let band = SKShapeNode(rect: CGRect(x: 0, y: skyBottom + CGFloat(i), width: size.width, height: 2))
            band.fillColor = col; band.strokeColor = .clear
            tree.addChild(band)
        }
        let ground = SKShapeNode(rect: CGRect(x: 0, y: radarH, width: size.width, height: viewMidY - radarH))
        ground.fillColor = SKColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)   // floor-tile colour
        ground.strokeColor = .clear
        tree.addChild(ground)
        addBaked(tree, to: self, z: -3)
    }

    // Bake a static node tree to one texture and add it as a single sprite (one
    // draw call). Falls back to the live tree if no view is available to bake with.
    private func addBaked(_ tree: SKNode, to parent: SKNode, z: CGFloat) {
        if let tex = view?.texture(from: tree) {
            let sprite = SKSpriteNode(texture: tex)
            let f = tree.calculateAccumulatedFrame()
            sprite.position = CGPoint(x: f.midX, y: f.midY)
            sprite.zPosition = z
            parent.addChild(sprite)
        } else {
            tree.zPosition = z
            parent.addChild(tree)
        }
    }

    private func buildColumns() {
        for _ in 0..<columns {
            let bar = SKShapeNode()
            bar.strokeColor = .clear; bar.isAntialiased = true; bar.zPosition = 0
            addChild(bar); bars.append(bar)
        }
    }

    private func emojiBillboard(_ text: String, _ fontSize: CGFloat) -> SKNode {
        let label = SKLabelNode(fontNamed: Strings.Font.menlo)
        label.text = text; label.fontSize = fontSize
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        guard let tex = view?.texture(from: label) else { return label }
        tex.filteringMode = .linear      // interpolate (smooth) when the raycaster scales it
        return SKSpriteNode(texture: tex)
    }

    private func buildBillboards() {
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                let x = Double(c) + 0.5, y = Double(r) + 0.5
                var node: SKNode?; var worldH: CGFloat = 0.6
                switch ch {
                case Strings.Tile.dotChar, Strings.Tile.hideoutChar:
                    node = SpriteFactory.pelletCube(size: 8); worldH = 0.14
                case Strings.Tile.goldDiscChar:
                    node = SpriteFactory.goldDiscVisual(radius: 10); worldH = 0.4
                case Strings.Tile.waterPelletChar:
                    node = SpriteFactory.waterPelletVisual(radius: 10); worldH = 0.4
                case Strings.Tile.waterGunChar:   node = emojiBillboard(Strings.Emoji.waterGun, 128); worldH = 0.5
                case Strings.Tile.printerChar:    node = emojiBillboard(Strings.Emoji.printer, 128); worldH = 0.6
                case Strings.Tile.faxChar:        node = emojiBillboard(Strings.Emoji.fax, 128); worldH = 0.6
                case Strings.Tile.coverSheetChar: node = emojiBillboard(Strings.Emoji.coverSheet, 128); worldH = 0.6
                case Strings.Tile.bookBinderChar: node = emojiBillboard(Strings.Emoji.bookBinder, 128); worldH = 0.6
                case Strings.Tile.brownBoxChar:   node = emojiBillboard(Strings.Emoji.brownBox, 128); worldH = 0.6
                default: continue
                }
                guard let n = node else { continue }
                n.isHidden = true
                spriteLayer.addChild(n)
                let nh = max(1, n.calculateAccumulatedFrame().height)
                billboards.append(Billboard(node: n, nativeH: nh, worldH: worldH, x: x, y: y, alive: true))
            }
        }
    }

    private func buildPete() {
        pete = SpriteFactory.petePersonBack(walkExaggeration: 1)
        let nativeH = max(1, pete.calculateAccumulatedFrame().height)
        let target = viewH * 0.42
        pete.setScale(target / nativeH)
        pete.zPosition = 90                          // above every billboard, so pellets pass behind him
        peteBaseY = radarH + target / 2 + 6
        pete.position = CGPoint(x: size.width / 2, y: peteBaseY)
        spriteLayer.addChild(pete)
        pete.startWalking()
    }

    private func buildHUD() {
        uiLayer.zPosition = 1000
        addChild(uiLayer)
        hud = HUD(requiredItems: Strings.Machine.required)
        hud.install(in: uiLayer, size: size, extraRow: false)   // compact 150/200-style HUD, never the extended row
        state.dotCount = map.reduce(0) { $0 + $1.filter { $0 == Strings.Tile.dotChar || $0 == Strings.Tile.hideoutChar }.count }
        refreshHUD()
    }

    private func refreshHUD() {
        hud.updateStatus(score: state.score, highScore: state.highScore, level: state.level,
                         dots: state.collectedDots, total: state.dotCount,
                         reports: state.tpsReportsDelivered, items: state.reportItems)
        hud.updateLives(state.lives)
        hud.updateWaterGun(active: waterGun.isActive, pellets: waterGunPickedUp ? waterGun.pelletsRemaining : -1, blueMode: false)
        hud.updateLevelEmojis(Array(levelTravelers.prefix(1)))
    }

    private func peteCaught() {
        _ = sound.playCaughtByBoss()
        state.lives -= 1
        refreshHUD()
        if state.lives <= 0 { gameOver = true; exit(); return }
        px = spawnPx; py = spawnPy; wantDir = nil; pressed.removeAll()
        let sc = Int(spawnPx.rounded(.down)), sr = Int(spawnPy.rounded(.down))
        for d in [(x: 1, y: 0), (x: 0, y: 1), (x: -1, y: 0), (x: 0, y: -1)] where open(sc + d.x, sr + d.y) { moveDir = d; break }
        targetAngle = cardinal(moveDir); angle = targetAngle
        bossController.teleportAllToSpawn()   // 3s spawnGrace; peteShielded follows isAnyBossSpawning
        pete.removeAction(forKey: "shield")
        pete.run(.sequence([.repeat(.sequence([.fadeAlpha(to: 0.35, duration: 0.6), .fadeAlpha(to: 1.0, duration: 0.6)]), count: 3),
                            .run { [weak self] in self?.pete.alpha = 1 }]), withKey: "shield")
    }

    // Grid-space catch (BonusScene has no physics worker body, so same-tile is the
    // catch); honors spawnGrace immobilization + the shield, like GameScene.
    private func checkBossCatch() {
        let pgx = Int(px.rounded(.down)), pgy = rowsCount - 1 - Int(py.rounded(.down))
        for e in bossController.entities {
            let bg = e.mover?.grid ?? e.ai.grid
            guard Int(bg.x) == pgx, Int(bg.y) == pgy, !bossController.isImmobilized(boss: e.node) else { continue }
            if bossController.isInFleeMode(boss: e.node) { bossController.capture(boss: e.node) }
            else if !peteShielded { peteCaught(); return }
        }
    }

    // MARK: - BossControllerDelegate (Pete reported in GridMap's bottom-up coords)
    var workerGrid: CGPoint { CGPoint(x: CGFloat(Int(px.rounded(.down))), y: CGFloat(rowsCount - 1 - Int(py.rounded(.down)))) }
    var workerDirection: MoveDirection? {
        if moveDir.x > 0 { return .right }
        if moveDir.x < 0 { return .left }
        return moveDir.y > 0 ? .down : .up
    }
    var isGoldDiscMode: Bool { false }
    var isPeteShielded: Bool { peteShielded }
    func bossDidCatchWorker() { }   // bonus catches via grid checkBossCatch() after advance (no physics contact)
    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint) {
        state.bumpScore(by: points); sound.playCaptureBoss(streak: max(1, points / 100)); refreshHUD()
    }
    func dropletAxisThreatening(_ grid: CGPoint) -> MoveDirection? { nil }

    private func togglePause() {
        isUserPaused.toggle()
        if isUserPaused { pete.stopWalking(); mapPete.stopWalking(); sound.pauseAudio() }
        else { pete.startWalking(); mapPete.startWalking(); sound.resumeAudio() }
    }

    private func mapKey(_ c: Int, _ r: Int) -> Int { r * colsCount + c }
    private func mapLocal(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) * mapCell, y: (CGFloat(rowsCount) - CGFloat(y)) * mapCell)
    }
    private func buildMap() {
        let panel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: radarH))
        panel.fillColor = SKColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        panel.strokeColor = .clear; panel.zPosition = 29
        addChild(panel)

        let mapW = CGFloat(colsCount) * mapCell, mapH = CGFloat(rowsCount) * mapCell
        let cubicle = SpriteFactory.cubicleColors[0]

        // The maze floor and cubicle walls never change, so we bake them to ONE
        // texture and draw a single sprite — the MazeBuilder trick the 100% game
        // uses — instead of ~2000 per-cell SKShapeNodes (Apple pays a draw call per
        // shape). Pickups, Pete and the chasing bosses stay live on top.
        let bakeTree = SKNode()
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                let center = mapLocal(Double(c) + 0.5, Double(r) + 0.5)
                let floor = SpriteFactory.floorTile(size: mapCell, alternate: (c + r) % 2 == 0)
                floor.position = center; bakeTree.addChild(floor)
                if ch == Strings.Tile.wallChar {
                    let wall = SpriteFactory.wallTile(size: mapCell, color: cubicle)
                    wall.position = center; bakeTree.addChild(wall)
                }
            }
        }
        addBaked(bakeTree, to: mapLayer, z: 0)

        // Dots all share one baked texture so they batch into ~one draw call; gold
        // and water keep their own node so each can be hidden when collected.
        let dotTex = view?.texture(from: SpriteFactory.dotVisual(size: mapCell * 0.2))
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                let center = mapLocal(Double(c) + 0.5, Double(r) + 0.5)
                var pickup: SKNode?
                switch ch {
                case Strings.Tile.dotChar, Strings.Tile.hideoutChar:
                    pickup = dotTex.map { SKSpriteNode(texture: $0) } ?? SpriteFactory.dotVisual(size: mapCell * 0.2)
                case Strings.Tile.goldDiscChar:    pickup = SpriteFactory.goldDiscVisual(radius: mapCell * 0.28)
                case Strings.Tile.waterPelletChar: pickup = SpriteFactory.waterPelletVisual(radius: mapCell * 0.32)
                case Strings.Tile.waterGunChar:    pickup = emojiBillboard(Strings.Emoji.waterGun, mapCell * 0.7)
                case Strings.Tile.printerChar:     pickup = emojiBillboard(Strings.Emoji.printer, mapCell * 0.7)
                case Strings.Tile.faxChar:         pickup = emojiBillboard(Strings.Emoji.fax, mapCell * 0.7)
                case Strings.Tile.coverSheetChar:  pickup = emojiBillboard(Strings.Emoji.coverSheet, mapCell * 0.7)
                case Strings.Tile.bookBinderChar:  pickup = emojiBillboard(Strings.Emoji.bookBinder, mapCell * 0.7)
                case Strings.Tile.brownBoxChar:    pickup = emojiBillboard(Strings.Emoji.brownBox, mapCell * 0.7)
                default: break
                }
                if let pickup {
                    pickup.position = center; pickup.zPosition = 2; mapLayer.addChild(pickup)
                    mapPickups[mapKey(c, r)] = pickup
                    switch ch {
                    case Strings.Tile.goldDiscChar, Strings.Tile.waterGunChar:
                        pickup.run(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.35), .scale(to: 1.0, duration: 0.35)])))
                    case Strings.Tile.waterPelletChar:
                        pickup.run(.repeatForever(.sequence([.scale(to: 1.3, duration: 0.4), .scale(to: 1.0, duration: 0.4)])))
                    default: break
                    }
                }
            }
        }
        mapPete = SpriteFactory.petePerson(walkExaggeration: 1)
        mapPete.zPosition = 5
        mapLayer.addChild(mapPete)
        mapPete.startWalking()

        mapScale = (radarH - 8) / mapH
        mapLayer.setScale(mapScale)
        mapLayer.position = CGPoint(x: (size.width - mapW * mapScale) / 2, y: 4)
        mapLayer.zPosition = 30
        addChild(mapLayer)
    }

    private func setupBossController() {
        let rows = Levels.officeMaps.first ?? []
        gridMap = GridMap(tileSize: 32, rows: rows)
        gridMap.xOffset = 0; gridMap.yOffset = 0
        pathfinder = Pathfinder(map: gridMap)
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder, sound: sound, containerOriginX: 0)
        bossController.delegate = self
        // Spawn positions from the level data, in the bottom-up grid GridMap uses.
        var overrides: [(blueprintIndex: Int, position: CGPoint)] = []
        for (ri, row) in rows.reversed().enumerated() {
            for (ci, ch) in Array(row).enumerated() {
                switch ch {
                case Strings.Tile.boss1Char: overrides.append((0, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss2Char: overrides.append((1, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss3Char: overrides.append((2, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss4Char: overrides.append((3, CGPoint(x: ci, y: ri)))
                default: break
                }
            }
        }
        bossController.spawn(forLevel: 1, spawnOverrides: overrides)
        syncBossNodes()
    }

    // Re-parent controller boss nodes into the 3D sprite layer (driven as billboards,
    // no stray flat node / physics body) and mirror each on the radar. Re-run every
    // frame so splash/teleport respawns (fresh nodes) get adopted too.
    private func syncBossNodes() {
        let live = Set(bossController.entities.map { ObjectIdentifier($0.node) })
        for (id, mn) in bossMapNodes where !live.contains(id) {
            mn.removeFromParent(); bossMapNodes.removeValue(forKey: id); bossNativeH.removeValue(forKey: id)
        }
        for e in bossController.entities {
            let id = ObjectIdentifier(e.node)
            if e.node.parent !== spriteLayer {
                e.node.removeFromParent(); e.node.physicsBody = nil; e.node.isHidden = true
                bossNativeH[id] = max(1, e.node.calculateAccumulatedFrame().height)   // cache native height before projection scales it
                spriteLayer.addChild(e.node)
            }
            if bossMapNodes[id] == nil {
                let mn = SpriteFactory.bossPersonForBlueprint(e.blueprintIndex)
                mn.zPosition = 4; mapLayer.addChild(mn); bossMapNodes[id] = mn
            }
        }
    }

    // MARK: - Per-frame
    override func update(_ currentTime: TimeInterval) {
        if isUserPaused || gameOver { return }
        step(); render()
    }

    private var camX = 0.0, camY = 0.0
    private func render() {
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        // Camera trails behind Pete; pull in if it would sit inside a wall.
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back; camY = py - dirY * back

        // Cast a ray at every column boundary, then connect adjacent tops/bottoms
        // into sloped quads so wall silhouettes are continuous lines, not stairs.
        var topY = [CGFloat](repeating: 0, count: columns + 1)
        var botY = [CGFloat](repeating: 0, count: columns + 1)
        var dist = [Double](repeating: 0, count: columns + 1)
        var sides = [Int](repeating: 0, count: columns + 1)
        for j in 0...columns {
            let cameraX = 2.0 * Double(j) / Double(columns) - 1.0
            let rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX
            var mapX = Int(camX.rounded(.down)), mapY = Int(camY.rounded(.down))
            let ddx = rdx == 0 ? 1e30 : abs(1 / rdx), ddy = rdy == 0 ? 1e30 : abs(1 / rdy)
            var stepX = 0, stepY = 0, sideX = 0.0, sideY = 0.0
            if rdx < 0 { stepX = -1; sideX = (camX - Double(mapX)) * ddx } else { stepX = 1; sideX = (Double(mapX) + 1 - camX) * ddx }
            if rdy < 0 { stepY = -1; sideY = (camY - Double(mapY)) * ddy } else { stepY = 1; sideY = (Double(mapY) + 1 - camY) * ddy }
            var side = 0, guardN = 0
            while guardN < 200 {
                guardN += 1
                if sideX < sideY { sideX += ddx; mapX += stepX; side = 0 } else { sideY += ddy; mapY += stepY; side = 1 }
                if mapY < 0 || mapY >= rowsCount || mapX < 0 || mapX >= colsCount { break }
                if map[mapY][mapX] == Strings.Tile.wallChar { break }
            }
            let perp = side == 0 ? (sideX - ddx) : (sideY - ddy)
            let d = max(0.05, perp)
            dist[j] = d; sides[j] = side
            let lineH = min(viewH * 4, viewH / CGFloat(d))
            topY[j] = viewMidY + lineH / 2
            botY[j] = viewMidY - lineH / 2
        }
        let w = size.width / CGFloat(columns)
        for i in 0..<columns {
            let xL = CGFloat(i) * w, xR = CGFloat(i + 1) * w + 1   // 1px overlap hides AA seams between quads
            let p = CGMutablePath()
            p.move(to: CGPoint(x: xL, y: botY[i]))
            p.addLine(to: CGPoint(x: xL, y: topY[i]))
            p.addLine(to: CGPoint(x: xR, y: topY[i + 1]))
            p.addLine(to: CGPoint(x: xR, y: botY[i + 1]))
            p.closeSubpath()
            bars[i].path = p
            let d = (dist[i] + dist[i + 1]) / 2
            zbuf[i] = min(dist[i], dist[i + 1])
            let f = CGFloat(max(0.12, min(1.0, 1.0 - d / 16))) * (sides[i] == 1 ? 0.62 : 1.0)
            bars[i].fillColor = SKColor(red: 0.02 + 0.02 * f, green: 0.05 + 0.45 * f, blue: 0.10 + 0.88 * f, alpha: 1)
        }
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
    }

    private func projectSprites(dirX: Double, dirY: Double, planeX: Double, planeY: Double) {
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        var all: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, x: Double, y: Double)] = []
        for b in billboards where b.alive {
            all.append((b.node, b.nativeH, b.worldH, b.x, b.y))
        }
        for e in bossController.entities {
            let g = e.mover?.grid ?? e.ai.grid
            let bx = Double(g.x) + 0.5, by = Double(rowsCount) - 0.5 - Double(g.y)   // gridMap bottom-up -> raster top-down
            all.append((e.node, bossNativeH[ObjectIdentifier(e.node)] ?? 36, 0.9, bx, by))
        }
        for s in shots where s.alive {
            all.append((s.node, s.nativeH, 0.32, s.x, s.y))
        }
        for item in all {
            let node = item.node
            let relX = item.x - camX, relY = item.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)   // depth
            guard tY > 0.15 else { node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            // Occlude against the wall depth at the sprite's center column.
            if col >= 0, col < columns, tY > zbuf[col] + 0.1 { node.isHidden = true; continue }
            if tY > 18 { node.isHidden = true; continue }       // far cull
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { node.isHidden = true; continue }
            let targetH = viewH / CGFloat(tY) * item.worldH
            let s = targetH / item.nativeH
            node.isHidden = false
            node.setScale(s)
            // Stand on the corridor floor: bottom of the slice at this depth.
            let floorY = viewMidY - (viewH / CGFloat(tY)) / 2
            node.position = CGPoint(x: screenX, y: floorY + targetH / 2)
            node.zPosition = min(40, CGFloat(2 + 30 / tY))      // nearer over farther, but always behind Pete
        }
    }

    private func updateMap() {
        mapPete.position = mapLocal(px, py)
        mapPete.setFacing(facing(moveDir))
        for e in bossController.entities {
            guard let mn = bossMapNodes[ObjectIdentifier(e.node)] else { continue }
            let g = e.mover?.grid ?? e.ai.grid
            mn.position = mapLocal(Double(g.x) + 0.5, Double(rowsCount) - 0.5 - Double(g.y))
            if let d = e.mover?.dir { mn.setFacing(d) }
        }
        for s in shots where s.alive { s.mapNode.position = mapLocal(s.x, s.y) }
    }

    private func facing(_ d: (x: Int, y: Int)) -> MoveDirection {
        d.x > 0 ? .right : d.x < 0 ? .left : d.y > 0 ? .down : .up
    }

    // MARK: - Lane movement (Pac-Man style: auto-forward, turn at junctions)
    private func step() {
        var da = targetAngle - angle
        while da > .pi { da -= 2 * .pi }; while da < -.pi { da += 2 * .pi }
        angle += max(-0.14, min(0.14, da))

        let speed = 1.0 / (0.14 * 60.0)   // match 100% mode: WorkerController moveDuration 0.14s/tile at 60fps
        let col = Int(px.rounded(.down)), row = Int(py.rounded(.down))
        let ccx = Double(col) + 0.5, ccy = Double(row) + 0.5
        // Turn (←/→) only near a tile centre and only if that lane is open.
        if let t = wantDir, abs(px - ccx) < 0.2, abs(py - ccy) < 0.2, open(col + t.x, row + t.y) {
            px = ccx; py = ccy; moveDir = t; wantDir = nil; targetAngle = cardinal(moveDir)
        }
        // Hold ↑ = forward along facing, ↓ = backward; release = stop in tracks.
        let fwd = pressed.contains(KeyCode.arrowUp) || pressed.contains(KeyCode.keyW)
        let back = pressed.contains(KeyCode.arrowDown) || pressed.contains(KeyCode.keyS)
        let tdir: (x: Int, y: Int)? = fwd ? moveDir : (back ? (x: -moveDir.x, y: -moveDir.y) : nil)
        if let d = tdir {
            if d.x != 0 { py += max(-speed, min(speed, ccy - py)) }   // stay centred on the lane
            else        { px += max(-speed, min(speed, ccx - px)) }
            if open(col + d.x, row + d.y) {
                px += Double(d.x) * speed; py += Double(d.y) * speed
            } else {                                                  // stop at the wall, not past the tile centre
                if d.x > 0 { px = min(px + speed, ccx) } else if d.x < 0 { px = max(px - speed, ccx) }
                if d.y > 0 { py = min(py + speed, ccy) } else if d.y < 0 { py = max(py - speed, ccy) }
            }
            if px < 0 { px += Double(colsCount) } else if px >= Double(colsCount) { px -= Double(colsCount) }
        }
        for i in billboards.indices where billboards[i].alive && billboards[i].worldH < 0.5 {
            if abs(billboards[i].x - px) < 0.5 && abs(billboards[i].y - py) < 0.5 {
                billboards[i].alive = false; billboards[i].node.isHidden = true
                let bc = Int(billboards[i].x), br = Int(billboards[i].y)
                mapPickups[mapKey(bc, br)]?.isHidden = true
                switch map[br][bc] {
                case Strings.Tile.goldDiscChar:    sound.playGoldDisc(); state.collectedGoldDiscs += 1; state.bumpScore(by: 5)
                case Strings.Tile.waterPelletChar: sound.playWaterGunPickup(); state.bumpScore(by: 50)
                default:                           sound.playDotBlip(); state.collectedDots += 1; state.bumpScore(by: 1)
                }
                refreshHUD()
            }
        }
        collectStationary()
        moveShots()
        bossController.advance(1.0 / 60.0)          // fixed dt = 100% game's per-frame step
        syncBossNodes()
        peteShielded = bossController.isAnyBossSpawning   // shielded exactly while bosses flash in (spawnGrace)
        checkBossCatch()
        let moving = tdir != nil
        if moving { pete.startWalking(); mapPete.startWalking(); bob += 0.22 }
        else { pete.stopWalking(); mapPete.stopWalking() }
        pete.position = CGPoint(x: size.width / 2, y: peteBaseY + CGFloat(sin(bob) * 4))
    }

    private func moveShots() {
        let speed = 0.22
        for i in shots.indices where shots[i].alive {
            shots[i].x += Double(shots[i].dir.x) * speed
            shots[i].y += Double(shots[i].dir.y) * speed
            if isWall(shots[i].x, shots[i].y) { shots[i].alive = false; continue }
            let sgx = Int(shots[i].x.rounded(.down)), sgy = rowsCount - 1 - Int(shots[i].y.rounded(.down))
            for e in bossController.entities {
                let bg = e.mover?.grid ?? e.ai.grid
                if Int(bg.x) == sgx, Int(bg.y) == sgy {
                    bossController.splash(boss: e.node)   // real splash + loop-driven 5s respawn
                    shots[i].alive = false
                    sound.playWaterGunSplash(); state.bumpScore(by: 50); refreshHUD()
                    break
                }
            }
        }
        for s in shots where !s.alive { s.node.removeFromParent(); s.mapNode.removeFromParent() }
        shots.removeAll { !$0.alive }
    }

    private func fire() {
        guard waterGun.consumePellet() else { return }
        sound.playWaterGunShoot()
        refreshHUD()
        let pellet = SpriteFactory.waterPelletVisual(radius: 9)
        pellet.isHidden = true; spriteLayer.addChild(pellet)
        let mapNode = SpriteFactory.waterPelletVisual(radius: mapCell * 0.22)
        mapNode.position = mapLocal(px, py); mapNode.zPosition = 3; mapLayer.addChild(mapNode)
        shots.append(Shot(x: px, y: py, dir: moveDir, node: pellet,
                          nativeH: max(1, pellet.calculateAccumulatedFrame().height), mapNode: mapNode, alive: true))
    }

    // Tile-based pickup of the stationary items (water-gun power-up + TPS machines),
    // mirroring the 100% game's collect rules through the shared RoundState/WaterGunState.
    private func collectStationary() {
        let pcol = Int(px.rounded(.down)), prow = Int(py.rounded(.down))
        guard prow >= 0, prow < rowsCount, pcol >= 0, pcol < map[prow].count else { return }
        let key = mapKey(pcol, prow)
        guard !collected.contains(key) else { return }
        switch map[prow][pcol] {
        case Strings.Tile.waterGunChar:
            collected.insert(key); waterGun.activate(); waterGunPickedUp = true; sound.playWaterGunPickup()
            hidePickup(pcol, prow); refreshHUD()
        case Strings.Tile.printerChar:    collectMachine(Strings.Machine.printer, key, pcol, prow)
        case Strings.Tile.faxChar:        collectMachine(Strings.Machine.fax, key, pcol, prow)
        case Strings.Tile.coverSheetChar: collectMachine(Strings.Machine.coverSheet, key, pcol, prow)
        case Strings.Tile.bookBinderChar: collectMachine(Strings.Machine.bookBinder, key, pcol, prow)
        default: break
        }
    }
    private func collectMachine(_ name: String, _ key: Int, _ col: Int, _ row: Int) {
        guard Strings.Machine.required.contains(name), !state.reportItems.contains(name) else { return }
        collected.insert(key)
        state.reportItems.insert(name)
        state.bumpScore(by: 100)
        sound.playMachine(named: name)
        grayPickup(col, row); refreshHUD()   // dim it like the 100% 2D maze, don't remove it
    }
    private func hidePickup(_ col: Int, _ row: Int) {
        for i in billboards.indices where billboards[i].alive && Int(billboards[i].x) == col && Int(billboards[i].y) == row {
            billboards[i].alive = false; billboards[i].node.isHidden = true
        }
        mapPickups[mapKey(col, row)]?.isHidden = true
    }
    private func grayPickup(_ col: Int, _ row: Int) {
        for i in billboards.indices where Int(billboards[i].x) == col && Int(billboards[i].y) == row {
            billboards[i].node.alpha = 0.55
        }
        mapPickups[mapKey(col, row)]?.alpha = 0.55
    }

    private func exit() {
        sound.stopAllAudio()
        view?.presentScene(TitleScene(size: size), transition: .fade(withDuration: 0.5))
    }

    // MARK: - Input (steer at junctions, relative to facing)
    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        switch code {
        case KeyCode.esc:                       exit()
        case KeyCode.keyP:                      togglePause()
        case KeyCode.space:                     if !event.isARepeat { fire() }
        case KeyCode.arrowLeft,  KeyCode.keyA:  wantDir = (x: moveDir.y, y: -moveDir.x)   // turn left
        case KeyCode.arrowRight, KeyCode.keyD:  wantDir = (x: -moveDir.y, y: moveDir.x)   // turn right
        case KeyCode.arrowUp, KeyCode.keyW, KeyCode.arrowDown, KeyCode.keyS: pressed.insert(code)
        default:                                break
        }
    }
    override func keyUp(with event: NSEvent) { pressed.remove(Int(event.keyCode)) }

    // MARK: - On-screen joystick + fire button (drive the same tank input)
    private func buildControls() {
        if UserDefaults.standard.bool(forKey: Strings.DefaultsKey.waterGunHide) { return }
        controlsShown = true
        let fireOnLeft = UserDefaults.standard.bool(forKey: Strings.DefaultsKey.waterGunLeft)
        fireButtonCenter = CGPoint(x: fireOnLeft ? fireButtonRadius : size.width - fireButtonRadius, y: fireButtonRadius + 15)
        let ring = SKShapeNode(circleOfRadius: fireButtonRadius)
        ring.position = fireButtonCenter
        ring.fillColor = SKColor(white: 1, alpha: 0.14); ring.strokeColor = SKColor(white: 1, alpha: 0.5)
        ring.lineWidth = 2; ring.zPosition = 55
        addChild(ring)

        joystickCenter = CGPoint(x: fireOnLeft ? size.width - joystickRadius : joystickRadius, y: joystickRadius + 15)
        let base = SKShapeNode(circleOfRadius: joystickRadius)
        base.position = joystickCenter
        base.fillColor = SKColor(white: 1, alpha: 0.10); base.strokeColor = SKColor(white: 1, alpha: 0.5)
        base.lineWidth = 2; base.zPosition = 55
        addChild(base)
        let thumb = SKShapeNode(circleOfRadius: joystickKnobRadius)
        thumb.position = joystickCenter
        thumb.fillColor = SKColor(white: 1, alpha: 0.28); thumb.strokeColor = SKColor(white: 1, alpha: 0.6)
        thumb.lineWidth = 2; thumb.zPosition = 56
        addChild(thumb); joystickThumb = thumb
    }

    private func radius(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y; return (dx * dx + dy * dy).squareRoot()
    }

    override func mouseDown(with event: NSEvent) {
        guard controlsShown, !isUserPaused else { return }
        let p = event.location(in: self)
        if radius(p, joystickCenter) <= joystickRadius {
            joystickActive = true; moveThumb(to: p); steerJoystick(p); return
        }
        if radius(p, fireButtonCenter) <= fireButtonRadius { fire() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard joystickActive else { return }
        let p = event.location(in: self); moveThumb(to: p); steerJoystick(p)
    }
    override func mouseUp(with event: NSEvent) {
        guard joystickActive else { return }
        joystickActive = false
        joystickThumb?.position = joystickCenter
        pressed.remove(KeyCode.arrowUp); pressed.remove(KeyCode.arrowDown)
    }

    private func steerJoystick(_ p: CGPoint) {
        let dx = p.x - joystickCenter.x, dy = p.y - joystickCenter.y
        guard (dx * dx + dy * dy).squareRoot() >= joystickDeadzone else {
            pressed.remove(KeyCode.arrowUp); pressed.remove(KeyCode.arrowDown); return
        }
        if abs(dy) >= abs(dx) {                                    // up = forward, down = backward
            if dy > 0 { pressed.insert(KeyCode.arrowUp); pressed.remove(KeyCode.arrowDown) }
            else { pressed.insert(KeyCode.arrowDown); pressed.remove(KeyCode.arrowUp) }
        } else {                                                   // left / right = turn
            pressed.remove(KeyCode.arrowUp); pressed.remove(KeyCode.arrowDown)
            wantDir = dx > 0 ? (x: -moveDir.y, y: moveDir.x) : (x: moveDir.y, y: -moveDir.x)
        }
    }
    private func moveThumb(to p: CGPoint) {
        let dx = p.x - joystickCenter.x, dy = p.y - joystickCenter.y
        let mag = (dx * dx + dy * dy).squareRoot(), limit = joystickRadius - joystickKnobRadius
        if mag > limit, mag > 0 {
            let s = limit / mag
            joystickThumb?.position = CGPoint(x: joystickCenter.x + dx * s, y: joystickCenter.y + dy * s)
        } else {
            joystickThumb?.position = p
        }
    }

    required init?(coder: NSCoder) { fatalError(Strings.System.initCoderUnsupported) }
    override init(size: CGSize) { super.init(size: size) }
}
