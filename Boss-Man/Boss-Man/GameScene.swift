import AppKit
import SpriteKit

final class GameScene: SKScene, PointerInputControllerDelegate, WorkerControllerDelegate, BossControllerDelegate {
    private let tileSize: CGFloat = 32
    private let workerSpawn = CGPoint(x: 18, y: 7)
    private let powerPelletDuration: TimeInterval = 20

    private let requiredItems = ["Printer", "Fax", "Copy", "Collator"]
    private let machineNames: [Character: String] = [
        "P": "Printer", "F": "Fax", "C": "Copy", "M": "Collator", "D": "Brown Box"
    ]
    private let powerPelletPositions = [
        CGPoint(x: 2, y: 15), CGPoint(x: 33, y: 15),
        CGPoint(x: 2, y: 1), CGPoint(x: 33, y: 1)
    ]
    private let cubicleColors: [NSColor] = [
        .systemBlue, .systemTeal, .systemIndigo, .systemGreen, .systemPink, .systemBrown,
        .systemPurple, .systemRed, .systemOrange, .systemYellow, .systemCyan, //.systemGray (save for Men in Black Level)
    ]

    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var mazeBuilder: MazeBuilder!
    private var hud: HUD!
    private let sound = SoundManager()

    private let state = RoundState()
    private let inputController = PointerInputController()
    private let contactRouter = ContactRouter()
    private let powerPellet = PowerPelletTimer()
    private var travelerSpawner: TravelerSpawner!
    private var workerController: WorkerController!
    private var bossController: BossController!

    private(set) var isGameOver = false
    var isPowerPelletMode: Bool { powerPellet.isActive }

    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        anchorPoint = CGPoint(x: 0, y: 0)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = contactRouter

