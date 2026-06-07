import SpriteKit
import AppKit

// MARK: - Shared base for the 3D bonus scenes (Doom raycaster, Voxel painter, Iso overhead)
class Scene3D: SKScene, BossControllerDelegate, Bonus3DScene, SKTouchResponder {

    // MARK: - Maze (loaded for the selected level; the editor's test plays the edited rows)
    lazy var map: [[UInt8]] =
        LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1))).map { Array($0.utf8) }
    var rowsCount: Int { map.count }
    var colsCount: Int { map.first?.count ?? 0 }

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

    func isWall(_ x: Double, _ y: Double) -> Bool {
        let c = Int(x.rounded(.down)), r = Int(y.rounded(.down))
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return true }
        return map[r][c] == Strings.Tile.wallChar
    }

    // MARK: - Pete + chase camera (grid coords; y increases down the rows array)
    var px = 1.5, py = 1.5, angle = 0.0
    var moveDir = (x: 1, y: 0)       // current lane direction (cardinal)
    var wantDir: (x: Int, y: Int)? = nil   // queued turn (taken at the next junction)
    var tcx = 1.5, tcy = 1.5, targetAngle = 0.0
    let camBack = 0.65               // how far the camera trails behind Pete

    func open(_ c: Int, _ r: Int) -> Bool {
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return false }
        return map[r][c] != Strings.Tile.wallChar
    }
    func cardinal(_ d: (x: Int, y: Int)) -> Double {
        if d.x > 0 { return 0 }; if d.x < 0 { return .pi }
        return d.y > 0 ? .pi / 2 : -.pi / 2
    }

    // MARK: - Layout / projection
    var columns: Int { 220 }
    var radarH: CGFloat = 180
    var viewH: CGFloat { size.height - radarH }
    var viewMidY: CGFloat { radarH + viewH * 0.70 }   // horizon, lifted for a look-down view
    let floorA = SKShapeNode()   // alternating floor-tile checker, cast per frame
    let floorB = SKShapeNode()
    let floorFar = SKShapeNode()  // far rows: solid (the checker aliases to garbage at distance)
    var zbuf: [Double] = []
    var camX = 0.0, camY = 0.0

    // MARK: - Billboards (pooled: built once, projected each frame)
    struct Billboard { let node: SKNode; let nativeH: CGFloat; let worldH: CGFloat; let x, y: Double; var alive: Bool }
    var billboards: [Billboard] = []

    // MARK: - Bosses — the REAL BossController from the 100% game (speed, square +
    // smooth modes, flee/splash/capture/respawn all inherited; nothing hand-rolled).
    var gridMap: GridMap!
    var pathfinder: Pathfinder!
    var bossController: BossController!
    var travelerSpawner: TravelerSpawner!   // the fish/treat that walks the maze (same spawner as 2D)
    var bossMapNodes: [ObjectIdentifier: PixelPerson] = [:]   // radar mirror per boss node
    var bossNativeH: [ObjectIdentifier: CGFloat] = [:]        // cached unscaled height for projection
    var bossFeet: [ObjectIdentifier: CGFloat] = [:]           // cached LOCAL feet offset (frame.minY relative to origin)
    var bossGrid: [ObjectIdentifier: (Double, Double)] = [:]  // smooth (continuous) grid pos per boss, captured pre-projection
    var peteShielded = false
    struct Shot { var x, y: Double; let dir: (x: Int, y: Int); let node: SKNode; let nativeH: CGFloat; let mapNode: SKNode; var alive: Bool }
    var shots: [Shot] = []
    var gameOver = false
    var gameOverScreen: GameOverScreen?
    var dying = false
    var deathFramesLeft = 0
    let deathFrames = 90   // 1.5s at 60fps: hold the catcher on screen
    var pressed = Set<Int>()
    var collected = Set<Int>()
    let sound = SoundManager()

    // MARK: - On-screen controls (same layout/sizing as the 100% game)
    let joystickRadius: CGFloat = 129.375
    let joystickDeadzone: CGFloat = 20
    var joystickCenter = CGPoint.zero
    // X-pattern D-pad: four ring-sector wedges (up/down/left/right) split by an X.
    // Each finger lights at most one wedge; two fingers light two (forward + a turn)
    // ONLY when the phone actually has two fingers down. Keyed "up/down/left/right".
    var dpadWedges: [String: SKShapeNode] = [:]
    var dpadThumb: SKShapeNode?
    var dpadFinger: [Int: String] = [:]
    var joyFingers = Set<Int>()   // fingers captured by the joystick from press to release; drags re-engage even after leaving the ring
    var usingTouch = false
    var fireButtonCenter = CGPoint.zero
    let fireButtonRadius: CGFloat = 129.375
    var controlsShown = false

    let spriteLayer = SKNode()
    let nameLayer = SKNode()
    var bossNames: [ObjectIdentifier: SKLabelNode] = [:]
    var peteName: SKLabelNode!
    var pete: PixelPerson!
    var peteBaseY: CGFloat = 0
    var bob = 0.0
    var throbClock = 0.0   // free-running clock for the post-spawn boss pulse

    var hud: HUD!
    let uiLayer = SKNode()
    let state = RoundState()
    let waterGun = WaterGunState()
    var waterGunPickedUp = false
    let goldDisc = GoldDiscTimer()
    private let goldDiscDuration: TimeInterval = 20
    var frightenSecondsLeft: TimeInterval = 0
    let reportItemPoints = [10, 25, 50, 100]
    var onBrownBox = false
    var spawnPx = 1.5, spawnPy = 1.5
    var isUserPaused = false
    private var bossToggleTaps = 0
    private var bossToggleWindow = 0
