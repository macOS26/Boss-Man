import AppKit
import GameKit
import SpriteKit

// Gameplay scene, common to the macOS master and the wasm port. The game logic
// is shared, only platform input, movement timing, and Game Center fork behind
// #if.
final class GameScene: SKScene, WorkerControllerDelegate, BossControllerDelegate, LevelCompletionHost {
    private let tileSize: CGFloat = 32
    private let goldDiscDuration: TimeInterval = 20
    private var frightenSecondsLeft: TimeInterval = 0
    private let waterHitPoints = 50
    // Boss r=10 + Pete r=10: catch when their centres are within 20px (bodies
    // touch). Under a tile (32px), so being one cell away never triggers it.
    private let bossCatchDistance: CGFloat = 20
    private var pendingCatch: PixelPerson?
    private var deferredBossSpawn: (() -> Void)?
    private var bossSpawnGrace: TimeInterval = 0
    private var bossSpawnMax: TimeInterval = 0
    private var nextBossSpawnSeconds: TimeInterval = 0
    private let requiredItems = Strings.Machine.required
    private let reportItemPoints = Strings.Machine.reportPoints
    private let dropletDodgeRange = 8

    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var mazeBuilder: MazeBuilder!
    var hud: HUD!
    private let sound = SoundManager()

    let state = GameState()
    private let goldDisc = GoldDiscTimer()
    private let waterGun = WaterGunState()
    private var waterGunPickedUp = false
    private var travelerSpawner: TravelerSpawner!
    private var workerController: WorkerController!
    private var bossController: BossController!
    private(set) var isGameOver = false
    var lastUpdateTime: TimeInterval = 0
    var practiceMode: Bool {
        get { state.practiceMode }
        set { state.practiceMode = newValue }
    }
    var startingLevel: Int {
        get { state.level }
        set { state.level = max(1, newValue) }
    }
    var isGoldDiscMode: Bool { goldDisc.isActive }
    var isPeteShielded: Bool { workerController?.isShielded ?? false }
    var workerGrid: CGPoint { workerController.grid }
    var workerDirection: MoveDirection? { workerController.direction }

    private var waterDroplets: [WaterDroplet] = []
    private let waterDropletSpeed: CGFloat = 12 * 32
    private var fireButtonCenter = CGPoint.zero
    private var fireButtonHidden = false
    private let fireButtonRadius: CGFloat = 129.375
    private var isUserPaused = false
    private var pauseOverlay: SKNode? = nil
    // Maze 200% mode (title toggle): an SKCameraNode zoomed 2x that follows Pete,
    // clamped to the scene so the view never scrolls past the maze. Render-only,
    // physics and the grid catch stay in world coordinates, unaffected.
    private var cameraNode: SKCameraNode?
    private var camPos: CGPoint?
    private var camVel: CGPoint = .zero
    // Screen-fixed overlay layer (HUD, fire button, joystick, PAUSED, game-over).
    // A scene child at 100%, a camera child at 200% so it stays unscaled while
    // the board zooms. Re-created fresh each buildLevel (removeAllChildren wipes
    // the previous one).
    private var uiLayer = SKNode()

    private var containerOriginX: CGFloat = 0
    private var swipeStart: CGPoint? = nil
    private var swipeFired = false
    private var moveAnchor: CGPoint? = nil
    private let swipeThreshold: CGFloat = 24
    #if os(macOS)
    private let inputController = PointerInputController()
    #endif

