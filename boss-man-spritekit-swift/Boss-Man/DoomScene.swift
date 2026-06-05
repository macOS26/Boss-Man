import SpriteKit
import AppKit

// 3D bonus round: the office maze (level 1) rendered first/third-person with flat
// 2D graphics — a Wolfenstein-style DDA raycaster for the walls, a smooth blended
// sunset sky, and billboarded game sprites (pellets, gold discs, bosses) standing
// in the corridors. The camera trails behind Pete so you see him walking ahead of
// you. A top-down radar sits at the bottom. Common to both ports.
final class DoomScene: SKScene, BossControllerDelegate, SKTouchResponder {

    // MARK: - Maze (loaded for the selected level; the editor's test plays the edited rows)
    private lazy var map: [[Character]] =
        LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1))).map { Array($0) }
    private var rowsCount: Int { map.count }
    private var colsCount: Int { map.first?.count ?? 0 }

    // Set by the caller before the scene is presented. The title launches level 1
    // (BOSS 3D); the level editor's test launches the edited level in practice mode.
    var startingLevel: Int {
        get { state.level }
        set { state.level = max(1, newValue) }
    }
    var practiceMode: Bool {
        get { state.practiceMode }
        set { state.practiceMode = newValue }
    }

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
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return false }
        return map[r][c] != Strings.Tile.wallChar
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
    private let floorA = SKShapeNode()   // alternating floor-tile checker, cast per frame
    private let floorB = SKShapeNode()
    private var zbuf: [Double] = []

    // MARK: - Billboards (pooled: built once, projected each frame)
    private struct Billboard { let node: SKNode; let nativeH: CGFloat; let worldH: CGFloat; let x, y: Double; var alive: Bool }
    private var billboards: [Billboard] = []

    // MARK: - Bosses — the REAL BossController from the 100% game (speed, square +
    // smooth modes, flee/splash/capture/respawn all inherited; nothing hand-rolled).
    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var bossController: BossController!
    private var travelerSpawner: TravelerSpawner!   // the fish/treat that walks the maze (same spawner as 2D)
    private var travelerMirror: SKNode?             // billboard mirror; the REAL node keeps its SKAction walk (smooth) uncllobbered in the scene root
    private var travelerMirrorEmoji = ""
    private var bossMapNodes: [ObjectIdentifier: PixelPerson] = [:]   // radar mirror per boss node
    private var bossNativeH: [ObjectIdentifier: CGFloat] = [:]        // cached unscaled height for projection
    private var bossFeet: [ObjectIdentifier: CGFloat] = [:]           // cached LOCAL feet offset (frame.minY relative to origin)
    private var bossGrid: [ObjectIdentifier: (Double, Double)] = [:]  // smooth (continuous) grid pos per boss, captured pre-projection
    private var peteShielded = false
    private struct Shot { var x, y: Double; let dir: (x: Int, y: Int); let node: SKNode; let nativeH: CGFloat; let mapNode: SKNode; var alive: Bool }
    private var shots: [Shot] = []
    private var gameOver = false
    private var gameOverScreen: GameOverScreen?
    private var dying = false
    private var deathFramesLeft = 0
    private let deathFrames = 90   // 1.5s at 60fps: hold the catcher on screen
    private var pressed = Set<Int>()
    private var collected = Set<Int>()
    private let sound = SoundManager()

    // MARK: - On-screen controls (same layout/sizing as the 100% game)
    private let joystickRadius: CGFloat = 129.375
    private let joystickDeadzone: CGFloat = 20   // D-pad centre hole + input deadzone (smaller = more reach)
    private var joystickCenter = CGPoint.zero
    // X-pattern D-pad: four ring-sector wedges (up/down/left/right) split by an X.
    // Each finger lights at most one wedge; two fingers light two (forward + a turn)
    // ONLY when the phone actually has two fingers down. Keyed "up/down/left/right".
    private var dpadWedges: [String: SKShapeNode] = [:]
    private var dpadFinger: [Int: String] = [:]   // active finger id -> its wedge
    private var usingTouch = false                 // a real touch arrived: ignore the synthetic mouse pointer
    private var fireButtonCenter = CGPoint.zero
    private let fireButtonRadius: CGFloat = 129.375
    private var controlsShown = false

    private let spriteLayer = SKNode()
    private let nameLayer = SKNode()
    private var bossNames: [ObjectIdentifier: SKLabelNode] = [:]
    private var peteName: SKLabelNode!
    private var pete: PixelPerson!
    private var peteBaseY: CGFloat = 0
    private var bob = 0.0
    private var throbClock = 0.0   // free-running clock for the post-spawn boss pulse

    private var hud: HUD!
    private let uiLayer = SKNode()
    private let state = RoundState()
    private let waterGun = WaterGunState()
    private var waterGunPickedUp = false
    private let goldDisc = GoldDiscTimer()
    private let goldDiscDuration: TimeInterval = 20
    private var frightenSecondsLeft: TimeInterval = 0
    private let reportItemPoints = [10, 25, 50, 100]
    private var onBrownBox = false
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
        nameLayer.zPosition = 150            // nameplates ride above all billboards, below the HUD
        addChild(nameLayer)
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
        // Ceiling + floor derive from the level's cubicle colour (dark at the ceiling,
        // a touch brighter at the horizon) so the whole 3D environment matches the level.
        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        let tree = SKNode()
        let skyBottom = viewMidY, skyTop = size.height
        let n = max(1, Int(skyTop - skyBottom))
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(max(1, n - 1))      // 0 horizon .. 1 ceiling
            let factor = 0.18 + (0.05 - 0.18) * t            // cube brightness: horizon -> ceiling
            let col = cube.blended(withFraction: 1 - factor, of: .black) ?? cube
            let band = SKShapeNode(rect: CGRect(x: 0, y: skyBottom + CGFloat(i), width: size.width, height: 2))
            band.fillColor = col; band.strokeColor = .clear
            tree.addChild(band)
        }
        let ground = SKShapeNode(rect: CGRect(x: 0, y: radarH, width: size.width, height: viewMidY - radarH))
        ground.fillColor = cube.blended(withFraction: 0.88, of: .black) ?? cube   // dark level-tinted floor base
        ground.strokeColor = .clear
        tree.addChild(ground)
        addBaked(tree, to: self, z: -3)

        // Alternating floor-tile checker (cast per frame in castFloor), drawn above the
        // baked ground (z -3) and below the walls (z 0). Two nodes, one per shade.
        floorA.fillColor = cube.blended(withFraction: 0.87, of: .black) ?? cube   // ~cube * 0.13
        floorB.fillColor = cube.blended(withFraction: 0.76, of: .black) ?? cube   // ~cube * 0.24
        floorA.strokeColor = .clear; floorB.strokeColor = .clear
        floorA.zPosition = -2; floorB.zPosition = -2
        floorA.isAntialiased = false; floorB.isAntialiased = false
        addChild(floorA); addChild(floorB)
    }

    // Floor-cast the maze floor as an alternating checker so the tile grid reads in 3D
    // (matches the C++ DoomScene::drawFloor). Each scene row below the horizon maps to a
    // perpendicular distance; the world position sweeps left-ray -> right-ray across the
    // row; cell parity picks the shade. Coalesced into per-row run rects in two paths.
    private func castFloor() {
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        let rdx0 = dirX - planeX, rdy0 = dirY - planeY
        let rdx1 = dirX + planeX, rdy1 = dirY + planeY
        let W = size.width, rowH: CGFloat = 2
        let pathA = CGMutablePath(), pathB = CGMutablePath()
        var yu = radarH
        while yu < viewMidY - 0.5 {
            let distFromHorizon = Double(viewMidY - yu)
            let d = Double(viewH) / (2.0 * distFromHorizon)
            let fx0 = camX + d * rdx0, fy0 = camY + d * rdy0
            let stepX = d * (rdx1 - rdx0) / Double(W), stepY = d * (rdy1 - rdy0) / Double(W)
            var runStart: CGFloat = 0
            var runParity = (Int(fx0.rounded(.down)) + Int(fy0.rounded(.down))) & 1
            var x: CGFloat = 1
            while x <= W {
                var parity = -1
                if x < W {
                    let wx = fx0 + stepX * Double(x), wy = fy0 + stepY * Double(x)
                    parity = (Int(wx.rounded(.down)) + Int(wy.rounded(.down))) & 1
                }
                if parity != runParity {
                    let r = CGRect(x: runStart, y: yu, width: x - runStart, height: rowH)
                    if runParity == 1 { pathA.addRect(r) } else { pathB.addRect(r) }
                    runStart = x; runParity = parity
                }
                x += 1
            }
            yu += rowH
        }
        floorA.path = pathA; floorB.path = pathB
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

    // Wrap a power-up visual so it throbs in the 3D view: the raycaster scales the
    // PARENT each frame, the throb runs on the CHILD, so the two multiply instead of
    // the projection clobbering the pulse (matching MazeBuilder's throb).
    private func throbbing(_ visual: SKNode, _ peak: CGFloat, _ dur: TimeInterval) -> SKNode {
        let parent = SKNode()
        parent.addChild(visual)
        visual.run(.repeatForever(.sequence([.scale(to: peak, duration: dur), .scale(to: 1.0, duration: dur)])))
        return parent
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
                    node = throbbing(SpriteFactory.goldDiscVisual(radius: 10), 1.25, 0.35); worldH = 0.4
                case Strings.Tile.waterPelletChar:
                    node = throbbing(SpriteFactory.waterPelletVisual(radius: 10), 1.3, 0.4); worldH = 0.4
                case Strings.Tile.waterGunChar:   node = throbbing(emojiBillboard(Strings.Emoji.waterGun, 128), 1.25, 0.35); worldH = 0.5
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
        peteName = makeNameplate(Strings.Worker.pete)
        peteName.position = CGPoint(x: size.width / 2, y: peteBaseY + target / 2 + 16)
        nameLayer.addChild(peteName)
    }

    private func makeNameplate(_ text: String) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: Strings.Font.menloBold)
        l.text = text
        l.fontSize = 22
        l.fontColor = .white
        l.horizontalAlignmentMode = .center
        l.verticalAlignmentMode = .center
        return l
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

    private func startGoldDiscMode() {
        goldDisc.activate()
        bossController.setGoldDiscActive(true)   // recolors the real boss nodes (the 3D billboards) to flee blue
        recolorMinimapBosses(flee: true)         // mirror it on the radar copies
        sound.startGoldDiscBass()
        frightenSecondsLeft = goldDiscDuration
        hud.showMessage(Strings.Message.goldDiscActivated, duration: 3)
        refreshHUD()
    }
    private func endGoldDiscMode() {
        goldDisc.deactivate()
        bossController.setGoldDiscActive(false)
        recolorMinimapBosses(flee: false)
        sound.stopGoldDiscBass()
        frightenSecondsLeft = 0
        hud.showMessage(Strings.Message.goldDiscEnded, duration: 2)
        refreshHUD()
    }

    // The radar bosses are mirror nodes (a node can't have two parents), so they
    // need the same flee palette BossController paints on the real nodes.
    private static let bossSkin = NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.62, alpha: 1)
    private func recolorMinimapBosses(flee: Bool) {
        for e in bossController.entities {
            guard let mn = bossMapNodes[ObjectIdentifier(e.node)] else { continue }
            applyFleePalette(mn, flee: flee, blueprint: e.blueprintIndex)
        }
    }
    private func applyFleePalette(_ p: PixelPerson, flee: Bool, blueprint: Int) {
        if flee {
            p.setBodyColor(SpriteFactory.fleeBodyColor)
            p.setTieColor(SpriteFactory.fleeTieColor)
            p.setShirtOutlineColor(NSColor(calibratedWhite: 1, alpha: 0.75))
            p.setEyeColor(SpriteFactory.fleeEyeColor)
            p.setSkinColor(SpriteFactory.fleeSkinColor)
        } else {
            let c = BossBlueprint.colors[min(max(blueprint, 0), BossBlueprint.colors.count - 1)]
            p.setBodyColor(c.body); p.setTieColor(c.tie)
            p.setShirtOutlineColor(.white); p.setEyeColor(.black); p.setSkinColor(Self.bossSkin)
        }
    }

    // Caught: hold the REAL catching boss still in front of Pete for ~1.5s (no fake sprite),
    // then dock a life and respawn. update() skips step()/render() while dying, so the boss
    // stays frozen exactly where we place it here.
    private func startDeath(node: PixelPerson) {
        if dying { return }
        dying = true
        _ = sound.playCaughtByBoss()
        if goldDisc.isActive { endGoldDiscMode() }
        pete.stopWalking()
        pete.alpha = 0.2                                      // Pete fades as Bill (z 500, in front) takes him
        node.stopWalking()
        let nh = bossNativeH[ObjectIdentifier(node)] ?? max(1, node.calculateAccumulatedFrame().height)
        node.isHidden = false
        node.setScale(viewH * 0.42 / nh)                     // Pete's size, never larger
        node.position = CGPoint(x: size.width / 2, y: radarH + viewH * 0.5)
        node.zPosition = 500
        for e in bossController.entities where e.node !== node { e.node.isHidden = true }   // only the catcher shows
        for (_, l) in bossNames { l.isHidden = true }
        for s in shots { s.node.isHidden = true }
        deathFramesLeft = deathFrames
    }

    private func updateDeath() {
        deathFramesLeft -= 1                          // hold the catcher on screen, still, then respawn
        if deathFramesLeft <= 0 { finishDeath() }
    }

    private func finishDeath() {
        dying = false                                 // projectSprites re-scales/re-shows every billboard on resume
        for (_, l) in bossNames { l.isHidden = false }
        state.lives -= 1
        refreshHUD()
        if state.lives <= 0 { gameOver = true; showGameOver(); return }
        px = spawnPx; py = spawnPy; wantDir = nil; pressed.removeAll()
        let sc = Int(spawnPx.rounded(.down)), sr = Int(spawnPy.rounded(.down))
        for d in [(x: 1, y: 0), (x: 0, y: 1), (x: -1, y: 0), (x: 0, y: -1)] where open(sc + d.x, sr + d.y) { moveDir = d; break }
        targetAngle = cardinal(moveDir); angle = targetAngle
        bossController.teleportAllToSpawn()   // 3s spawnGrace; peteShielded follows isAnyBossSpawning
        pete.alpha = 1
        pete.startWalking()
        pete.removeAction(forKey: "shield")
        pete.run(.sequence([.repeat(.sequence([.fadeAlpha(to: 0.35, duration: 0.6), .fadeAlpha(to: 1.0, duration: 0.6)]), count: 3),
                            .run { [weak self] in self?.pete.alpha = 1 }]), withKey: "shield")
    }

    // Grid-space catch (DoomScene has no physics worker body, so same-tile is the
    // catch); honors spawnGrace immobilization + the shield, like GameScene.
    private func checkBossCatch() {
        let pgx = Int(px.rounded(.down)), pgy = rowsCount - 1 - Int(py.rounded(.down))
        for e in bossController.entities {
            let bg = e.mover?.grid ?? e.ai.grid
            guard Int(bg.x) == pgx, Int(bg.y) == pgy, !bossController.isImmobilized(boss: e.node) else { continue }
            if bossController.isInFleeMode(boss: e.node) { bossController.capture(boss: e.node) }
            else if !peteShielded { startDeath(node: e.node); return }
        }
    }

    // MARK: - BossControllerDelegate (Pete reported in GridMap's bottom-up coords)
    var workerGrid: CGPoint { CGPoint(x: CGFloat(Int(px.rounded(.down))), y: CGFloat(rowsCount - 1 - Int(py.rounded(.down)))) }
    var workerDirection: MoveDirection? {
        if moveDir.x > 0 { return .right }
        if moveDir.x < 0 { return .left }
        return moveDir.y > 0 ? .down : .up
    }
    var isGoldDiscMode: Bool { goldDisc.isActive }
    var isPeteShielded: Bool { peteShielded }
    func bossDidCatchWorker() { }   // bonus catches via grid checkBossCatch() after advance (no physics contact)
    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint) {
        state.bumpScore(by: points); sound.playCaptureBoss(streak: max(1, points / 100)); popPoints(points); refreshHUD()
    }
    // Bosses dodge an incoming water pellet, same as the 2D modes: report the travel
    // AXIS of any shot bearing down on this boss; BossController steps it perpendicular.
    private let dropletDodgeRange = 8
    func dropletAxisThreatening(_ bossGrid: CGPoint) -> MoveDirection? {
        for s in shots where s.alive {
            let dGrid = CGPoint(x: CGFloat(Int(s.x.rounded(.down))), y: CGFloat(rowsCount - 1 - Int(s.y.rounded(.down))))
            let dir: MoveDirection = s.dir.x > 0 ? .right : s.dir.x < 0 ? .left : (s.dir.y > 0 ? .down : .up)
            if dropletThreatens(dropletGrid: dGrid, dir: dir, boss: bossGrid) { return dir }
        }
        return nil
    }
    private func dropletThreatens(dropletGrid d: CGPoint, dir: MoveDirection, boss b: CGPoint) -> Bool {
        let (dx, dy) = dir.delta
        let dist: Int
        if dx != 0 {
            guard Int(b.y) == Int(d.y) else { return false }
            let delta = Int(b.x) - Int(d.x)
            guard delta != 0, (dx > 0) == (delta > 0) else { return false }
            dist = abs(delta)
        } else {
            guard Int(b.x) == Int(d.x) else { return false }
            let delta = Int(b.y) - Int(d.y)
            guard delta != 0, (dy > 0) == (delta > 0) else { return false }
            dist = abs(delta)
        }
        guard dist <= dropletDodgeRange else { return false }
        var step = d
        for _ in 0..<dist {
            step = CGPoint(x: step.x + CGFloat(dx), y: step.y + CGFloat(dy))
            if !gridMap.isWalkable(step) { return false }
        }
        return true
    }

    private func togglePause() {
        isUserPaused.toggle()
        hud.showPaused(isUserPaused)   // same PAUSED text the 2D game uses
        spriteLayer.isPaused = isUserPaused   // freeze every SKAction (boss walks, pickup throbs)
        mapLayer.isPaused = isUserPaused       // and the radar copies
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
        panel.strokeColor = .clear; panel.zPosition = 200   // above every 3D sprite/nameplate so nothing ever draws over the minimap
        addChild(panel)

        let mapW = CGFloat(colsCount) * mapCell, mapH = CGFloat(rowsCount) * mapCell
        let cubicle = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]

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
        mapLayer.zPosition = 201
        addChild(mapLayer)
    }

    private func setupBossController() {
        let rows = LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1)))
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
        // The traveler (fish/treat) walks the maze and is caught for points, exactly as in 2D —
        // the spawner drives the tile walk; the 3D view projects it as a billboard (see projectSprites).
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound, containerOriginX: 0)
        travelerSpawner.scheduleVisits(of: levelTravelers[(state.level - 1) % levelTravelers.count]) { [weak self] in
            guard let self else { return false }
            return !self.gameOver && !self.isUserPaused && !self.dying
        }
    }

    // Re-parent controller boss nodes into the 3D sprite layer (driven as billboards,
    // no stray flat node / physics body) and mirror each on the radar. Re-run every
    // frame so splash/teleport respawns (fresh nodes) get adopted too.
    private func syncBossNodes() {
        let live = Set(bossController.entities.map { ObjectIdentifier($0.node) })
        for (id, mn) in bossMapNodes where !live.contains(id) {
            mn.removeFromParent(); bossMapNodes.removeValue(forKey: id)
            bossNativeH.removeValue(forKey: id); bossFeet.removeValue(forKey: id)
        }
        for (id, lbl) in bossNames where !live.contains(id) {
            lbl.removeFromParent(); bossNames.removeValue(forKey: id)
        }
        for e in bossController.entities {
            let id = ObjectIdentifier(e.node)
            if e.node.parent !== spriteLayer {
                e.tag.removeFromParent()                                              // drop the in-world tag (still inflates the frame even when hidden); 3D uses overlay nameplates
                let f = e.node.calculateAccumulatedFrame()                            // body-only frame now (tag gone)
                bossNativeH[id] = max(1, f.height)
                bossFeet[id] = f.minY - e.node.position.y                             // LOCAL bottom (frame is in parent coords incl. position; subtract it)
                e.node.removeFromParent(); e.node.physicsBody = nil; e.node.isHidden = true
                e.node.freezeLook()                                                   // 3D billboard: static eyes/tie (radar copy still tracks)
                spriteLayer.addChild(e.node)
            }
            if bossMapNodes[id] == nil {
                let mn = SpriteFactory.bossPersonForBlueprint(e.blueprintIndex)
                mn.zPosition = 4; mapLayer.addChild(mn); bossMapNodes[id] = mn
                if goldDisc.isActive { applyFleePalette(mn, flee: true, blueprint: e.blueprintIndex) }
            }
        }
    }

    // MARK: - Per-frame
    override func update(_ currentTime: TimeInterval) {
        if isUserPaused || gameOver { return }
        if dying { updateDeath(); return }
        step(); render()
    }

    private var camX = 0.0, camY = 0.0
    private func render() {
        throbClock += 1.0 / 60.0
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        // Camera trails behind Pete; pull in if it would sit inside a wall.
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back; camY = py - dirY * back
        castFloor()

        // One ray per column CENTRE. A column whose ray exits the map through an
        // opening (tunnel / no wall) is "open" -> drawn as nothing (black), not a wall.
        var cTop = [CGFloat](repeating: 0, count: columns)
        var cBot = [CGFloat](repeating: 0, count: columns)
        var cDist = [Double](repeating: 0, count: columns)
        var cSide = [Int](repeating: 0, count: columns)
        var cOpen = [Bool](repeating: false, count: columns)
        var cFace = [Int](repeating: -1, count: columns)
        var cPar = [Int](repeating: 0, count: columns)
        for i in 0..<columns {
            let cameraX = 2.0 * (Double(i) + 0.5) / Double(columns) - 1.0
            let rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX
            var mapX = Int(camX.rounded(.down)), mapY = Int(camY.rounded(.down))
            let ddx = rdx == 0 ? 1e30 : abs(1 / rdx), ddy = rdy == 0 ? 1e30 : abs(1 / rdy)
            var stepX = 0, stepY = 0, sideX = 0.0, sideY = 0.0
            if rdx < 0 { stepX = -1; sideX = (camX - Double(mapX)) * ddx } else { stepX = 1; sideX = (Double(mapX) + 1 - camX) * ddx }
            if rdy < 0 { stepY = -1; sideY = (camY - Double(mapY)) * ddy } else { stepY = 1; sideY = (Double(mapY) + 1 - camY) * ddy }
            var side = 0, guardN = 0, hitWall = false
            while guardN < 256 {
                guardN += 1
                if sideX < sideY { sideX += ddx; mapX += stepX; side = 0 } else { sideY += ddy; mapY += stepY; side = 1 }
                if mapY < 0 || mapY >= rowsCount || mapX < 0 || mapX >= colsCount { break }
                if map[mapY][mapX] == Strings.Tile.wallChar { hitWall = true; break }
            }
            let perp = side == 0 ? (sideX - ddx) : (sideY - ddy)
            let d = hitWall ? max(0.05, perp) : 1e9   // exited an opening -> no wall (black), not a blue dead end
            let lineH = min(viewH * 4, viewH / CGFloat(d))
            cTop[i] = viewMidY + lineH / 2
            cBot[i] = viewMidY - lineH / 2
            cDist[i] = d; cSide[i] = side; cOpen[i] = !hitWall
            // Identity of the exact wall FACE hit (grid line + axis). Two columns share a
            // face only if they land on the same line; depth deltas vary with distance, so
            // keying on depth falsely splits far columns (jagged) and merges near corners.
            cFace[i] = hitWall ? (side == 0 ? (stepX > 0 ? mapX : mapX + 1) * 2 : (stepY > 0 ? mapY : mapY + 1) * 2 + 1) : -1
            cPar[i] = (mapX + mapY) & 1   // wall-cell parity -> per-cell checker shade (aligns with the floor)
            zbuf[i] = d
        }
        let w = size.width / CGFloat(columns)
        // One straight-edged quad per contiguous wall FACE. Screen-space top/bottom of a
        // flat wall are exact straight lines (inverse depth is linear in screen-x), so a
        // single quad spanning the face is exact: square walls, no stairstep, no wobble,
        // and a sharp vertical break wherever the face changes (corner / opening).
        // Cubicle/wall colour for this level, matching the 2D game; shaded per-quad by
        // depth + side below so it reads as the same wall in first person.
        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        var bar = 0
        var i = 0
        while i < columns {
            if cOpen[i] { i += 1; continue }
            var j = i
            while j + 1 < columns && cFace[j + 1] == cFace[i] && cPar[j + 1] == cPar[i] { j += 1 }
            let xL = CGFloat(i) * w, xR = CGFloat(j + 1) * w + 1   // 1px overlap hides AA seams at corners
            var topL = cTop[i], topR = cTop[j], botL = cBot[i], botR = cBot[j]
            if j > i {
                let cxL = (CGFloat(i) + 0.5) * w, cxR = (CGFloat(j) + 0.5) * w
                let mT = (cTop[j] - cTop[i]) / (cxR - cxL), mB = (cBot[j] - cBot[i]) / (cxR - cxL)
                topL = cTop[i] + mT * (xL - cxL); topR = cTop[i] + mT * (xR - cxL)
                botL = cBot[i] + mB * (xL - cxL); botR = cBot[i] + mB * (xR - cxL)
            }
            let p = CGMutablePath()
            p.move(to: CGPoint(x: xL, y: botL))
            p.addLine(to: CGPoint(x: xL, y: topL))
            p.addLine(to: CGPoint(x: xR, y: topR))
            p.addLine(to: CGPoint(x: xR, y: botR))
            p.closeSubpath()
            let n = bars[bar]; bar += 1
            n.path = p; n.isHidden = false
            let mid = (i + j) / 2
            let f = CGFloat(max(0.12, min(1.0, 1.0 - cDist[mid] / 16))) * (cSide[i] == 1 ? 0.62 : 1.0)
                    * (cPar[i] == 1 ? 1.0 : 0.82)   // adjacent cells alternate shade for grid readability
            n.fillColor = cube.blended(withFraction: 1 - f, of: .black) ?? cube
            i = j + 1
        }
        for k in bar..<bars.count { bars[k].isHidden = true }
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
    }

    private func projectSprites(dirX: Double, dirY: Double, planeX: Double, planeY: Double) {
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        // `bottom` = the sprite's LOCAL frame.minY (feet offset from origin); centred sprites pass -nativeH/2.
        var all: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, x: Double, y: Double, maxH: CGFloat, name: String?, bottom: CGFloat)] = []
        for b in billboards where b.alive {
            all.append((b.node, b.nativeH, b.worldH, b.x, b.y, .greatestFiniteMagnitude, nil, -b.nativeH / 2))
        }
        for e in bossController.entities {
            guard let g = bossGrid[ObjectIdentifier(e.node)] else { continue }
            let id = ObjectIdentifier(e.node)
            let bx = g.0 + 0.5, by = Double(rowsCount) - 0.5 - g.1   // gridMap bottom-up -> raster top-down (smooth)
            let nh = bossNativeH[id] ?? 36
            all.append((e.node, nh, 0.3, bx, by, .greatestFiniteMagnitude, e.name, bossFeet[id] ?? -nh / 2))   // no size cap (cap made him sink); worldH 0.3 keeps him ~Pete-size at the catch
        }
        for s in shots where s.alive {
            all.append((s.node, s.nativeH, 0.32, s.x, s.y, .greatestFiniteMagnitude, nil, -s.nativeH / 2))
        }
        // The traveler walks in 2D scene coords; pull its node into the sprite layer and project it as a
        // billboard at its current grid tile (gridMap bottom-up -> raster top-down, same flip as bosses).
        if let tnode = travelerSpawner?.node, travelerSpawner?.activeTraveler != nil {
            if tnode.parent !== spriteLayer { tnode.removeFromParent(); spriteLayer.addChild(tnode) }
            let g = travelerSpawner.grid
            let nh = max(1, tnode.calculateAccumulatedFrame().height)
            all.append((tnode, nh, 0.42, Double(g.x) + 0.5, Double(rowsCount) - 0.5 - Double(g.y), .greatestFiniteMagnitude, nil, -nh / 2))
        }
        for item in all {
            let node = item.node
            let label = item.name.map { bossNameplate(for: node, text: $0) }
            label?.isHidden = true
            let relX = item.x - camX, relY = item.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)   // depth
            guard tY > 0.15 else { node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            // Occlude only when walls are nearer than the sprite across its whole footprint.
            // Sampling a window (not one column) stops the per-step blink when the centre
            // column straddles a side-opening edge as a boss walks. Clamp the column so a sprite
            // whose centre sits just past the screen edge still occludes against the edge wall —
            // skipping it leaked dots/pickups onto the left/right borders.
            let colC = max(0, min(columns - 1, col))
            var wallZ = zbuf[colC]
            for c in max(0, colC - 4)...min(columns - 1, colC + 4) { wallZ = max(wallZ, zbuf[c]) }
            if tY > wallZ + 0.3 { node.isHidden = true; continue }
            if tY > 18 { node.isHidden = true; continue }       // far cull
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { node.isHidden = true; continue }
            // TRUE 1-point perspective, identical to the dots: size = viewH/depth, feet planted on
            // the floor row at THIS depth. maxH only clamps the size at point-blank range so the
            // catch close-up isn't a full-screen sprite; it never moves the floor.
            let targetH = min(viewH / CGFloat(tY) * item.worldH, item.maxH)
            var s = targetH / item.nativeH
            // Post-spawn pulse: a respawned boss throbs while it can't yet catch Pete
            // (spawn grace / immobilized), then settles to full size. Feet stay planted
            // because position uses s below. Matches the C++ DoomScene throb.
            if item.name != nil, let boss = item.node as? PixelPerson, bossController.isImmobilized(boss: boss) {
                s *= 1 + 0.18 * abs(sin(throbClock * .pi * 3))
            }
            node.isHidden = false
            node.setScale(s)
            let floorY = viewMidY - (viewH / CGFloat(tY)) / 2
            node.position = CGPoint(x: screenX, y: floorY - item.bottom * s)
            node.zPosition = min(40, CGFloat(2 + 30 / tY))      // nearer over farther, but always behind Pete
            if let label = label {
                label.isHidden = false
                label.fontSize = max(13, min(24, targetH * 0.16))
                label.position = CGPoint(x: screenX, y: floorY + targetH + label.fontSize * 0.7)
            }
        }
    }

    private func bossNameplate(for node: SKNode, text: String) -> SKLabelNode {
        let id = ObjectIdentifier(node)
        if let l = bossNames[id] { return l }
        let l = makeNameplate(text)
        bossNames[id] = l
        nameLayer.addChild(l)
        return l
    }

    private func updateMap() {
        mapPete.position = mapLocal(px, py)
        mapPete.setFacing(facing(moveDir))
        for e in bossController.entities {
            guard let mn = bossMapNodes[ObjectIdentifier(e.node)], let g = bossGrid[ObjectIdentifier(e.node)] else { continue }
            mn.position = mapLocal(g.0 + 0.5, Double(rowsCount) - 0.5 - g.1)
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
        // Turn near a tile centre: take a ←/→ turn ONLY into an open lane (Pete never turns to
        // face a wall — a blocked turn stays queued for the next junction where that lane opens).
        // The down button queues the opposite heading, an about-face that ALWAYS corners here
        // since the lane behind Pete is open. Snap onto the square from up to ~0.4 tile away.
        if let t = wantDir, abs(px - ccx) < 0.4, abs(py - ccy) < 0.4, open(col + t.x, row + t.y) {
            px = ccx; py = ccy; moveDir = t; wantDir = nil; targetAngle = cardinal(moveDir)
        }
        // Hold ↑ = forward along facing; release = stop in tracks. ↓ is an about-face (wantDir), not reverse.
        let fwd = pressed.contains(KeyCode.arrowUp) || pressed.contains(KeyCode.keyW)
        let tdir: (x: Int, y: Int)? = fwd ? moveDir : nil
        if let d = tdir {
            let atCenter = abs(px - ccx) < 0.06 && abs(py - ccy) < 0.06
            if atCenter, !open(col + d.x, row + d.y),
               let partner = gridMap.tunnelPartner(of: CGPoint(x: col, y: rowsCount - 1 - row)) {
                px = Double(Int(partner.x)) + 0.5                       // real Pac-Man tunnel (GridMap.tunnelPartner)
                py = Double(rowsCount - 1 - Int(partner.y)) + 0.5
            } else {
                if d.x != 0 { py += max(-speed, min(speed, ccy - py)) }   // stay centred on the lane
                else        { px += max(-speed, min(speed, ccx - px)) }
                if open(col + d.x, row + d.y) {
                    px += Double(d.x) * speed; py += Double(d.y) * speed
                } else {                                                  // stop at the wall, not past the tile centre
                    if d.x > 0 { px = min(px + speed, ccx) } else if d.x < 0 { px = max(px - speed, ccx) }
                    if d.y > 0 { py = min(py + speed, ccy) } else if d.y < 0 { py = max(py - speed, ccy) }
                }
            }
        } else {
            // Released: always finish the step FORWARD onto a tile centre. If Pete is past the
            // current centre with an open lane ahead, glide onto the next centre; otherwise
            // settle on the current tile's centre. Either way he lands rounded to a tile centre.
            let past = (moveDir.x != 0 && Double(moveDir.x) * (px - ccx) > 0) ||
                       (moveDir.y != 0 && Double(moveDir.y) * (py - ccy) > 0)
            let ahead = past && open(col + moveDir.x, row + moveDir.y)
            let tx = Double(ahead ? col + moveDir.x : col) + 0.5
            let ty = Double(ahead ? row + moveDir.y : row) + 0.5
            px += max(-speed, min(speed, tx - px))
            py += max(-speed, min(speed, ty - py))
        }
        for i in billboards.indices where billboards[i].alive && billboards[i].worldH < 0.5 {
            if abs(billboards[i].x - px) < 0.5 && abs(billboards[i].y - py) < 0.5 {
                billboards[i].alive = false; billboards[i].node.isHidden = true
                let bc = Int(billboards[i].x), br = Int(billboards[i].y)
                mapPickups[mapKey(bc, br)]?.isHidden = true
                switch map[br][bc] {
                case Strings.Tile.goldDiscChar:    sound.playGoldDisc(); state.collectedGoldDiscs += 1; state.bumpScore(by: 5); popPoints(5); startGoldDiscMode()
                case Strings.Tile.waterPelletChar: sound.playWaterGunPickup(); state.bumpScore(by: 50); popPoints(50)
                default:                           sound.playDotBlip(); state.collectedDots += 1; state.bumpScore(by: 1)
                }
                refreshHUD()
            }
        }
        collectStationary()
        moveShots()
        bossController.advance(1.0 / 60.0)          // fixed dt = 100% game's per-frame step
        syncBossNodes()
        // Capture each boss's SMOOTH world position from the mover itself, not node.position:
        // projectSprites overwrites node.position with screen coords for the billboard, and on
        // square-mode dwell frames the mover doesn't rewrite it, so sampling node.position then
        // yields a stale screen coord -> a bogus map-edge cell (Bill blinked to a tunnel).
        bossGrid.removeAll(keepingCapacity: true)
        for e in bossController.entities {
            let p = e.mover?.worldPosition ?? e.node.position
            bossGrid[ObjectIdentifier(e.node)] = (Double(p.x) / 32.0 - 0.5, Double(p.y) / 32.0 - 0.5)
        }
        peteShielded = bossController.isAnyBossSpawning   // shielded exactly while bosses flash in (spawnGrace)
        checkBossCatch()
        if let caught = travelerSpawner?.tryCatch(at: workerGrid) {   // walked onto the traveler's tile
            state.bumpScore(by: caught.traveler.points)
            sound.playFishOrTreat()
            popPoints(caught.traveler.points)
            refreshHUD()
            hud.showMessage(Strings.Message.travelerCaught(emoji: caught.traveler.emoji, points: caught.traveler.points), duration: 2)
        }
        if frightenSecondsLeft > 0 {                      // loop-driven (no Task.sleep on wasm)
            frightenSecondsLeft -= 1.0 / 60.0
            if frightenSecondsLeft <= 0 { endGoldDiscMode() }
        }
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
                    sound.playWaterGunSplash(); state.bumpScore(by: 50); popPoints(50); refreshHUD()
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
        let ch = map[prow][pcol]
        // Brown box = the TPS drop-off (repeatable, never "collected"). Fire once per entry.
        if ch == Strings.Tile.brownBoxChar {
            if !onBrownBox { onBrownBox = true; collectTPSReport() }
            return
        }
        onBrownBox = false
        let key = mapKey(pcol, prow)
        guard !collected.contains(key) else { return }
        switch ch {
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
        let itemIndex = state.reportItems.count - 1   // points ramp 10/25/50/100, like GameScene.handleMachine
        if itemIndex < reportItemPoints.count {
            let pts = reportItemPoints[itemIndex]
            state.bumpScore(by: pts); state.currentReportScore += pts; popPoints(pts)
        }
        sound.playMachine(named: name)
        grayPickup(col, row); refreshHUD()   // dim it like the 100% 2D maze, don't remove it
    }
    // +point popup, same as the 100% game's ScorePopup, in BOTH views: on Pete in
    // the 3D corridor, and on Pete in the mini-map (a matching rise+fade label).
    private func popPoints(_ n: Int) {
        ScorePopup.show(n, at: CGPoint(x: size.width / 2, y: peteBaseY + viewH * 0.30), in: self, fontSize: 54)   // big in the 3D view, above Pete
        let mini = SKLabelNode(fontNamed: Strings.Font.menloBold)
        mini.text = Strings.Score.popup(n)
        mini.fontSize = 40; mini.fontColor = .systemYellow
        mini.position = mapPete.position; mini.zPosition = 6
        mapLayer.addChild(mini)
        mini.run(.sequence([.group([.moveBy(x: 0, y: 42, duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
    }

    // Turn in a completed TPS report at the brown box (mirrors GameScene.collectTPSReport).
    private func collectTPSReport() {
        guard state.reportItems.count == Strings.Machine.required.count else {
            let missing = Strings.Machine.required.filter { !state.reportItems.contains($0) }
            hud.showMessage(Strings.Message.tpsMissingItems(missing), duration: 5)
            sound.playTpsMissingItems(missing)
            return
        }
        state.tpsReportsDelivered += 1
        state.reportItems.removeAll()
        let tpsPoints = state.level * 100 + 100
        state.bumpScore(by: tpsPoints); state.currentReportScore = 0
        popPoints(tpsPoints)
        sound.playTpsDeliver()
        let gainedLife = state.lives < HUD.maxLives
        if gainedLife { state.lives += 1 }
        resetCollectedMachines()   // un-gray so a fresh report can be gathered (GameScene.resetGrayedMachines)
        refreshHUD()
        hud.showMessage(Strings.Message.tpsTurnedIn(points: tpsPoints, gainedLife: gainedLife), duration: 3)
    }
    private func resetCollectedMachines() {
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                switch ch {
                case Strings.Tile.printerChar, Strings.Tile.faxChar, Strings.Tile.coverSheetChar, Strings.Tile.bookBinderChar:
                    let key = mapKey(c, r); collected.remove(key)
                    for i in billboards.indices where Int(billboards[i].x) == c && Int(billboards[i].y) == r { billboards[i].node.alpha = 1 }
                    mapPickups[key]?.alpha = 1
                default: break
                }
            }
        }
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
        // A practice session (launched from the editor) returns to the editor at the
        // level under test, matching GameScene.returnToTitleScene().
        if state.practiceMode {
            let editor = LevelEditorScene(size: size)
            editor.scaleMode = .aspectFit
            editor.currentLevelIndex = max(0, state.level - 1)
            view?.presentScene(editor, transition: .fade(withDuration: 0.5))
            return
        }
        view?.presentScene(TitleScene(size: size), transition: .fade(withDuration: 0.5))
    }

    // Same game-over screen as the 2D levels, with name entry when the score qualifies.
    private func showGameOver() {
        sound.stopAllAudio()
        let screen = GameOverScreen(
            size: size, font: Strings.Font.menloBold,
            score: state.score, highScore: state.highScore,
            defaultName: LocalHighScores.savedUsername ?? "", allowEntry: !state.practiceMode,
            onPlay: { [weak self] in self?.restartDoom() },
            onEsc:  { [weak self] in self?.exit() })
        screen.zPosition = 2000
        addChild(screen)
        gameOverScreen = screen
    }
    private func restartDoom() {
        gameOverScreen?.removeFromParent(); gameOverScreen = nil
        let bonus = DoomScene(size: size)
        bonus.scaleMode = scaleMode
        bonus.practiceMode = practiceMode
        bonus.startingLevel = startingLevel
        view?.presentScene(bonus, transition: .fade(withDuration: 0.5))
    }

    // MARK: - Input (steer at junctions, relative to facing)
    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        if let s = gameOverScreen {                   // type the name (when qualified); PLAY/ESC otherwise
            #if os(macOS)
            s.handleKey(usernameKeyCode(for: event), shift: event.modifierFlags.contains(.shift))
            #else
            s.handleKey(code, shift: false)
            #endif
            return
        }
        switch code {
        case KeyCode.esc:                       exit()
        case KeyCode.keyP:                      togglePause()
        case KeyCode.space:                     if !event.isARepeat { fire() }
        case KeyCode.arrowLeft,  KeyCode.keyA:  wantDir = (x: moveDir.y, y: -moveDir.x)   // turn left
        case KeyCode.arrowRight, KeyCode.keyD:  wantDir = (x: -moveDir.y, y: moveDir.x)   // turn right
        case KeyCode.arrowDown,  KeyCode.keyS:  wantDir = (x: -moveDir.x, y: -moveDir.y)  // about-face 180, not reverse
        case KeyCode.arrowUp,    KeyCode.keyW:  pressed.insert(code)
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
        ring.lineWidth = 2; ring.zPosition = 300   // above the radar panel (200/201) so the controls are never cropped
        addChild(ring)

        joystickCenter = CGPoint(x: fireOnLeft ? size.width - joystickRadius : joystickRadius, y: joystickRadius + 15)
        let base = SKShapeNode(circleOfRadius: joystickRadius)
        base.position = joystickCenter
        base.fillColor = SKColor(white: 1, alpha: 0.06); base.strokeColor = SKColor(white: 1, alpha: 0.5)
        base.lineWidth = 2; base.zPosition = 300
        addChild(base)
        // Four ring-sector wedges split by an X = the D-pad buttons. A diagonal press
        // lights two and steers forward + a turn together. Arrow glyph in each wedge.
        let dirs: [(String, CGFloat, String)] = [("up", .pi / 2, "\u{25B2}"), ("left", .pi, "\u{25C0}"),
                                                 ("down", -.pi / 2, "\u{25BC}"), ("right", 0, "\u{25B6}")]
        for (name, ang, glyph) in dirs {
            let w = SKShapeNode(path: dpadWedgePath(centerAngle: ang))
            w.position = joystickCenter
            w.fillColor = SKColor(white: 1, alpha: 0.12); w.strokeColor = .clear
            w.lineWidth = 0; w.zPosition = 301
            addChild(w); dpadWedges[name] = w
            let arrow = SKLabelNode(text: glyph)
            arrow.fontSize = 24; arrow.fontColor = SKColor(white: 1, alpha: 0.7)
            arrow.verticalAlignmentMode = .center; arrow.horizontalAlignmentMode = .center
            let r = (joystickDeadzone + joystickRadius) / 2
            arrow.position = CGPoint(x: joystickCenter.x + cos(ang) * r, y: joystickCenter.y + sin(ang) * r)
            arrow.zPosition = 302
            addChild(arrow)
        }
        // X boundary lines (the four diagonals) only — no centre ring.
        let xPath = CGMutablePath()
        for k in 0..<4 {
            let t = CGFloat.pi / 4 + CGFloat(k) * CGFloat.pi / 2
            xPath.move(to: CGPoint(x: cos(t) * joystickDeadzone, y: sin(t) * joystickDeadzone))
            xPath.addLine(to: CGPoint(x: cos(t) * joystickRadius, y: sin(t) * joystickRadius))
        }
        let xlines = SKShapeNode(path: xPath)
        xlines.position = joystickCenter
        xlines.strokeColor = SKColor(white: 1, alpha: 0.5); xlines.lineWidth = 2
        xlines.zPosition = 301
        addChild(xlines)
    }

    // Ring-sector wedge (deadzone radius -> outer radius), a full 90° so the four
    // wedges MEET at the diagonals (no dead gaps); the X reads as the stroked boundary
    // between neighbours, and the diagonal corner sits on the edge of both wedges so a
    // corner press fires both. Polygon (move/addLine only) so it renders on WASM too.
    private func dpadWedgePath(centerAngle: CGFloat) -> CGPath {
        let inner = joystickDeadzone, outer = joystickRadius
        let a0 = centerAngle - .pi / 4, a1 = centerAngle + .pi / 4
        let steps = 10
        let p = CGMutablePath()
        for i in 0...steps {
            let t = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
            let pt = CGPoint(x: cos(t) * outer, y: sin(t) * outer)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        for i in 0...steps {
            let t = a1 - (a1 - a0) * CGFloat(i) / CGFloat(steps)
            p.addLine(to: CGPoint(x: cos(t) * inner, y: sin(t) * inner))
        }
        p.closeSubpath()
        return p
    }

    private func radius(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y; return (dx * dx + dy * dy).squareRoot()
    }

    // Desktop mouse = a single finger (the on-screen D-pad is really for phones).
    // Once any true touch arrives, ignore this synthetic pointer so we don't
    // double-drive the D-pad on a phone (the host emits BOTH for finger 0).
    override func mouseDown(with event: NSEvent) {
        if let s = gameOverScreen { s.handleTap(at: s.convert(event.location(in: self), from: self)); return }
        if usingTouch { return }
        pointerBegan(finger: 0, at: event.location(in: self))
    }
    override func mouseDragged(with event: NSEvent) {
        if usingTouch { return }
        if dpadFinger[0] != nil { dpadSet(finger: 0, phase: 1, at: event.location(in: self)) }
    }
    override func mouseUp(with event: NSEvent) {
        if usingTouch { return }
        if dpadFinger[0] != nil { dpadSet(finger: 0, phase: 2, at: event.location(in: self)) }
    }

    // MARK: - Multi-touch D-pad (phone). Each finger lights at most one wedge, so
    // forward + a turn happen only when two fingers are physically down at once.
    func touchBegan(finger: Int, at p: CGPoint) {
        if gameOverScreen != nil { return }   // game-over menu rides the synthetic mouse pointer (no double-fire)
        usingTouch = true
        pointerBegan(finger: finger, at: p)
    }
    func touchMoved(finger: Int, at p: CGPoint) {
        if dpadFinger[finger] != nil { dpadSet(finger: finger, phase: 1, at: p) }
    }
    func touchEnded(finger: Int, at p: CGPoint) {
        if dpadFinger[finger] != nil { dpadSet(finger: finger, phase: 2, at: p) }
    }

    private func pointerBegan(finger: Int, at p: CGPoint) {
        guard !isUserPaused, !dying else { return }
        if !controlsShown { fire(); return }   // water gun hidden: a tap anywhere fires
        if radius(p, joystickCenter) <= joystickRadius { dpadSet(finger: finger, phase: 0, at: p); return }
        if radius(p, fireButtonCenter) <= fireButtonRadius { fire() }
    }

    // Which single wedge a point is in ("" = centre hole / outside the ring).
    private func dpadWedgeAt(_ p: CGPoint) -> String {
        let dx = p.x - joystickCenter.x, dy = p.y - joystickCenter.y
        let mag = (dx * dx + dy * dy).squareRoot()
        if mag < joystickDeadzone || mag > joystickRadius { return "" }
        if abs(dy) >= abs(dx) { return dy > 0 ? "up" : "down" }   // scene y-up: up = forward
        return dx > 0 ? "right" : "left"
    }

    private func dpadSet(finger: Int, phase: Int, at p: CGPoint) {
        let prev = dpadFinger[finger] ?? ""
        let w = phase == 2 ? "" : dpadWedgeAt(p)
        if w.isEmpty { dpadFinger[finger] = nil } else { dpadFinger[finger] = w }
        // One-shot turn the moment a finger ENTERS a turn wedge: left/right = 90°, down = 180°.
        if !w.isEmpty, w != prev {
            switch w {
            case "left":  wantDir = (x: moveDir.y, y: -moveDir.x)
            case "right": wantDir = (x: -moveDir.y, y: moveDir.x)
            case "down":  wantDir = (x: -moveDir.x, y: -moveDir.y)
            default:      break
            }
        }
        applyDpad()
    }

    private func applyDpad() {
        var up = false, down = false, left = false, right = false
        for (_, w) in dpadFinger {
            switch w {
            case "up": up = true; case "down": down = true
            case "left": left = true; case "right": right = true
            default: break
            }
        }
        if up { pressed.insert(KeyCode.arrowUp) } else { pressed.remove(KeyCode.arrowUp) }
        pressed.remove(KeyCode.arrowDown)   // up = forward (held); down is a 180° turn, not reverse
        highlightDPad(up: up, down: down, left: left, right: right)
    }
    private func highlightDPad(up: Bool, down: Bool, left: Bool, right: Bool) {
        let on: [String: Bool] = ["up": up, "down": down, "left": left, "right": right]
        for (k, v) in on { dpadWedges[k]?.fillColor = SKColor(white: 1, alpha: v ? 0.34 : 0.12) }
    }

    required init?(coder: NSCoder) { fatalError(Strings.System.initCoderUnsupported) }
    override init(size: CGSize) { super.init(size: size) }
}