        gridMap = GridMap(tileSize: tileSize, rows: currentLevelRows())
        pathfinder = Pathfinder(map: gridMap)
        mazeBuilder = MazeBuilder(map: gridMap, powerPelletPositions: powerPelletPositions, machineNames: machineNames)
        hud = HUD(requiredItems: requiredItems)
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound)
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder, sound: sound)
        bossController.delegate = self
        wireContactRouter()

        buildLevel()
        hud.showMessage("Collect office dots and finish the TPS report!", duration: 3)
        sound.startBackgroundMusic()
        inputController.delegate = self
        inputController.start()
        view.window?.acceptsMouseMovedEvents = true
        inputController.hideCursor()
    }

    override func willMove(from view: SKView) {
        inputController.unhideCursor()
    }

    // All subsystems are SKAction-driven; nothing needed per-frame.

    // MARK: - Input
    override func keyDown(with event: NSEvent) {
        if isGameOver {
            switch event.keyCode {
            case 49: restartGame()
            case 53: returnToTitleScene()
            default: break
            }
            return
        }
        guard let direction = MoveDirection(keyCode: event.keyCode), !event.isARepeat else { return }
        workerController.queueDirection(direction)
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

    // MARK: - WorkerControllerDelegate
    var workerGrid: CGPoint { workerController.grid }
    var workerDirection: MoveDirection? { workerController.direction }

    func workerDidEnterTile(_ grid: CGPoint) {
        guard mazeBuilder.collectDot(atColumn: Int(grid.x), row: Int(grid.y)) else { return }
        state.collectedDots += 1
        state.bumpScore(by: 1)
        sound.playDotBlip()
        refreshHUD()
        if state.collectedDots >= state.dotCount { startNextLevel() }
    }

    // MARK: - BossControllerDelegate
    func bossDidCatchWorker() { bossCaughtWorker() }

    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint) {
        state.bumpScore(by: points)
        sound.playCaptureBoss(streak: points / 100)
        ScorePopup.show(points, at: position, in: self)
        refreshHUD()
        hud.showMessage("\(name) captured! +\(points)", duration: 2)
    }

    // MARK: - Contact wiring

    private func wireContactRouter() {
        contactRouter.shouldIgnoreContact = { [weak self] in self?.isGameOver ?? true }
        contactRouter.onBossTouchedWorker = { [weak self] node in
            guard let self else { return }
            guard let bossNode = node as? PixelPerson else { return }
            // Skip while the boss is in its post-escape spawn freeze —
            // he's visible but can't kill yet.
            if self.bossController.isImmobilized(boss: bossNode) { return }
            if self.bossController.isInFleeMode(boss: bossNode) {
                self.bossController.capture(boss: bossNode)
            } else {
                // Instantly hide AND disable the catching boss so it can't
                // render a single frame at PETE's tile or fire another
                // contact while bossCaughtWorker runs. The teleportAll
                // call inside bossCaughtWorker will then destroy + respawn
                // every boss fresh in its corner.
                bossNode.alpha = 0
                bossNode.physicsBody?.categoryBitMask = 0
                bossNode.removeAllActions()
                self.bossController.relocateAfterCatch(boss: bossNode)
                self.bossCaughtWorker()
            }
        }
        contactRouter.onPowerPelletTouched = { [weak self] node in
            node?.removeFromParent()
            guard let self else { return }
            self.state.bumpScore(by: 5)
            self.sound.playPowerPellet()
            self.startPowerPelletMode()
            self.refreshHUD()
        }
        contactRouter.onMachineTouchedWorker = { [weak self] body, name in
            self?.handleMachine(body: body, name: name)
        }
        contactRouter.onTpsBoxTouchedWorker = { [weak self] in self?.collectTPSReport() }
        contactRouter.onFishTouchedWorker = { [weak self] node in self?.catchTraveler(node) }
    }

    private func handleMachine(body: SKPhysicsBody, name: String) {
        guard requiredItems.contains(name), !state.reportItems.contains(name) else { return }
        state.reportItems.insert(name)
        sound.playMachine(named: name)
        mazeBuilder.grayOutMachine(body)
        refreshHUD()
        if state.reportItems.count == requiredItems.count {
            hud.showMessage("TPS report complete! Deliver it to a brown box.", duration: 6)
        } else {
            hud.showMessage("Collected \(name) page for TPS report", duration: 2)
        }
    }

    // MARK: - Level / round flow

    private func buildLevel() {
        gridMap.setRows(currentLevelRows())
        mazeBuilder.cubicleColor = cubicleColors[(state.level - 1) % cubicleColors.count]
        state.dotCount = mazeBuilder.build(in: self)
        hud.install(in: self)
        workerController = WorkerController(spawnGrid: workerSpawn, gridMap: gridMap, sound: sound)
        workerController.delegate = self
        addChild(workerController.node)
        bossController.spawn(forLevel: state.level)
        refreshHUD()
        let scheduledLevel = state.level
        travelerSpawner.scheduleVisits(of: currentTraveler()) { [weak self] in
            guard let self else { return false }
            return self.state.level == scheduledLevel && !self.isGameOver
        }
    }

    private func currentLevelRows() -> [String] {
        officeMaps[(state.level - 1) % officeMaps.count]
    }

    private func currentTraveler() -> LevelTraveler {
        levelTravelers[(state.level - 1) % levelTravelers.count]
    }

    private func catchTraveler(_ node: SKNode?) {
        guard let caught = travelerSpawner.tryCatch(node) else { return }
        state.bumpScore(by: caught.traveler.points)
        sound.playFishOrTreat()
        refreshHUD()
        hud.showMessage("Caught \(caught.emoji)! +\(caught.traveler.points)", duration: 2)
        ScorePopup.show(caught.traveler.points, at: caught.position, in: self)
    }

    private func collectTPSReport() {
        guard state.reportItems.count == requiredItems.count else {
            hud.showMessage("Brown boxes collect finished TPS reports.", duration: 2)
            return
        }
        state.tpsReportsCreated += 1
        state.reportItems.removeAll()
        state.bumpScore(by: 200)
        sound.playTpsDeliver()
        let gainedLife = state.lives < HUD.maxLives
        if gainedLife { state.lives += 1 }
        refreshHUD()
        hud.showMessage(
            gainedLife ? "TPS report delivered! +200, extra worker hired."
                       : "TPS report delivered! +200, workers at max.",
            duration: 3
        )
    }

    private func bossCaughtWorker() {
        sound.playCaughtByBoss()
        state.lives -= 1
        state.reportItems.removeAll()
        mazeBuilder.resetGrayedMachines(in: self, names: requiredItems)
        refreshHUD()
        workerController.node.setBodyColor(.systemOrange)
        let worker = workerController.node
        worker.run(.sequence([
            .wait(forDuration: 0.5),
            .run { [weak worker] in worker?.setBodyColor(.systemTeal) }
        ]), withKey: "gameOverFlash")
        workerController.resetMotion()
        workerController.teleport(to: workerSpawn)
        bossController.teleportAllToSpawn()
        if state.lives <= 0 {
            triggerGameOver()
        } else {
            hud.showMessage("A boss caught you! \(state.lives) workers left.", duration: 3)
        }
    }

    private func triggerGameOver() {
        isGameOver = true
        inputController.unhideCursor()
        GameCenterClient.submitScore(state.score, to: LeaderboardPanel.leaderboardID)
        LocalHighScores.record(name: GameCenterClient.currentPlayerName(), score: state.score)
        sound.stopPowerPelletBass()
        sound.stopBackgroundMusic()
        sound.playGameOver()
        workerController.resetMotion()
        bossController.stopAll()
        hud.showGameOver(in: self)
    }

    private func resetSceneAndBuild() {
        bossController.clear()
        travelerSpawner.reset()
        powerPellet.deactivate()
        removeAllActions()
        removeAllChildren()
        buildLevel()
    }

    private func restartGame() {
        hud.hideGameOver()
        sound.startBackgroundMusic()
        inputController.hideCursor()
        isGameOver = false
        state.resetForNewGame()
        resetSceneAndBuild()
        hud.showMessage("New game! Collect dots and TPS reports.", duration: 3)
    }

    private func startNextLevel() {
        state.advanceLevel()
        resetSceneAndBuild()
        sound.playLevelStart()
        hud.showMessage("Level \(state.level)! New office floor loaded.", duration: 3)
    }

    private func returnToTitleScene() {
        guard let view else { return }
        hud.hideGameOver()
        sound.stopBackgroundMusic()
        let title = TitleScene(size: size)
        title.scaleMode = .aspectFit
        view.presentScene(title, transition: .fade(withDuration: 0.5))
    }

    // MARK: - Power pellet
    private func startPowerPelletMode() {
        powerPellet.activate()
        bossController.setPowerPelletActive(true)
        sound.startPowerPelletBass()
        run(.sequence([
            .wait(forDuration: 20),
            .run { [weak self] in self?.endPowerPelletMode() }
        ]), withKey: "powerPelletExpiry")
        hud.showMessage("Power pellet! Capture the bosses for 20 seconds.", duration: 3)
    }

    private func endPowerPelletMode() {
        powerPellet.deactivate()
        bossController.setPowerPelletActive(false)
        sound.stopPowerPelletBass()
        removeAction(forKey: "powerPelletExpiry")
        hud.showMessage("Power pellet mode ended.", duration: 2)
    }

    // MARK: - HUD

    private func refreshHUD() {
        hud.updateStatus(
            score: state.score, highScore: state.highScore, level: state.level,
            dots: state.collectedDots, total: state.dotCount,
            reports: state.tpsReportsCreated, items: state.reportItems
        )
        hud.updateLives(state.lives)
        let cyclePosition = ((state.level - 1) % levelTravelers.count) + 1
        let emojis = (0..<cyclePosition).map { levelTravelers[$0].emoji }
        hud.updateLevelEmojis(emojis)
    }
}