    // MARK: - Joystick (on-screen movement control)
    private let joystickRadius: CGFloat = 129.375
    private let joystickKnobRadius: CGFloat = 51.75
    private let joystickDeadzone: CGFloat = 37.375
    private var joystickCenter = CGPoint.zero
    private var joystickHidden = false
    private var joystickActive = false
    private var joystickThumb: SKShapeNode?
    private var dpadWedges: [String: SKShapeNode] = [:]

    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60   // uncapped play, even when launched from the low-fps editor
        backgroundColor = SpriteFactory.mazeBackground
        anchorPoint = .zero
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        gridMap = GridMap(tileSize: tileSize, rows: currentLevelRows())
        gridMap.yOffset = 0
        // Centre the maze horizontally. On a scene sized to the maze (apple) the
        // offset is 0, on a full-viewport scene (web) it pads the slack so the maze
        // sits centred. containerOriginX feeds the movers their world origin.
        let mazeWidth = CGFloat(gridMap.columnCount) * tileSize
        gridMap.xOffset = max(0, (size.width - mazeWidth) / 2)
        containerOriginX = gridMap.xOffset
        pathfinder = Pathfinder(map: gridMap)
        mazeBuilder = MazeBuilder(map: gridMap)
        hud = HUD(requiredItems: requiredItems)
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound, containerOriginX: containerOriginX)
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder, sound: sound, containerOriginX: containerOriginX)
        bossController.delegate = self
        buildLevel()
        hud.showMessage(state.practiceMode ? Strings.Message.practiceMode : Strings.Message.intro, duration: 3)
        #if os(macOS)
        inputController.delegate = self
        inputController.start()
        view.window?.acceptsMouseMovedEvents = true
        (NSApplication.shared.delegate as? AppDelegate)?.setGameModeActive(true)
        #endif
    }

    override func willMove(from view: SKView) {
        sound.stopAllAudio()
        mazeBuilder.releaseTextures()
        #if os(macOS)
        inputController.unhideCursor()
        (NSApplication.shared.delegate as? AppDelegate)?.setGameModeActive(false)
        #endif
    }

    private func buildLevel() {
        sound.startBackgroundMusic(theme: musicTheme(for: state.level))
        mazeBuilder.cubicleColor = SpriteFactory.cubicleColor(forLevel: state.level)
        gridMap.setRows(currentLevelRows())
        state.dotCount = mazeBuilder.build(in: self, view: view)
        state.goldDiscCount = mazeBuilder.goldDiscPositions.count
        state.waterGunCount = mazeBuilder.waterGunPositions.count
        state.waterPelletCount = mazeBuilder.waterPelletPositions.count
        setupMazeCamera()
        setupUILayer()
        hud.install(in: uiLayer, size: size, extraRow: cameraNode == nil)
        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        workerController = WorkerController(spawnGrid: spawn, gridMap: gridMap, sound: sound, containerOriginX: containerOriginX)
        workerController.delegate = self
        addChild(workerController.node)
        workerController.applySpawnShield()
        installFireButton()
        installJoystick()
        let bossSpawnSeconds = nextBossSpawnSeconds
        nextBossSpawnSeconds = 0
        delayBossSpawn(after: bossSpawnSeconds) { [weak self] in
            guard let self else { return }
            self.bossController.spawn(forLevel: self.state.level,
                                      spawnOverrides: self.mazeBuilder.bossSpawns.map { (blueprintIndex: $0.index, position: $0.position) })
        }
        refreshHUD()
        let scheduledLevel = state.level
        travelerSpawner.scheduleVisits(of: currentTraveler()) { [weak self] in
            guard let self else { return false }
            return self.state.level == scheduledLevel && !self.isGameOver && !self.isUserPaused
        }
    }

    private var clampedLevelIndex: Int { max(0, min(state.level - 1, Levels.levelNames.count - 1)) }
    private func currentLevelRows() -> [String] {
        LevelStore.loadLevel(index: clampedLevelIndex)
    }

    private func musicTheme(for level: Int) -> MusicTheme {
        level % 12 == 0 ? .mib : .normal
    }

    private func currentTraveler() -> LevelTraveler {
        levelTravelers[(state.level - 1) % levelTravelers.count]
    }

    private func firstWalkableCell() -> CGPoint {
        for row in 0..<gridMap.rowCount {
            for col in 0..<gridMap.columnCount {
                let p = CGPoint(x: col, y: row)
                if gridMap.isWalkable(p) && !gridMap.isHideout(p) { return p }
            }
        }
        return .zero
    }

    // MARK: - Input
    // Keyboard + pointer handling is common: the framework bridges the web
    // runtime's Int/CGPoint callbacks into the same (with: NSEvent) overrides
    // apple calls natively, and KeyCode abstracts the per-platform raw codes. Only
    // the input device with no counterpart on the other platform stays behind #if:
    // apple's gamepad / mouse-delta (inputController) and key-repeat filter, web's
    // touch swipe, and apple's Carbon username-key translation (usernameKeyCode,
    // shared with DoomScene in GameOverKeyCompat.swift).

    private func swipeDirection(_ dx: CGFloat, _ dy: CGFloat) -> MoveDirection? {
        guard max(abs(dx), abs(dy)) >= swipeThreshold else { return nil }
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .up : .down
    }

    private func steer(_ dir: MoveDirection) {
        workerController.queueDirection(dir)
        workerController.node.setFacing(dir)
    }

    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        if isGameOver { return }
        if code == KeyCode.keyP {
            togglePause()
            return
        }
        if code == KeyCode.esc {
            returnToTitleScene()
            return
        }
        guard !isUserPaused else { return }
        if code == KeyCode.space {
            fireWaterGun()
            return
        }
        guard !event.isARepeat else { return }
        if let direction = MoveDirection(keyCode: code) { steer(direction) }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isUserPaused, !isGameOver else { return }
        let p = event.location(in: uiLayer)
        if !joystickHidden, joystickCenter.distance(to: p) <= joystickRadius {
            joystickActive = true
            applyJoystick(at: p)
            swipeStart = nil
            moveAnchor = nil
            return
        }
        #if os(macOS)
        fireWaterGun()
        #else
        moveAnchor = p
        if !fireButtonHidden, fireButtonCenter.distance(to: p) <= fireButtonRadius {
            fireWaterGun()
            swipeStart = nil
            return
        }
        swipeStart = ControlMode.current.isHidden ? p : nil // swipe-to-move only in HIDDEN mode, stick/dpad uses the widget
        swipeFired = false
        #endif
    }

    override func mouseUp(with event: NSEvent) {
        if joystickActive {
            joystickActive = false
            recenterJoystickThumb()
            lightDpadFace(dpadWedges, up: false, down: false, left: false, right: false)
            return
        }
        // Swipe release. Dormant on apple (mouseDown fires there and never arms
        // swipeStart), so the guard short-circuits and the writes are harmless.
        let p = event.location(in: uiLayer)
        if let start = swipeStart, !swipeFired, !isGameOver, !isUserPaused {
            if let d = swipeDirection(p.x - start.x, p.y - start.y) {
                steer(d)
            } else if fireButtonHidden {
                fireWaterGun()   // fire button hidden: a tap (no swipe) fires the water gun
            }
        }
        swipeStart = nil
        moveAnchor = p
    }

    override func mouseDragged(with event: NSEvent) {
        let p = event.location(in: uiLayer)
        if joystickActive {
            applyJoystick(at: p)
            return
        }
        #if os(macOS)
        inputController.handleMouseDelta(dx: event.deltaX, dy: event.deltaY)
        #else
        if isGameOver || isUserPaused {
            moveAnchor = p
            return
        }
        if let start = swipeStart {
            if !swipeFired, let d = swipeDirection(p.x - start.x, p.y - start.y) {
                steer(d)
                swipeFired = true
            }
            return
        }
        guard ControlMode.current.isHidden else { return }   // drag-to-steer only in HIDDEN mode
        guard let anchor = moveAnchor else {
            moveAnchor = p
            return
        }
        if let d = swipeDirection(p.x - anchor.x, p.y - anchor.y) {
            steer(d)
            moveAnchor = p
        }
        #endif
    }

    #if os(macOS)
    override func mouseMoved(with event: NSEvent) {
        inputController.handleMouseDelta(dx: event.deltaX, dy: event.deltaY)
    }

    var isGameOverForInput: Bool { isGameOver }

    func inputControllerDidRequest(_ direction: MoveDirection) {
        workerController.queueDirection(direction)
    }
    #endif

    // MARK: - WorkerControllerDelegate (shared collection logic)
    func workerDidEnterTile(_ grid: CGPoint) {
        if mazeBuilder.collectDot(at: grid) {
            state.collectedDots += 1
            state.bumpScore(by: 1)
            sound.playDotBlip()
            refreshHUD()
            checkLevelComplete()
        }
        if mazeBuilder.collectGold(at: grid) {
            state.bumpScore(by: 5)
            state.collectedGoldDiscs += 1
            sound.playGoldDisc()
            startGoldDiscMode()
            refreshHUD()
            checkLevelComplete()
        }
        if mazeBuilder.collectWaterPellet(at: grid) {
            state.collectedWaterPellets += 1
            state.bumpScore(by: 50)
            ScorePopup.show(50, at: gridMap.point(for: grid), in: self)
            if waterGunPickedUp {
                waterGun.reloadPellets(8)
                sound.playWaterGunPickup()
            }
            refreshHUD()
            checkLevelComplete()
        }
        if mazeBuilder.collectWaterGun(at: grid) {
            state.collectedWaterGuns += 1
            sound.playWaterGunPickup()
            state.bumpScore(by: 75)
            ScorePopup.show(75, at: gridMap.point(for: grid), in: self)
            startWaterGunMode()
            refreshHUD()
            checkLevelComplete()
        }
        if let machine = mazeBuilder.collectMachine(at: grid, shouldCollect: {
               requiredItems.contains($0) && !state.reportItems.contains($0)
           }) {
            handleMachine(name: machine.name, at: machine.position)
        }
        if mazeBuilder.touchedBrownBox(at: grid) != nil {
            collectTPSReport(at: grid)
        }
    }

    private func handleMachine(name: String, at position: CGPoint) {
        guard requiredItems.contains(name), !state.reportItems.contains(name) else { return }
        state.reportItems.insert(name)
        let itemIndex = state.reportItems.count - 1
        if itemIndex < reportItemPoints.count {
            let pts = reportItemPoints[itemIndex]
            state.bumpScore(by: pts)
            state.currentReportScore += pts
            ScorePopup.show(pts, at: position, in: self)
        }
        sound.playMachine(named: name)
        refreshHUD()
        if state.reportItems.count == requiredItems.count {
            hud.showMessage(Strings.Message.tpsReportReady, duration: 6)
        }
    }

    private func collectTPSReport(at grid: CGPoint) {
        guard state.reportItems.count == requiredItems.count else {
            let missing = requiredItems.filter { !state.reportItems.contains($0) }
            hud.showMessage(Strings.Message.tpsMissingItems(missing), duration: 5)
            sound.playTpsMissingItems(missing)
            return
        }
        mazeBuilder.collectBrownBox(at: grid)   // dim the box on turn-in, same fade + cooldown as a collected machine
        state.tpsReportsDelivered += 1
        state.reportItems.removeAll()
        let tpsPoints = state.level * 100 + 100
        state.bumpScore(by: tpsPoints)
        state.currentReportScore = 0
        if let workerPos = workerController?.node.position {
            ScorePopup.show(tpsPoints, at: workerPos, in: self)
        }
        sound.playTpsDeliver()
        let gainedLife = state.lives < HUD.maxLives
        if gainedLife { state.lives += 1 }
        refreshHUD()
        hud.showMessage(Strings.Message.tpsTurnedIn(points: tpsPoints, gainedLife: gainedLife), duration: 3)
        checkLevelComplete()
    }

    private func catchTraveler(_ node: SKNode?) {
        guard let caught = travelerSpawner.tryCatch(node) else { return }
        state.bumpScore(by: caught.traveler.points)
        sound.playFishOrTreat()
        refreshHUD()
        hud.showMessage(Strings.Message.travelerCaught(emoji: caught.traveler.emoji, points: caught.traveler.points), duration: 2)
        ScorePopup.show(caught.traveler.points, at: caught.position, in: self)
    }

    // MARK: - BossControllerDelegate
    func bossDidCatchWorker() { bossCaughtWorker() }

    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint) {
        state.bumpScore(by: points)
        sound.playCaptureBoss(streak: points / 100)
        ScorePopup.show(points, at: position, in: self)
        refreshHUD()
        hud.showMessage(Strings.Message.bossCaptured(name: name, points: points), duration: 2)
    }

    private func delayBossSpawn(after seconds: TimeInterval, _ action: @escaping () -> Void) {
        if seconds <= 0 && !sound.isSpeaking {
            action()
            return
        }
        deferredBossSpawn = action
        bossSpawnGrace = 0.4
        bossSpawnMax = max(seconds, 0) + 2.5
    }

    private func bossCaughtWorker() {
        let caughtSpeech = sound.playCaughtByBoss()
        state.lives -= 1
        if goldDisc.isActive { endGoldDiscMode() }

        if state.currentReportScore > 0 {
            let lost = state.currentReportScore
            if let workerPos = workerController?.node.position {
                ScorePopup.show(-lost, at: workerPos, in: self, color: .systemRed)
            }
        }
        state.reportItems.removeAll()
        state.currentReportScore = 0
        mazeBuilder.resetGrayedMachines()
        refreshHUD()
        workerController.resetMotion()
        workerController.teleport(to: mazeBuilder.workerSpawn ?? firstWalkableCell())
        workerController.applySpawnShield()
        if state.lives <= 0 {
            triggerGameOver()
        } else {
            delayBossSpawn(after: caughtSpeech) { [weak self] in self?.bossController.teleportAllToSpawn() }
            hud.showMessage(Strings.Message.bossCaughtYou(state.lives), duration: 3)
        }
    }

    // MARK: - Contacts (platform-specific)
    func didBegin(_ contact: SKPhysicsContact) {
        if isGameOver { return }
        let bodies = [contact.bodyA, contact.bodyB]

        if let dropletNode = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.waterDroplet })?.node,
           let bossNode = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.boss })?.node as? PixelPerson {
            let pos = bossNode.position
            let isFleeMode = isGoldDiscMode && bossController.isInFleeMode(boss: bossNode)
            let points = isFleeMode ? bossController.nextCapturePoints : waterHitPoints
            let color: NSColor = isFleeMode ? .white : .systemYellow
            bossController.splash(boss: bossNode)
            sound.playWaterGunSplash()
            state.bumpScore(by: points)
            spawnWaterSplash(at: pos)
            ScorePopup.show(points, at: pos, in: self, color: color)
            hud.showMessage(Strings.Message.bossSplashed, duration: 1.5)
            if let idx = waterDroplets.firstIndex(where: { $0 === dropletNode }) { waterDroplets.remove(at: idx) }
            refreshHUD()
            dropletNode.removeFromParent()
            return
        }

        if let dropletNode = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.waterDroplet })?.node,
           let fishNode = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.fish })?.node {
            let pos = fishNode.position
            if let caught = travelerSpawner.tryCatch(fishNode) {
                spawnWaterSplash(at: pos)
                sound.playWaterGunSplash()
                state.bumpScore(by: caught.traveler.points)
                ScorePopup.show(caught.traveler.points, at: pos, in: self,
                                color: SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1))
                refreshHUD()
            }
            if let idx = waterDroplets.firstIndex(where: { $0 === dropletNode }) { waterDroplets.remove(at: idx) }
            dropletNode.removeFromParent()
            return
        }

        guard bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.worker }) else { return }
        if let fishBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.fish }),
           fishBody.node != nil {
            catchTraveler(fishBody.node)
        }
        // Physics-contact backup to the per-frame proximity catch: a dynamic-sensor
        // boss overlapping Pete fires this. Both funnel into resolveBossContact.
        if let bossNode = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.boss })?.node as? PixelPerson {
            resolveBossContact(bossNode)
        }
    }

    private func resolveBossContact(_ bossNode: PixelPerson) {
        guard !bossController.isImmobilized(boss: bossNode) else { return }
        if bossController.isInFleeMode(boss: bossNode) {
            bossController.capture(boss: bossNode)
        } else if !workerController.isShielded {
            pendingCatch = bossNode
        }
    }

    // Proximity catch: same tile, or centres within bossCatchDistance (their
    // bodies overlap). Pure overlap, so it never fires a full tile away — Pete is
    // only safe from a boss while that boss is flashing in (immobilized during its
    // spawnGrace), which resolveBossContact guards on, the run-through was the
    // never-clearing shield, not the detection.
    private func checkBossCatch() {
        let petePos = workerController.node.position
        let peteGrid = workerController.grid
        for boss in bossController.entities {
            let bossGrid = boss.mover?.grid ?? dropletGrid(boss.node.position)
            if bossGrid == peteGrid || boss.node.position.distance(to: petePos) <= bossCatchDistance {
                resolveBossContact(boss.node)
            }
        }
    }

    // MARK: - Maze camera (200% mode)
    private func setupMazeCamera() {
        camPos = nil
        camVel = .zero
        let zoom = MazeZoom.zoomPercent        // 1982 -> 150%, 1983 -> 200% (the year is the era key)
        guard zoom > 100, zoom <= 200 else {   // 1980 classic / DOOM 3D get no 2D camera zoom
            camera = nil
            cameraNode = nil
            return
        }
        let scale = 100 / CGFloat(zoom)
        let cam = SKCameraNode()
        cam.xScale = scale
        cam.yScale = scale
        addChild(cam)
        camera = cam
        cameraNode = cam
    }

    // Host for all screen-fixed UI. Under the camera (200%) it is offset by
    // -half the scene so its scene-style child coords land at the same on-screen
    // spot as at 100%, with no camera it sits at the scene origin. A brand-new
    // node each call, since removeAllChildren cleared the previous one.
    private func setupUILayer() {
        uiLayer = SKNode()
        uiLayer.zPosition = 1000
        if let cam = cameraNode {
            uiLayer.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
            cam.addChild(uiLayer)
        } else {
            uiLayer.position = .zero
            addChild(uiLayer)
        }
    }

    // Follow Pete, clamped so the (zoomed) viewport never scrolls past the scene
    // edges — it stays inside the maze area of the 100% view, scrolling x/y with
    // the player.
    private func updateMazeCamera(dt: CGFloat) {
        guard let cam = cameraNode else { return }
        let p = workerController.node.position
        guard var c = camPos else {
            camPos = p
            camVel = .zero
            cam.position = p
            return
        }
        let snapThreshold = tileSize * 4
        if abs(p.x - c.x) > snapThreshold || abs(p.y - c.y) > snapThreshold {
            c = p
            camVel = .zero
        } else {
            let smoothTime: CGFloat = 0.22
            c.x = GameScene.smoothDamp(c.x, p.x, &camVel.x, smoothTime, dt)
            c.y = GameScene.smoothDamp(c.y, p.y, &camVel.y, smoothTime, dt)
        }
        camPos = c
        // No rounding here: the renderer snaps the world pass to whole device
        // pixels (gfx_snap_translation), so the camera follows smoothly and stays
        // sharp on its own.
        cam.position = c
    }

    // Critically damped follow (Unity-style SmoothDamp): eases in and out toward
    // the target without overshoot, for a smooth camera that accelerates and
    // settles instead of snapping.
    private static func smoothDamp(_ current: CGFloat, _ target: CGFloat,
                                   _ vel: inout CGFloat, _ smoothTime: CGFloat, _ dt: CGFloat) -> CGFloat {
        let omega = 2 / smoothTime
        let x = omega * dt
        let exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = current - target
        let temp = (vel + omega * change) * dt
        vel = (vel - omega * temp) * exp
        return target + (change + temp) * exp
    }

    // MARK: - Update loop
    override func update(_ currentTime: TimeInterval) {
        guard workerController != nil else { return }
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = min(currentTime - lastUpdateTime, 1.0 / 20.0)
        lastUpdateTime = currentTime
        if let caughtBy = pendingCatch {
            pendingCatch = nil
            #if os(macOS)
            caughtBy.alpha = 0
            caughtBy.removeAllActions()
            #endif
            bossController.relocateAfterCatch(boss: caughtBy)
            bossCaughtWorker()
        }
        if let action = deferredBossSpawn {
            bossSpawnGrace -= dt
            bossSpawnMax -= dt
            if (bossSpawnGrace <= 0 && !sound.isSpeaking) || bossSpawnMax <= 0 {
                deferredBossSpawn = nil
                action()
            }
        }
        if isGameOver { return }
        if isUserPaused { return }

        workerController.advance(dt)
        bossController.advance(dt)
        // Pete is shielded exactly while a boss is flashing in (spawnGrace), so the
        // grace ends for worker and boss at the same instant. No standalone timer.
        workerController.setShielded(bossController.isAnyBossSpawning)
        checkBossCatch()
        updateMazeCamera(dt: CGFloat(dt))
        stepWaterDroplets(dt: dt)

        if frightenSecondsLeft > 0 {
            frightenSecondsLeft -= dt
            if frightenSecondsLeft <= 0 { endGoldDiscMode() }
        }
    }

    private func stepWaterDroplets(dt: TimeInterval) {
        guard !waterDroplets.isEmpty else { return }
        var i = waterDroplets.count - 1
        while i >= 0 {
            let drop = waterDroplets[i]
            var consumed = drop.step(dt: dt)
            if !consumed, !gridMap.isWalkable(dropletGrid(drop.position)) { consumed = true }
            if consumed {
                drop.removeFromParent()
                waterDroplets.remove(at: i)
            }
            i -= 1
        }
    }

    // MARK: - Level / game flow
    func startNextLevel() {
        guard !isUserPaused else { return }
        isUserPaused = true
        let tune = sound.playLevelComplete(forLevel: state.level)
        let cover = makeLevelFadeCover()
        cover.alpha = 0
        uiLayer.addChild(cover)
        cover.run(.sequence([.wait(forDuration: tune + 1.0), .fadeIn(withDuration: 0.4), .run { [weak self] in
            guard let self else { return }
            self.state.advanceLevel()
            self.nextBossSpawnSeconds = self.sound.playLevelStart()
            self.resetSceneAndBuild()
            let cover2 = self.makeLevelFadeCover()
            cover2.alpha = 1
            self.uiLayer.addChild(cover2)
            cover2.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent(), .run { [weak self] in
                self?.isUserPaused = false
            }]))
            self.hud.showMessage(Strings.Message.levelLoaded(self.state.level), duration: 3)
        }]))
    }

    private func resetSceneAndBuild() {
        bossController.clear()
        travelerSpawner.reset()
        goldDisc.deactivate()
        waterGun.deactivate()
        waterDroplets.removeAll()
        waterGunPickedUp = false
        sound.stopGoldDiscBass()
        frightenSecondsLeft = 0
        removeAllActions()
        removeAllChildren()
        buildLevel()
    }

    private func returnToTitleScene() {
        guard let view else { return }
        hud.hideGameOver()
        sound.stopBackgroundMusic()
        if state.practiceMode {
            let editor = LevelEditorScene(size: size)
            editor.scaleMode = .aspectFit
            editor.currentLevelIndex = max(0, state.level - 1)
            view.presentScene(editor, transition: .fade(withDuration: 0.5))
            return
        }
        let title = TitleScene(size: size)
        title.scaleMode = .aspectFit
        view.presentScene(title, transition: .fade(withDuration: 0.5))
    }

    private func triggerGameOver() {
        isGameOver = true
        sound.stopGoldDiscBass()
        sound.stopBackgroundMusic()
        sound.playGameOver()
        workerController.resetMotion()
        bossController.stopAll()
        let allowEntry = !state.practiceMode
        var defaultName = LocalHighScores.savedUsername ?? ""

        #if os(macOS)
        inputController.unhideCursor()
        if !state.practiceMode {
            GameCenterClient.submitScore(state.score, to: LeaderboardPanel.leaderboardID)
        }
        if GKLocalPlayer.local.isAuthenticated {
            defaultName = LocalHighScores.savedUsername ?? GameCenterClient.currentPlayerName()
        }
        #endif

        guard let view else { return }
        let sz = size, sm = scaleMode, pm = state.practiceMode, lvl = state.level
        let goScene = GameOverScene(
            size: sz, score: state.score, highScore: state.highScore,
            allowEntry: allowEntry, defaultName: defaultName,
            isPractice: pm, practiceLevel: lvl,
            makeRestartScene: {
                let g = GameScene(size: sz)
                g.scaleMode = sm
                if pm { g.startingLevel = lvl }
                return g
            })
        view.presentScene(goScene, transition: .fade(withDuration: 0.5))
    }

    private func togglePause() {
        isUserPaused.toggle()
        if isUserPaused { sound.pauseAudio() } else { sound.resumeAudio() }
        speed = isUserPaused ? 0 : 1
        if isUserPaused {
            let dim = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            dim.fillColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.1)
            dim.strokeColor = .clear
            dim.zPosition = 40
            uiLayer.addChild(dim)
            pauseOverlay = dim
            hud.showPaused(true)
        } else {
            pauseOverlay?.removeFromParent()
            pauseOverlay = nil
            hud.showPaused(false)
        }
    }

    // MARK: - Gold disc
    private func startGoldDiscMode() {
        goldDisc.activate()
        bossController.setGoldDiscActive(true)
        sound.startGoldDiscBass()
        frightenSecondsLeft = goldDiscDuration
        hud.showMessage(Strings.Message.goldDiscActivated, duration: 3)
        refreshHUD()
    }

    private func endGoldDiscMode() {
        goldDisc.deactivate()
        bossController.setGoldDiscActive(false)
        sound.stopGoldDiscBass()
        frightenSecondsLeft = 0
        hud.showMessage(Strings.Message.goldDiscEnded, duration: 2)
        refreshHUD()
    }

    // MARK: - Water gun
    private func startWaterGunMode() {
        waterGunPickedUp = true
        waterGun.activate()
        hud.updateWaterGun(active: true, pellets: waterGun.pelletsRemaining)
        hud.showMessage(Strings.Message.waterGunActivated, duration: 3)
    }

    private func endWaterGunMode() {
        guard waterGun.isActive else { return }
        waterGun.deactivate()
        for drop in waterDroplets { drop.removeFromParent() }
        waterDroplets.removeAll()
        hud.updateWaterGun(active: false, pellets: 0)
        hud.showMessage(Strings.Message.waterGunEnded, duration: 2)
    }

    private func fireWaterGun() {
        guard waterGun.isActive else { return }
        guard let direction = workerController.direction ?? workerController.queuedDirection else { return }
        guard waterGun.consumePellet() else { return }
        let drop = WaterDroplet(direction: direction, speed: waterDropletSpeed)
        drop.position = workerController.node.position
        drop.zPosition = 6
        addChild(drop)
        waterDroplets.append(drop)
        sound.playWaterGunShoot()
        refreshHUD()
        if waterGun.pelletsRemaining == 0 { endWaterGunMode() }
    }

    private func spawnWaterSplash(at center: CGPoint) {
        let splash = SpriteFactory.waterSplash()
        splash.position = center
        splash.zPosition = 15
        addChild(splash)
    }

    // MARK: - Fire button
    private func installFireButton() {
        fireButtonHidden = !ControlMode.current.showsControl
        if fireButtonHidden { return }
        let onLeft = !ControlMode.current.onLeft   // fire button opposite the movement widget
        fireButtonCenter = CGPoint(x: onLeft ? fireButtonRadius : size.width - fireButtonRadius, y: fireButtonRadius + 15)
        uiLayer.addChild(SpriteFactory.controlRing(radius: fireButtonRadius, center: fireButtonCenter, zPosition: 50))
    }

    // MARK: - Joystick
    private func installJoystick() {
        if !ControlMode.current.showsControl { return }
        let onLeft = ControlMode.current.onLeft   // movement widget side
        joystickCenter = CGPoint(x: onLeft ? joystickRadius : size.width - joystickRadius, y: joystickRadius + 15)

        let base = SKShapeNode(circleOfRadius: joystickRadius)
        base.position = joystickCenter
        base.fillColor = SKColor(white: 1, alpha: 0.06)
        base.strokeColor = SKColor(white: 1, alpha: 0.5)
        base.lineWidth = 2
        base.zPosition = 50
        uiLayer.addChild(base)

        if ControlMode.current.showsDpad { // DPAD: the shared 4-wedge cross (same look + hit-area as the 3D bonus), STICK: the follow-thumb below
            dpadWedges = buildDpadFace(in: uiLayer, center: joystickCenter, inner: joystickDeadzone, outer: joystickRadius, z: 51)
            return
        }

        let thumb = SKShapeNode(circleOfRadius: joystickKnobRadius)
        thumb.position = joystickCenter
        thumb.fillColor = SKColor(white: 1, alpha: 0.28)
        thumb.strokeColor = SKColor(white: 1, alpha: 0.6)
        thumb.lineWidth = 2
        thumb.zPosition = 51
        uiLayer.addChild(thumb)
        joystickThumb = thumb
    }

    // Drive the shared D-pad from a pointer in uiLayer space: move the thumb (stick mode), light the
    // pressed wedge, and steer. One cardinal per pointer, in stick mode the wedge dict is empty so the
    // highlight is a no-op.
    private func applyJoystick(at p: CGPoint) {
        moveJoystickThumb(to: p)
        let c = dpadCardinal(p, center: joystickCenter, deadzone: joystickDeadzone, radius: joystickRadius)
        lightDpadFace(dpadWedges, up: c == "up", down: c == "down", left: c == "left", right: c == "right")
        switch c {
        case "up":    steer(.up)
        case "down":  steer(.down)
        case "left":  steer(.left)
        case "right": steer(.right)
        default:      break
        }
    }

    private func moveJoystickThumb(to p: CGPoint) {
        let dx = p.x - joystickCenter.x
        let dy = p.y - joystickCenter.y
        let mag = (dx * dx + dy * dy).squareRoot()
        let limit = joystickRadius - joystickKnobRadius
        if mag > limit, mag > 0 {
            let s = limit / mag
            joystickThumb?.position = CGPoint(x: joystickCenter.x + dx * s, y: joystickCenter.y + dy * s)
        } else {
            joystickThumb?.position = p
        }
    }

    private func recenterJoystickThumb() {
        joystickThumb?.position = joystickCenter
    }

    // MARK: - Boss water-droplet dodge (BossControllerDelegate)
    func dropletAxisThreatening(_ bossGrid: CGPoint) -> MoveDirection? {
        for line in activeDropletLines() where dropletThreatens(dropletGrid: line.grid, dir: line.dir, boss: bossGrid, range: dropletDodgeRange, isWalkable: { gridMap.isWalkable($0) }) {
            return line.dir
        }
        return nil
    }


    private func dropletGrid(_ p: CGPoint) -> CGPoint {
        CGPoint(x: CGFloat(Int((p.x - gridMap.xOffset) / tileSize)),
                y: CGFloat(Int((p.y - gridMap.yOffset) / tileSize)))
    }

    private func activeDropletLines() -> [(grid: CGPoint, dir: MoveDirection)] {
        waterDroplets.map { d in
            let v = d.velocity
            let dir: MoveDirection = abs(v.dx) > abs(v.dy) ? (v.dx > 0 ? .right : .left) : (v.dy > 0 ? .up : .down)
            return (self.dropletGrid(d.position), dir)
        }
    }

    // MARK: - HUD
    private func refreshHUD() {
        hud.updateStatus(
            score: state.score, highScore: state.highScore, level: state.level,
            dots: state.collectedDots, total: state.dotCount,
            reports: state.tpsReportsDelivered, items: state.reportItems
        )
        hud.updateLives(state.lives)
        hud.updateWaterGun(active: waterGun.isActive, pellets: waterGunPickedUp ? waterGun.pelletsRemaining : -1, blueMode: goldDisc.isActive)
        let cyclePosition = ((state.level - 1) % levelTravelers.count) + 1
        hud.updateLevelEmojis(Array(levelTravelers.prefix(cyclePosition)))
    }
}

extension GameScene: SKPhysicsContactDelegate {}

#if os(macOS)
extension GameScene: PointerInputControllerDelegate {}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
#endif


