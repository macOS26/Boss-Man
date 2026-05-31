import AppKit
#if os(macOS)
import GameKit
#endif
import SpriteKit

// Gameplay scene, common to the macOS master and the wasm port. The pure game
// logic (collection, scoring via RoundState, TPS reports, gold-disc, boss
// catch, level flow) is shared; the platform I/O is forked behind #if:
//   - macOS: NSEvent input + PointerInputController, ContactRouter, GameKit,
//     SKAction-driven movement, gold-disc expiry via a scene SKAction.
//   - wasm: kit CGPoint/Int input overrides, didBegin contacts, TileMover
//     movement driven from update(), gold-disc expiry via a frame countdown,
//     maze centred through gridMap x/yOffset.
final class GameScene: SKScene, WorkerControllerDelegate, BossControllerDelegate {
    private let tileSize: CGFloat = 32
    private let goldDiscDuration: TimeInterval = 20
    private let requiredItems = Strings.Machine.required
    private let reportItemPoints = [10, 25, 50, 100]
    private let dropletDodgeRange = 8

    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var mazeBuilder: MazeBuilder!
    private var hud: HUD!
    private let sound = SoundManager()

    private let state = RoundState()
    private let goldDisc = GoldDiscTimer()
    private let waterGun = WaterGunState()
    private var waterGunPickedUp = false
    private var travelerSpawner: TravelerSpawner!
    private var workerController: WorkerController!
    private var bossController: BossController!
    private var gameOverScreen: GameOverScreen?

    private(set) var isGameOver = false
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

    #if os(macOS)
    private let workerSpawn = CGPoint(x: 18, y: 7)
    private let inputController = PointerInputController()
    private let contactRouter = ContactRouter()
    #elseif os(WASI)
    private let mazeRoot = SKNode()
    private var containerOriginX: CGFloat = 0
    private var swipeStart: CGPoint? = nil
    private var swipeFired = false
    private var moveAnchor: CGPoint? = nil
    private let swipeThreshold: CGFloat = 24
    private var fireButtonCenter = CGPoint.zero
    private var fireButtonHidden = false
    private let fireButtonRadius: CGFloat = 90
    private var contactCooldown: TimeInterval = 0
    private var frightenSecondsLeft: TimeInterval = 0
    private var waterDroplets: [WaterDroplet] = []
    private let waterDropletSpeed: CGFloat = 12 * 32
    private let waterHitPoints = 50
    private var isUserPaused = false
    private var pauseOverlay: SKNode? = nil
    #endif

    // MARK: - Lifecycle
    #if os(macOS)
    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60   // uncapped play, even when launched from the 30fps editor
        backgroundColor = SpriteFactory.mazeBackground
        anchorPoint = CGPoint(x: 0, y: 0)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = contactRouter