#if os(WASI)
    static var bossesEnabled = false
#else
    static var bossesEnabled = true
#endif
    var bossOffLabel: SKLabelNode?

    // MARK: - Minimap (the real 2D level, centered at the bottom)
    let mapLayer = SKNode()
    var mapPete: PixelPerson!
    var mapPickups: [Int: SKNode] = [:]
    let mapCell: CGFloat = 32
    var mapScale: CGFloat = 1

    // MARK: - Lifecycle
    override init(size: CGSize) { super.init(size: size) }
    required init?(coder: NSCoder) { fatalError(Strings.System.initCoderUnsupported) }

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
    func placeStart() {
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

    func buildSky() {
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
        floorFar.fillColor = cube.blended(withFraction: 0.81, of: .black) ?? cube   // mid shade between A/B
        floorA.strokeColor = .clear; floorB.strokeColor = .clear; floorFar.strokeColor = .clear
        floorA.zPosition = -2; floorB.zPosition = -2; floorFar.zPosition = -2
        floorA.isAntialiased = false; floorB.isAntialiased = false; floorFar.isAntialiased = false
        addChild(floorA); addChild(floorB); addChild(floorFar)
    }

    // Bake a static node tree to one texture and add it as a single sprite (one
    // draw call). Falls back to the live tree if no view is available to bake with.
    func addBaked(_ tree: SKNode, to parent: SKNode, z: CGFloat) {
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

    func buildColumns() {
        // Wall quads are pooled lazily in render() (count varies with the view).
    }

    func emojiBillboard(_ text: String, _ fontSize: CGFloat) -> SKNode {
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
    func throbbing(_ visual: SKNode, _ peak: CGFloat, _ dur: TimeInterval) -> SKNode {
        let parent = SKNode()
        parent.addChild(visual)
        visual.run(.repeatForever(.sequence([.scale(to: peak, duration: dur), .scale(to: 1.0, duration: dur)])))
        return parent
    }

    func buildBillboards() {
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

    func buildPete() {
        pete = makePete()
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

    func makeNameplate(_ text: String) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: Strings.Font.menloBold)
        l.text = text
        l.fontSize = 22
        l.fontColor = .white
        l.horizontalAlignmentMode = .center
        l.verticalAlignmentMode = .center
        return l
    }

    func buildHUD() {
        uiLayer.zPosition = 1000
        addChild(uiLayer)
        hud = HUD(requiredItems: Strings.Machine.required)
        hud.install(in: uiLayer, size: size, extraRow: false)   // compact 150/200-style HUD, never the extended row
        state.dotCount = map.reduce(0) { $0 + $1.filter { $0 == Strings.Tile.dotChar || $0 == Strings.Tile.hideoutChar }.count }
        let lbl = SKLabelNode(fontNamed: Strings.Font.menloBold)
        lbl.fontSize = 20; lbl.horizontalAlignmentMode = .right
        lbl.position = CGPoint(x: size.width - 12, y: size.height - 25)
        lbl.zPosition = 1001
        uiLayer.addChild(lbl); bossOffLabel = lbl
        updateBossLabel()
        refreshHUD()
    }

    func refreshHUD() {
        hud.updateStatus(score: state.score, highScore: state.highScore, level: state.level,
                         dots: state.collectedDots, total: state.dotCount,
                         reports: state.tpsReportsDelivered, items: state.reportItems)
        hud.updateLives(state.lives)
        hud.updateWaterGun(active: waterGun.isActive, pellets: waterGunPickedUp ? waterGun.pelletsRemaining : -1, blueMode: false)
        hud.updateLevelEmojis(Array(levelTravelers.prefix(1)))
    }

    func startGoldDiscMode() {
        goldDisc.activate()
        bossController.setGoldDiscActive(true)   // recolors the real boss nodes (the 3D billboards) to flee blue
        recolorMinimapBosses(flee: true)         // mirror it on the radar copies
        sound.startGoldDiscBass()
        frightenSecondsLeft = goldDiscDuration
        hud.showMessage(Strings.Message.goldDiscActivated, duration: 3)
        refreshHUD()
    }
    func endGoldDiscMode() {
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
    func recolorMinimapBosses(flee: Bool) {
        for e in bossController.entities {
            guard let mn = bossMapNodes[ObjectIdentifier(e.node)] else { continue }
            applyFleePalette(mn, flee: flee, blueprint: e.blueprintIndex)
        }
    }
    func applyFleePalette(_ p: PixelPerson, flee: Bool, blueprint: Int) {
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

    // All-3-differ. Empty default; every scene overrides with its own body.
    func startDeath(node: PixelPerson) { }

    func updateDeath() {
        deathFramesLeft -= 1                          // hold the catcher on screen, still, then respawn
        if deathFramesLeft <= 0 { finishDeath() }
    }

    func finishDeath() {
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
    func bossesAllFar() -> Bool {
        let pgx = Int(px.rounded(.down)), pgy = rowsCount - 1 - Int(py.rounded(.down))
        return bossController.entities.allSatisfy { e in
            let bg = e.mover?.grid ?? e.ai.grid
            return max(abs(Int(bg.x) - pgx), abs(Int(bg.y) - pgy)) >= 3
        }
    }

    func checkBossCatch() {
        let pgx = Int(px.rounded(.down)), pgy = rowsCount - 1 - Int(py.rounded(.down))
        for e in bossController.entities {
            let bg = e.mover?.grid ?? e.ai.grid
            guard Int(bg.x) == pgx, Int(bg.y) == pgy, !bossController.isImmobilized(boss: e.node) else { continue }
            if bossController.isInFleeMode(boss: e.node) { bossController.capture(boss: e.node) }
            else if !peteShielded && Scene3D.bossesEnabled { startDeath(node: e.node); return }
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
            if dropletThreatens(dropletGrid: dGrid, dir: dir, boss: bossGrid, range: dropletDodgeRange, isWalkable: { gridMap.isWalkable($0) }) { return dir }
        }
        return nil
    }

    func updateBossLabel() {
        bossOffLabel?.text = Scene3D.bossesEnabled ? "BOSS ON" : "BOSS OFF"
        bossOffLabel?.fontColor = Scene3D.bossesEnabled ? SKColor(white: 1, alpha: 0.3) : .systemRed
    }

    func toggleBossMode() {
        Scene3D.bossesEnabled.toggle()
        updateBossLabel()
        hud.showMessage(Scene3D.bossesEnabled ? "BOSS ON" : "BOSS OFF", duration: 2)
    }

    func togglePause() {
        isUserPaused.toggle()
        hud.showPaused(isUserPaused)
        pauseSceneLayers(isUserPaused)
        if isUserPaused { pete.stopWalking(); mapPete.stopWalking(); sound.pauseAudio() }
        else { pete.startWalking(); mapPete.startWalking(); sound.resumeAudio() }
    }

    func mapKey(_ c: Int, _ r: Int) -> Int { r * colsCount + c }
    func mapLocal(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) * mapCell, y: (CGFloat(rowsCount) - CGFloat(y)) * mapCell)
    }
    func buildMap() {
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

    func setupBossController() {
        let rows = LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1)))
        gridMap = GridMap(tileSize: 32, rows: rows)
        gridMap.xOffset = 0; gridMap.yOffset = 0
        pathfinder = Pathfinder(map: gridMap)
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder, sound: sound, containerOriginX: 0)
        bossController.delegate = self
        // Spawn positions from the level data, in the bottom-up grid GridMap uses.
        var overrides: [(blueprintIndex: Int, position: CGPoint)] = []
        for (ri, row) in rows.reversed().enumerated() {
            for (ci, ch) in row.utf8.enumerated() {
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
    func syncBossNodes() {
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
        if bossToggleWindow > 0 { bossToggleWindow -= 1 } else { bossToggleTaps = 0 }
        if isUserPaused || gameOver { return }
        if dying { updateDeath(); return }
        step()
        if dying { return }   // step() just caught Pete: startDeath pinned the catcher — don't let render re-project it past Pete
        render()
    }

    // All-3-differ. Empty default; every scene overrides with its own renderer.
    func render() { }

    func bossNameplate(for node: SKNode, text: String) -> SKLabelNode {
        let id = ObjectIdentifier(node)
        if let l = bossNames[id] { return l }
        let l = makeNameplate(text)
        bossNames[id] = l
        nameLayer.addChild(l)
        return l
    }

    func updateMap() {
        mapPete.position = mapLocal(px, py)
        mapPete.setFacing(facing(moveDir))
        for e in bossController.entities {
            guard let mn = bossMapNodes[ObjectIdentifier(e.node)], let g = bossGrid[ObjectIdentifier(e.node)] else { continue }
            mn.position = mapLocal(g.0 + 0.5, Double(rowsCount) - 0.5 - g.1)
            if let d = e.mover?.dir { mn.setFacing(d) }
        }
        for s in shots where s.alive { s.mapNode.position = mapLocal(s.x, s.y) }
    }

    func facing(_ d: (x: Int, y: Int)) -> MoveDirection {
        d.x > 0 ? .right : d.x < 0 ? .left : d.y > 0 ? .down : .up
    }

    // MARK: - Lane movement (Pac-Man style: auto-forward, turn at junctions)
    func step() {
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
        if Scene3D.bossesEnabled || bossesAllFar() {
            bossController.advance(1.0 / 60.0)
        } else {
            bossController.stopAll()
        }
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

    func moveShots() {
        let speed = 0.22
        for i in shots.indices where shots[i].alive {
            shots[i].x += Double(shots[i].dir.x) * speed
            shots[i].y += Double(shots[i].dir.y) * speed
            if isWall(shots[i].x, shots[i].y) { shots[i].alive = false; continue }
            let sgx = Int(shots[i].x.rounded(.down)), sgy = rowsCount - 1 - Int(shots[i].y.rounded(.down))
            for e in bossController.entities {
                let bg = e.mover?.grid ?? e.ai.grid
                if Int(bg.x) == sgx, Int(bg.y) == sgy {
                    let hitAt = e.node.position, hitZ = e.node.zPosition
                    let splash = SpriteFactory.waterSplash(spread: min(2.2, max(0.5, e.node.calculateAccumulatedFrame().height / 60)))
                    bossController.splash(boss: e.node)   // real splash + loop-driven 5s respawn
                    shots[i].alive = false
                    sound.playWaterGunSplash(); state.bumpScore(by: 50); popPoints(50); refreshHUD()
                    splash.position = hitAt; splash.zPosition = hitZ + 1; spriteLayer.addChild(splash)
                    break
                }
            }
        }
        for s in shots where !s.alive { s.node.removeFromParent(); s.mapNode.removeFromParent() }
        shots.removeAll { !$0.alive }
    }

    func fire() {
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
    func collectStationary() {
        let pcol = Int(px.rounded(.down)), prow = Int(py.rounded(.down))
        guard prow >= 0, prow < rowsCount, pcol >= 0, pcol < map[prow].count else { return }
        let ch = map[prow][pcol]
        // Brown box = the TPS drop-off (repeatable, never "collected"). Fire once per entry.
        if ch == Strings.Tile.brownBoxChar {
            if !onBrownBox { onBrownBox = true; collectTPSReport(pcol, prow) }
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
    func collectMachine(_ name: String, _ key: Int, _ col: Int, _ row: Int) {
        guard Strings.Machine.required.contains(name), !state.reportItems.contains(name) else { return }
        collected.insert(key)
        state.reportItems.insert(name)
        let itemIndex = state.reportItems.count - 1   // points ramp 10/25/50/100, like GameScene.handleMachine
        if itemIndex < reportItemPoints.count {
            let pts = reportItemPoints[itemIndex]
            state.bumpScore(by: pts); state.currentReportScore += pts; popPoints(pts)
        }
        sound.playMachine(named: name)
        grayPickupInWorld(col: col, row: row); refreshHUD()
    }
    // +point popup, same as the 100% game's ScorePopup, in BOTH views: on Pete in
    // the 3D corridor, and on Pete in the mini-map (a matching rise+fade label).
    func popPoints(_ n: Int) {
        popPointsInWorld(n)
        let mini = SKLabelNode(fontNamed: Strings.Font.menloBold)
        mini.text = Strings.Score.popup(n)
        mini.fontSize = 40; mini.fontColor = .systemYellow
        mini.position = mapPete.position; mini.zPosition = 6
        mapLayer.addChild(mini)
        mini.run(.sequence([.group([.moveBy(x: 0, y: 42, duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
    }

    // Turn in a completed TPS report at the brown box (mirrors GameScene.collectTPSReport).
    func collectTPSReport(_ col: Int, _ row: Int) {
        guard state.reportItems.count == Strings.Machine.required.count else {
            let missing = Strings.Machine.required.filter { !state.reportItems.contains($0) }
            hud.showMessage(Strings.Message.tpsMissingItems(missing), duration: 5)
            sound.playTpsMissingItems(missing)
            return
        }
        grayBrownBox(col, row)   // dim the box on turn-in, same fade + cooldown as a collected machine
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
    func resetCollectedMachines() {
        for r in 0..<rowsCount {
            for (c, ch) in map[r].enumerated() {
                switch ch {
                case Strings.Tile.printerChar, Strings.Tile.faxChar, Strings.Tile.coverSheetChar, Strings.Tile.bookBinderChar:
                    ungrayPickupInWorld(col: c, row: r)
                default: break
                }
            }
        }
    }
    func hidePickup(_ col: Int, _ row: Int) {
        hidePickupInWorld(col: col, row: row)
    }
    func grayPickup(_ col: Int, _ row: Int) {
        grayPickupInWorld(col: col, row: row)
    }
    // Brown box on a TPS turn-in: same dim + cooldown as a collected machine, then restore.
    func grayBrownBox(_ col: Int, _ row: Int, cooldown: TimeInterval = 15) {
        let mk = mapKey(col, row)
        guard let n = findBrownBoxNode(col: col, row: row) else { return }
        guard n.action(forKey: Strings.ActionKey.machineCooldown) == nil else { return }
        n.alpha = 0.55; mapPickups[mk]?.alpha = 0.55
        n.run(.sequence([.wait(forDuration: cooldown), .run { [weak self] in
            n.alpha = 1; self?.mapPickups[mk]?.alpha = 1 }]), withKey: Strings.ActionKey.machineCooldown)
    }

    // MARK: - Pickup hooks (IsoScene overrides for isoPickups)
    func hidePickupInWorld(col: Int, row: Int) {
        let key = mapKey(col, row)
        for i in billboards.indices where billboards[i].alive && Int(billboards[i].x) == col && Int(billboards[i].y) == row {
            billboards[i].alive = false; billboards[i].node.isHidden = true
        }
        mapPickups[key]?.isHidden = true
    }
    func grayPickupInWorld(col: Int, row: Int) {
        let key = mapKey(col, row)
        for i in billboards.indices where Int(billboards[i].x) == col && Int(billboards[i].y) == row {
            billboards[i].node.alpha = 0.55
        }
        mapPickups[key]?.alpha = 0.55
    }
    func ungrayPickupInWorld(col: Int, row: Int) {
        let key = mapKey(col, row)
        collected.remove(key)
        for i in billboards.indices where Int(billboards[i].x) == col && Int(billboards[i].y) == row { billboards[i].node.alpha = 1 }
        mapPickups[key]?.alpha = 1
    }
    func findBrownBoxNode(col: Int, row: Int) -> SKNode? {
        return billboards.first(where: { Int($0.x) == col && Int($0.y) == row })?.node
    }
    func popPointsInWorld(_ n: Int) {
        ScorePopup.show(n, at: CGPoint(x: size.width / 2, y: peteBaseY + viewH * 0.30), in: self, fontSize: 54)
    }
    func pauseSceneLayers(_ paused: Bool) {
        spriteLayer.isPaused = paused
        mapLayer.isPaused = paused
    }
    func makePete() -> PixelPerson {
        SpriteFactory.petePersonBack(walkExaggeration: 1)
    }
    func commonSetup() {
        buildPete()
        buildMap()
        setupBossController()
        buildHUD()
        buildControls()
        render()
        sound.startBackgroundMusic()
    }

    func exit() {
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
    func showGameOver() {
        sound.stopAllAudio()
        let screen = GameOverScreen(
            size: size, font: Strings.Font.menloBold,
            score: state.score, highScore: state.highScore,
            defaultName: LocalHighScores.savedUsername ?? "", allowEntry: !state.practiceMode && Scene3D.bossesEnabled,
            onPlay: { [weak self] in self?.restartDoom() },
            onEsc:  { [weak self] in self?.exit() })
        screen.zPosition = 2000
        addChild(screen)
        gameOverScreen = screen
    }

    // All-3-differ (each instantiates its own scene type). Empty default; every scene overrides.
    func restartDoom() { }

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
        case KeyCode.keyB:                      toggleBossMode()
        case KeyCode.space:                     if !event.isARepeat { fire() }
        case KeyCode.arrowLeft,  KeyCode.keyA:  wantDir = (x: moveDir.y, y: -moveDir.x)
        case KeyCode.arrowRight, KeyCode.keyD:  wantDir = (x: -moveDir.y, y: moveDir.x)
        case KeyCode.arrowDown,  KeyCode.keyS:  wantDir = (x: -moveDir.x, y: -moveDir.y)  // about-face 180, not reverse
        case KeyCode.arrowUp,    KeyCode.keyW:  pressed.insert(code)
        default:                                break
        }
    }
    override func keyUp(with event: NSEvent) { pressed.remove(Int(event.keyCode)) }

    // MARK: - On-screen joystick + fire button (drive the same tank input)
    func buildControls() {
        if !ControlMode.current.showsControl { return }
        controlsShown = true
        let fireOnLeft = !ControlMode.current.onLeft   // fire button opposite the dpad
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
        if ControlMode.current.showsStick { addStickThumb(); return }   // STICK: a round follow-thumb instead of the wedge cross
        dpadWedges = buildDpadFace(in: self, center: joystickCenter, inner: joystickDeadzone, outer: joystickRadius, z: 301)
    }
    // STICK mode: a thumb knob that rides the finger; direction still comes from dpadWedgeAt (shared angle logic).
    func addStickThumb() {
        let thumb = SKShapeNode(circleOfRadius: joystickRadius * 0.42)
        thumb.position = joystickCenter
        thumb.fillColor = SKColor(white: 1, alpha: 0.22); thumb.strokeColor = SKColor(white: 1, alpha: 0.6)
        thumb.lineWidth = 2; thumb.zPosition = 301
        addChild(thumb); dpadThumb = thumb
    }
    func moveStickThumb(to p: CGPoint, release: Bool) {
        guard let thumb = dpadThumb else { return }
        if release { thumb.position = joystickCenter; return }
        let dx = p.x - joystickCenter.x, dy = p.y - joystickCenter.y
        let mag = (dx * dx + dy * dy).squareRoot(), lim = joystickRadius * 0.58
        thumb.position = (mag > lim && mag > 0) ? CGPoint(x: joystickCenter.x + dx / mag * lim, y: joystickCenter.y + dy / mag * lim) : p
    }


    func radius(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
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
        if joyFingers.contains(0) { dpadSet(finger: 0, phase: 1, at: event.location(in: self)) }
    }
    override func mouseUp(with event: NSEvent) {
        if usingTouch { return }
        if joyFingers.contains(0) { dpadSet(finger: 0, phase: 2, at: event.location(in: self)); joyFingers.remove(0) }
    }

    // MARK: - Multi-touch D-pad (phone). Each finger lights at most one wedge, so
    // forward + a turn happen only when two fingers are physically down at once.
    func touchBegan(finger: Int, at p: CGPoint) {
        if gameOverScreen != nil { return }   // game-over menu rides the synthetic mouse pointer (no double-fire)
        usingTouch = true
        pointerBegan(finger: finger, at: p)
    }
    func touchMoved(finger: Int, at p: CGPoint) {
        if joyFingers.contains(finger) { dpadSet(finger: finger, phase: 1, at: p) }
    }
    func touchEnded(finger: Int, at p: CGPoint) {
        if joyFingers.contains(finger) { dpadSet(finger: finger, phase: 2, at: p); joyFingers.remove(finger) }
    }

    private func pointerBegan(finger: Int, at p: CGPoint) {
        guard !isUserPaused, !dying else { return }
        if !controlsShown { fire(); return }   // water gun hidden: a tap anywhere fires
        if radius(p, joystickCenter) <= joystickRadius {
            #if os(WASI)
            if !joyFingers.isEmpty {
                let newDir = dpadWedgeAt(p)
                let hasUp = dpadFinger.values.contains { $0.contains("up") }
                guard hasUp && (newDir == "left" || newDir == "right") else { return }
            }
            #endif
            joyFingers.insert(finger); dpadSet(finger: finger, phase: 0, at: p); return
        }
        if radius(p, fireButtonCenter) <= fireButtonRadius { fire(); return }
        bossToggleTaps += 1; bossToggleWindow = 36
        if bossToggleTaps >= 3 { bossToggleTaps = 0; bossToggleWindow = 0; toggleBossMode() }
    }

    func dpadWedgeAt(_ p: CGPoint) -> String {
        dpadCardinal(p, center: joystickCenter, deadzone: joystickDeadzone, radius: joystickRadius)
    }

    func dpadSet(finger: Int, phase: Int, at p: CGPoint) {
        let prev = dpadFinger[finger] ?? ""
        let w = phase == 2 ? "" : dpadWedgeAt(p)
        if w.isEmpty { dpadFinger[finger] = nil } else { dpadFinger[finger] = w }
        moveStickThumb(to: p, release: phase == 2)
        // One-shot turn the moment a lateral / about-face component newly appears under
        // this finger: left/right = 90° (combinable with forward), down = 180° about-face.
        if w != prev {
            if w.contains("left"),  !prev.contains("left")  { wantDir = (x: moveDir.y, y: -moveDir.x) }
            if w.contains("right"), !prev.contains("right") { wantDir = (x: -moveDir.y, y: moveDir.x) }
            if w == "down", prev != "down"                  { wantDir = (x: -moveDir.x, y: -moveDir.y) }
        }
        applyDpad()
    }

    func applyDpad() {
        var up = false, down = false, left = false, right = false
        for (_, w) in dpadFinger {
            if w.contains("up")    { up = true }
            if w.contains("down")  { down = true }
            if w.contains("left")  { left = true }
            if w.contains("right") { right = true }
        }
        if left && right { left = false; right = false }       // opposing laterals cancel
        if down { up = false; left = false; right = false }    // down is always solo
        if (left || right) && !up { /* single lateral, fine */ }
        if up { pressed.insert(KeyCode.arrowUp) } else { pressed.remove(KeyCode.arrowUp) }
        pressed.remove(KeyCode.arrowDown)   // up = forward (held); down is a 180° turn, not reverse
        highlightDPad(up: up, down: down, left: left, right: right)
    }
    func highlightDPad(up: Bool, down: Bool, left: Bool, right: Bool) {
        lightDpadFace(dpadWedges, up: up, down: down, left: left, right: right)
    }
}