        gridMap = GridMap(tileSize: tileSize, rows: currentLevelRows())
        gridMap.yOffset = 0
        pathfinder = Pathfinder(map: gridMap)
        mazeBuilder = MazeBuilder(map: gridMap)
        hud = HUD(requiredItems: requiredItems)
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound)
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder, sound: sound)
        bossController.delegate = self
        wireContactRouter()
        buildLevel()
        hud.showMessage(state.practiceMode ? Strings.Message.practiceMode : Strings.Message.intro, duration: 3)
        inputController.delegate = self
        inputController.start()
        view.window?.acceptsMouseMovedEvents = true
        inputController.hideCursor()
        installFireButton()
    }

    override func willMove(from view: SKView) {
        inputController.unhideCursor()
    }
    #elseif os(WASI)
    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60   // uncapped play, even when launched from the low-fps editor
        backgroundColor = SpriteFactory.mazeBackground
        anchorPoint = .zero
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        let rows = LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1)))
        gridMap = GridMap(tileSize: tileSize, rows: rows)
        pathfinder = Pathfinder(map: gridMap)

        let mazeHeight = CGFloat(gridMap.rowCount) * tileSize
        let mazeWidth  = CGFloat(gridMap.columnCount) * tileSize
        // Reserve the top HUD panel and centre the maze in what's left so labels
        // never sit on top of cubicle tiles. gridMap.point(for:) then returns
        // final centred coords for tiles, Pete and bosses alike.
        let availableHeight = size.height - HUD.panelHeight
        gridMap.yOffset = max(20, (availableHeight - mazeHeight) / 2)
        gridMap.xOffset = max(0, (size.width - mazeWidth) / 2)
        containerOriginX = gridMap.xOffset

        mazeRoot.position = .zero
        addChild(mazeRoot)

        mazeBuilder = MazeBuilder(map: gridMap)
        hud = HUD(requiredItems: requiredItems)
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound,
                                          containerOriginX: containerOriginX)
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder,
                                        sound: sound, containerOriginX: containerOriginX)
        bossController.delegate = self
        buildLevel()
        installFireButton()
        if state.practiceMode { hud.showMessage(Strings.Message.practiceMode, duration: 3) }
    }

    override func willMove(from view: SKView) {
        sound.stopAllAudio()
        mazeBuilder.releaseTextures()
    }
    #endif

    private func buildLevel() {
        sound.startBackgroundMusic(theme: musicTheme(for: state.level))
        mazeBuilder.cubicleColor = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        #if os(macOS)
        gridMap.setRows(currentLevelRows())
        state.dotCount = mazeBuilder.build(in: self, view: self.view)
        #elseif os(WASI)
        state.dotCount = mazeBuilder.build(in: mazeRoot, view: view)
        #endif
        state.goldDiscCount = mazeBuilder.goldDiscPositions.count
        hud.install(in: self)
        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        #if os(macOS)
        workerController = WorkerController(spawnGrid: spawn, gridMap: gridMap, sound: sound)
        #elseif os(WASI)
        workerController = WorkerController(spawnGrid: spawn, gridMap: gridMap, sound: sound,
                                            containerOriginX: containerOriginX)
        #endif
        workerController.delegate = self
        addChild(workerController.node)
        workerController.applySpawnShield()
        bossController.spawn(forLevel: state.level,
                             spawnOverrides: mazeBuilder.bossSpawns.map { (blueprintIndex: $0.index, position: $0.position) })
        refreshHUD()
        #if os(macOS)
        let scheduledLevel = state.level
        travelerSpawner.scheduleVisits(of: currentTraveler()) { [weak self] in
            guard let self else { return false }
            return self.state.level == scheduledLevel && !self.isGameOver
        }
        #elseif os(WASI)
        scheduleTravelerForCurrentLevel()
        #endif
    }

    private func currentLevelRows() -> [String] {
        #if os(macOS)
        let idx = (state.level - 1) % Levels.levelNames.count
        let name = Levels.levelNames[idx]
        if let custom = LevelStore.shared.loadLevel(name: name) {
            return custom
        }
        return Levels.officeMaps[idx % Levels.officeMaps.count]
        #elseif os(WASI)
        return LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1)))
        #endif
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

    // MARK: - Input (platform-specific)
    #if os(macOS)
    private func usernameKeyCode(for event: NSEvent) -> Int {
        switch event.keyCode {
        case 36, 76: return 58
        case 53:     return 36
        case 51:     return 59
        case 49:     return 57
        default:
            guard let u = (event.charactersIgnoringModifiers ?? "").uppercased().unicodeScalars.first else { return -1 }
            if u.value >= 65, u.value <= 90 { return Int(u.value) - 65 }
            if u.value >= 48, u.value <= 57 { return 26 + Int(u.value) - 48 }
            return -1
        }
    }

    override func keyDown(with event: NSEvent) {
        if let s = gameOverScreen {
            s.handleKey(usernameKeyCode(for: event), shift: event.modifierFlags.contains(.shift))
            return
        }
        if isGameOver {
            switch event.keyCode {
            case 35: restartGame()
            case 53: returnToTitleScene()
            default: break
            }
            return
        }
        switch event.keyCode {
        case 35: togglePause(); return
        case 53: returnToTitleScene(); return
        default: break
        }
        guard !isPaused else { return }
        if event.keyCode == 49 { fireWaterGun(); return }
        guard let direction = MoveDirection(keyCode: event.keyCode), !event.isARepeat else { return }
        workerController.queueDirection(direction)
    }

    override func mouseDown(with event: NSEvent) {
        if let s = gameOverScreen {
            s.handleTap(at: event.location(in: self))
            return
        }
        guard !isPaused, !isGameOver else { return }
        fireWaterGun()
    }

    override func mouseMoved(with event: NSEvent) {
        inputController.handleMouseDelta(dx: event.deltaX, dy: event.deltaY)
    }

    override func mouseDragged(with event: NSEvent) {
        inputController.handleMouseDelta(dx: event.deltaX, dy: event.deltaY)
    }

    var isGameOverForInput: Bool { isGameOver }

    func inputControllerDidRequest(_ direction: MoveDirection) {
        workerController.queueDirection(direction)
    }
    #elseif os(WASI)
    private func swipeDirection(_ dx: CGFloat, _ dy: CGFloat) -> MoveDirection? {
        guard max(abs(dx), abs(dy)) >= swipeThreshold else { return nil }
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .up : .down
    }

    private func steer(_ dir: MoveDirection) {
        workerController.queueDirection(dir)
        workerController.node.setFacing(dir)
    }

    override func mouseDown(at p: CGPoint) {
        if let s = gameOverScreen {
            s.handleTap(at: p)
            return
        }
        if isGameOver || isUserPaused { return }
        moveAnchor = p
        if !fireButtonHidden, fireButtonCenter.distance(to: p) <= fireButtonRadius {
            fireWaterGun()
            swipeStart = nil
            return
        }
        swipeStart = p
        swipeFired = false
    }

    override func mouseMoved(to p: CGPoint) {
        if isGameOver || isUserPaused { moveAnchor = p; return }
        if let start = swipeStart {
            if !swipeFired, let d = swipeDirection(p.x - start.x, p.y - start.y) {
                steer(d); swipeFired = true
            }
            return
        }
        guard let anchor = moveAnchor else { moveAnchor = p; return }
        if let d = swipeDirection(p.x - anchor.x, p.y - anchor.y) {
            steer(d); moveAnchor = p
        }
    }

    override func mouseUp(at p: CGPoint) {
        if let start = swipeStart, !swipeFired, !isGameOver, !isUserPaused,
           let d = swipeDirection(p.x - start.x, p.y - start.y) {
            steer(d)
        }
        swipeStart = nil
        moveAnchor = p
    }

    override func keyDown(_ key: Int) {
        if let s = gameOverScreen {
            s.handleKey(key, shift: false)
            return
        }
        if isGameOver {
            if key == 15 { restartGame() }
            else if key == 36 { returnToTitleScene() }
            return
        }
        if key == 36 { returnToTitleScene(); return }
        if key == 15 { togglePause(); return }
        if isUserPaused { return }
        if key == 57 { fireWaterGun(); return }
        if let dir = MoveDirection(keyCode: key) {
            workerController.queueDirection(dir)
            workerController.node.setFacing(dir)
        }
    }

    private func scheduleTravelerForCurrentLevel() {
        travelerSpawner.scheduleVisits(of: currentTraveler(),
                                       whileActive: { [weak self] in
                                           guard let self else { return false }
                                           return !self.isGameOver && !self.isUserPaused
                                       })
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
            state.bumpScore(by: 50)
            ScorePopup.show(50, at: gridMap.point(for: grid), in: self)
            if waterGunPickedUp {
                waterGun.reloadPellets(8)
                sound.playWaterGunPickup()
            }
            refreshHUD()
        }
        if mazeBuilder.collectWaterGun(at: grid) {
            sound.playWaterGunPickup()
            state.bumpScore(by: 75)
            ScorePopup.show(75, at: gridMap.point(for: grid), in: self)
            startWaterGunMode()
            refreshHUD()
        }
        if let machine = mazeBuilder.collectMachine(at: grid, shouldCollect: {
               requiredItems.contains($0) && !state.reportItems.contains($0)
           }) {
            handleMachine(name: machine.name, at: machine.position)
        }
        if mazeBuilder.touchedBrownBox(at: grid) != nil {
            collectTPSReport()
        }
    }

    private func checkLevelComplete() {
        let dotsDone = state.collectedDots >= state.dotCount
        let discsDone = state.collectedGoldDiscs >= state.goldDiscCount
        guard dotsDone && discsDone else { return }
        if state.tpsReportsDelivered >= 1 {
            startNextLevel()
        } else {
            hud.showMessage(Strings.Message.needTPSReport, duration: 3)
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
        } else {
            hud.showMessage(Strings.Message.reportItemCollected(name: name, points: reportItemPoints[itemIndex]), duration: 2)
        }
    }

    private func collectTPSReport() {
        guard state.reportItems.count == requiredItems.count else {
            let missing = requiredItems.filter { !state.reportItems.contains($0) }
            hud.showMessage(Strings.Message.tpsMissingItems(missing), duration: 5)
            sound.playTpsMissingItems(missing)
            return
        }
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

    private func bossCaughtWorker() {
        sound.playCaughtByBoss()
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
        bossController.teleportAllToSpawn()
        if state.lives <= 0 {
            triggerGameOver()
        } else {
            hud.showMessage(Strings.Message.bossCaughtYou(state.lives), duration: 3)
        }
    }

    // MARK: - Contacts (platform-specific)
    #if os(macOS)
    private func wireContactRouter() {
        contactRouter.shouldIgnoreContact = { [weak self] in self?.isGameOver ?? true }
        contactRouter.onBossTouchedWorker = { [weak self] node in
            guard let self else { return }
            guard let bossNode = node as? PixelPerson else { return }
            if self.bossController.isImmobilized(boss: bossNode) { return }
            if self.bossController.isInFleeMode(boss: bossNode) {
                self.bossController.capture(boss: bossNode)
            } else if !self.workerController.isShielded {
                bossNode.alpha = 0
                bossNode.removeAllActions()
                self.bossController.relocateAfterCatch(boss: bossNode)
                self.bossCaughtWorker()
            }
        }
        contactRouter.onFishTouchedWorker = { [weak self] node in self?.catchTraveler(node) }
        contactRouter.onDropletTouchedBoss = { [weak self] dropletBody, bossBody in
            dropletBody.node?.removeFromParent()
            guard let self else { return }
            if let bossNode = bossBody.node as? PixelPerson {
                let pos = bossNode.position
                self.bossController.splash(boss: bossNode)
                self.sound.playWaterGunSplash()
                self.state.bumpScore(by: 50)
                ScorePopup.show(50, at: pos, in: self)
                self.spawnWaterSplash(at: pos)
                self.hud.showMessage(Strings.Message.bossSplashed, duration: 1.5)
                self.refreshHUD()
            }
        }
    }
    #elseif os(WASI)
    func didBegin(_ contact: SKPhysicsContact) {
        if isGameOver { return }
        let bodies = [contact.bodyA, contact.bodyB]
        let hasWorker = bodies.contains { $0.categoryBitMask == PhysicsCategory.worker }
        if hasWorker, let fishBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.fish }),
           fishBody.node != nil {
            catchTraveler(fishBody.node)
        }
    }
    #endif

    // MARK: - Update loop (wasm: drives movement; macOS: SKAction-driven)
    #if os(WASI)
    override func update(_ currentTime: TimeInterval) {
        guard workerController != nil else { return }
        if isGameOver || isUserPaused { return }
        let dt: TimeInterval = 1.0 / 60.0

        workerController.advance(dt)
        bossController.advance(dt)
        stepWaterDroplets(dt: dt)

        if frightenSecondsLeft > 0 {
            frightenSecondsLeft -= dt
            if frightenSecondsLeft <= 0 { endGoldDiscMode() }
        }
        if contactCooldown > 0 {
            contactCooldown -= dt
        } else if let bossNode = bossOnPete() {
            if bossController.isInFleeMode(boss: bossNode) {
                bossController.capture(boss: bossNode)
                contactCooldown = 0.4
            } else if !workerController.isShielded {
                bossController.relocateAfterCatch(boss: bossNode)
                bossCaughtWorker()
                contactCooldown = 1.2
            }
        }
    }

    private func bossOnPete() -> PixelPerson? {
        let r = tileSize * 0.55
        let r2 = r * r
        for e in bossController.entities {
            if e.isImmobilized { continue }
            let dx = e.node.position.x - workerController.node.position.x
            let dy = e.node.position.y - workerController.node.position.y
            if dx * dx + dy * dy < r2 { return e.node }
        }
        return nil
    }

    private func gridCellAtScenePoint(_ p: CGPoint) -> CGPoint {
        let localX = p.x - containerOriginX
        let col = Int(localX / tileSize)
        let row = Int((p.y - gridMap.yOffset) / tileSize)
        return CGPoint(x: col, y: row)
    }

    private func stepWaterDroplets(dt: TimeInterval) {
        guard !waterDroplets.isEmpty else { return }
        var i = waterDroplets.count - 1
        while i >= 0 {
            let drop = waterDroplets[i]
            var consumed = drop.step(dt: dt)
            if !consumed {
                let g = gridCellAtScenePoint(drop.position)
                if !gridMap.isWalkable(g) { consumed = true }
                else {
                    for e in bossController.entities {
                        let dx = e.node.position.x - drop.position.x
                        let dy = e.node.position.y - drop.position.y
                        if dx * dx + dy * dy < (tileSize * 0.45) * (tileSize * 0.45) {
                            state.bumpScore(by: waterHitPoints)
                            ScorePopup.show(waterHitPoints, at: e.node.position, in: self,
                                            color: SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1))
                            spawnWaterSplash(at: e.node.position)
                            sound.playWaterGunSplash()
                            bossController.splash(boss: e.node)
                            refreshHUD()
                            consumed = true
                            break
                        }
                    }
                }
            }
            if consumed {
                drop.removeFromParent()
                waterDroplets.remove(at: i)
            }
            i -= 1
        }
    }
    #endif

    // MARK: - Level / game flow
    private func startNextLevel() {
        state.advanceLevel()
        #if os(macOS)
        resetSceneAndBuild()
        sound.playLevelStart()
        #elseif os(WASI)
        // wasm reuses the worker / HUD / fire button across levels — only the
        // maze, bosses and traveler are swapped (apple rebuilds the whole scene).
        sound.startBackgroundMusic(theme: musicTheme(for: state.level))
        sound.playLevelStart()
        bossController.clear()
        mazeRoot.removeAllChildren()
        travelerSpawner.reset()
        gridMap.setRows(currentLevelRows())
        mazeBuilder.cubicleColor = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        state.dotCount = mazeBuilder.build(in: mazeRoot, view: view)
        state.goldDiscCount = mazeBuilder.goldDiscPositions.count
        scheduleTravelerForCurrentLevel()
        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        workerController.resetMotion()
        workerController.teleport(to: spawn)
        bossController.spawn(forLevel: state.level,
                             spawnOverrides: mazeBuilder.bossSpawns.map { (blueprintIndex: $0.index, position: $0.position) })
        refreshHUD()
        #endif
        hud.showMessage(Strings.Message.levelLoaded(state.level), duration: 3)
    }

    #if os(macOS)
    private func resetSceneAndBuild() {
        bossController.clear()
        travelerSpawner.reset()
        goldDisc.deactivate()
        waterGun.deactivate()
        waterGunPickedUp = false
        sound.stopGoldDiscBass()
        removeAction(forKey: Strings.ActionKey.goldDiscExpiry)
        removeAllActions()
        removeAllChildren()
        buildLevel()
    }
    #endif

    private func restartGame() {
        #if os(macOS)
        hud.hideGameOver()
        inputController.hideCursor()
        isGameOver = false
        state.resetForNewGame()
        resetSceneAndBuild()
        hud.showMessage(Strings.Message.newGame, duration: 3)
        #elseif os(WASI)
        sound.stopAllAudio()
        let game = GameScene(size: size)
        game.scaleMode = .aspectFit
        view?.presentScene(game, transition: .fade(withDuration: 0.4))
        #endif
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
        #if os(macOS)
        inputController.unhideCursor()
        if !state.practiceMode {
            GameCenterClient.submitScore(state.score, to: LeaderboardPanel.leaderboardID)
        }
        let defaultName = GKLocalPlayer.local.isAuthenticated
            ? (LocalHighScores.savedUsername ?? GameCenterClient.currentPlayerName())
            : (LocalHighScores.savedUsername ?? "")
        #elseif os(WASI)
        let defaultName = LocalHighScores.savedUsername ?? ""
        #endif
        presentGameOverScreen(defaultName: defaultName)
    }

    private func presentGameOverScreen(defaultName: String) {
        let screen = GameOverScreen(
            size: size,
            font: Strings.Font.menloBold,
            score: state.score,
            highScore: state.highScore,
            defaultName: defaultName,
            allowEntry: !state.practiceMode,
            onPlay: { [weak self] in self?.dismissGameOverScreen(); self?.restartGame() },
            onEsc:  { [weak self] in self?.dismissGameOverScreen(); self?.returnToTitleScene() }
        )
        screen.position = .zero
        addChild(screen)
        gameOverScreen = screen
    }

    private func dismissGameOverScreen() {
        gameOverScreen?.removeFromParent()
        gameOverScreen = nil
    }

    private func togglePause() {
        #if os(macOS)
        if isPaused {
            isPaused = false
            sound.resumeAudio()
            inputController.hideCursor()
            hud.showMessage(Strings.HUD.empty, duration: 0.1)
        } else {
            hud.showMessage(Strings.Message.paused, duration: 9999)
            inputController.unhideCursor()
            isPaused = true
            sound.pauseAudio()
        }
        #elseif os(WASI)
        isUserPaused.toggle()
        if isUserPaused { sound.pauseAudio() } else { sound.resumeAudio() }
        speed = isUserPaused ? 0 : 1
        if isUserPaused {
            let dim = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            dim.fillColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.45)
            dim.strokeColor = .clear
            dim.zPosition = 40
            let label = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
            label.text = "PAUSED"
            label.fontSize = 72
            label.fontColor = .white
            label.position = CGPoint(x: size.width / 2, y: size.height * 0.5)
            label.zPosition = 41
            dim.addChild(label)
            addChild(dim)
            pauseOverlay = dim
        } else {
            pauseOverlay?.removeFromParent()
            pauseOverlay = nil
        }
        #endif
    }

    // MARK: - Gold disc
    private func startGoldDiscMode() {
        goldDisc.activate()
        bossController.setGoldDiscActive(true)
        sound.startGoldDiscBass()
        #if os(macOS)
        run(.sequence([
            .wait(forDuration: goldDiscDuration),
            .run { [weak self] in self?.endGoldDiscMode() }
        ]), withKey: Strings.ActionKey.goldDiscExpiry)
        #elseif os(WASI)
        frightenSecondsLeft = goldDiscDuration
        #endif
        hud.showMessage(Strings.Message.goldDiscActivated, duration: 3)
        refreshHUD()
    }

    private func endGoldDiscMode() {
        goldDisc.deactivate()
        bossController.setGoldDiscActive(false)
        sound.stopGoldDiscBass()
        removeAction(forKey: Strings.ActionKey.goldDiscExpiry)
        #if os(WASI)
        frightenSecondsLeft = 0
        #endif
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
        for child in children where child.name == "waterDroplet" {
            child.removeFromParent()
        }
        hud.updateWaterGun(active: false, pellets: 0)
        hud.showMessage(Strings.Message.waterGunEnded, duration: 2)
    }

    private func fireWaterGun() {
        guard waterGun.isActive else { return }
        if goldDisc.isActive {
            hud.showMessage(Strings.Message.waterGunBlueMode, duration: 2)
            return
        }
        #if os(macOS)
        guard let direction = workerController.direction else { return }
        guard waterGun.consumePellet() else { return }
        let droplet = WaterDroplet.fire(from: workerController.node.position, direction: direction, tileSize: tileSize)
        addChild(droplet)
        sound.playWaterGunShoot()
        hud.updateWaterGun(active: waterGun.isActive, pellets: waterGunPickedUp ? waterGun.pelletsRemaining : -1)
        if waterGun.pelletsRemaining == 0 { endWaterGunMode() }
        #elseif os(WASI)
        guard let h = workerController.direction ?? workerController.queuedDirection else { return }
        guard waterGun.consumePellet() else { return }
        let drop = WaterDroplet(direction: h, speed: waterDropletSpeed)
        drop.position = workerController.node.position
        drop.zPosition = 6
        addChild(drop)
        waterDroplets.append(drop)
        sound.playWaterGunShoot()
        refreshHUD()
        #endif
    }

    private func spawnWaterSplash(at center: CGPoint) {
        #if os(macOS)
        let count = 10
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2
            let radius = CGFloat.random(in: 22...48)
            let drop = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...6))
            drop.fillColor = Bool.random() ? .systemCyan : .systemBlue
            drop.strokeColor = .clear
            drop.position = center
            drop.zPosition = 15
            drop.alpha = 0.85
            addChild(drop)
            let dx = cos(angle) * radius
            let dy = sin(angle) * radius
            drop.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: 0.35),
                    .sequence([
                        .scale(to: 1.4, duration: 0.1),
                        .group([.scale(to: 0.1, duration: 0.25), .fadeOut(withDuration: 0.25)])
                    ])
                ]),
                .removeFromParent()
            ]))
        }
        #elseif os(WASI)
        let burst = SKNode()
        burst.position = center
        burst.zPosition = 8
        addChild(burst)
        let dist: CGFloat = tileSize * 0.45
        // Hand-rolled unit vectors (60 deg apart) to avoid linking libm on wasm.
        let unit: [(CGFloat, CGFloat)] = [
            ( 1.0,  0.0), ( 0.5,  0.866025), (-0.5,  0.866025),
            (-1.0,  0.0), (-0.5, -0.866025), ( 0.5, -0.866025),
        ]
        for (ux, uy) in unit {
            let dot = SKShapeNode(circleOfRadius: 3.5)
            dot.fillColor = SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 0.9)
            dot.strokeColor = .clear
            burst.addChild(dot)
            dot.run(.group([
                .move(by: CGVector(dx: ux * dist, dy: uy * dist), duration: 0.35),
                .fadeOut(withDuration: 0.4),
            ]))
        }
        burst.run(.sequence([.wait(forDuration: 0.45), .removeFromParent()]))
        #endif
    }

    // MARK: - Fire button
    private func installFireButton() {
        #if os(macOS)
        if UserDefaults.standard.bool(forKey: Strings.DefaultsKey.waterGunHide) { return }
        let onLeft = UserDefaults.standard.bool(forKey: Strings.DefaultsKey.waterGunLeft)
        let center = CGPoint(x: onLeft ? 90 : size.width - 90, y: 90)
        let ring = SKShapeNode(circleOfRadius: 90)
        ring.position = center
        ring.fillColor = NSColor(white: 1, alpha: 0.14)
        ring.strokeColor = NSColor(white: 1, alpha: 0.5)
        ring.lineWidth = 2
        ring.zPosition = 50
        addChild(ring)
        #elseif os(WASI)
        fireButtonHidden = Persistence.bool(forKey: Strings.DefaultsKey.waterGunHide)
        if fireButtonHidden { return }
        let onLeft = Persistence.bool(forKey: Strings.DefaultsKey.waterGunLeft)
        fireButtonCenter = CGPoint(x: onLeft ? fireButtonRadius : size.width - fireButtonRadius, y: fireButtonRadius)
        let ring = SKShapeNode(circleOfRadius: fireButtonRadius)
        ring.position = fireButtonCenter
        ring.fillColor = SKColor(white: 1, alpha: 0.14)
        ring.strokeColor = SKColor(white: 1, alpha: 0.5)
        ring.lineWidth = 2
        ring.zPosition = 50
        addChild(ring)
        #endif
    }

    // MARK: - Boss water-droplet dodge (BossControllerDelegate)
    func dropletAxisThreatening(_ bossGrid: CGPoint) -> MoveDirection? {
        for line in activeDropletLines() where dropletThreatens(dropletGrid: line.grid, dir: line.dir, boss: bossGrid) {
            return line.dir
        }
        return nil
    }

    // A boss is threatened when it shares the droplet's row/col, sits ahead of it
    // along its travel axis within dropletDodgeRange tiles, and every tile between
    // is walkable (a wall would stop the shot first).
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

    private func dropletGrid(_ p: CGPoint) -> CGPoint {
        CGPoint(x: CGFloat(Int((p.x - gridMap.xOffset) / tileSize)),
                y: CGFloat(Int((p.y - gridMap.yOffset) / tileSize)))
    }

    private func activeDropletLines() -> [(grid: CGPoint, dir: MoveDirection)] {
        #if os(macOS)
        return children.compactMap { node in
            guard node.name == "waterDroplet",
                  let dx = node.userData?["wdx"] as? Int,
                  let dy = node.userData?["wdy"] as? Int else { return nil }
            let dir: MoveDirection = dx > 0 ? .right : dx < 0 ? .left : dy > 0 ? .up : .down
            return (self.dropletGrid(node.position), dir)
        }
        #elseif os(WASI)
        return waterDroplets.map { d in
            let v = d.velocity
            let dir: MoveDirection = abs(v.dx) > abs(v.dy) ? (v.dx > 0 ? .right : .left) : (v.dy > 0 ? .up : .down)
            return (self.dropletGrid(d.position), dir)
        }
        #endif
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

#if os(macOS)
extension GameScene: PointerInputControllerDelegate {}
#elseif os(WASI)
extension GameScene: SKPhysicsContactDelegate {}
#endif
