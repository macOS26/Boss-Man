import AppKit
import SpriteKit

final class GameScene: SKScene, PointerInputControllerDelegate, WorkerControllerDelegate, BossControllerDelegate {
    private let tileSize: CGFloat = 32
    private let workerSpawn = CGPoint(x: 18, y: 7)
    private let goldDiscDuration: TimeInterval = 20

    private let requiredItems = ["Printer", "Fax", "Copy", "Collator"]
    private let machineNames: [Character: String] = [
        "P": "Printer", "F": "Fax", "C": "Copy", "M": "Collator", "D": "Brown Box"
    ]
    private let goldDiscPositions = [
        CGPoint(x: 2, y: 15), CGPoint(x: 33, y: 15),
        CGPoint(x: 2, y: 1),  CGPoint(x: 33, y: 1)
    ]
    private let cubicleColors: [NSColor] = [
        .systemBlue,   .systemTeal, .systemIndigo, .systemGreen,  .systemPink, .systemBrown,
        .systemPurple, .systemRed,  .systemOrange, .systemYellow, .systemCyan, .systemGray // MIB level 12
    ]

    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var mazeBuilder: MazeBuilder!
    private var hud: HUD!
    private let sound = SoundManager()

    private let state = RoundState()
    private let inputController = PointerInputController()
    private let contactRouter = ContactRouter()
    private let goldDisc = GoldDiscTimer()
    private var travelerSpawner: TravelerSpawner!
    private var workerController: WorkerController!
    private var bossController: BossController!

    private(set) var isGameOver = false
    var isGoldDiscMode: Bool { goldDisc.isActive }
    var isPeteShielded: Bool { workerController?.isShielded ?? false }

    // MARK: - Lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        anchorPoint = CGPoint(x: 0, y: 0)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = contactRouter

        gridMap = GridMap(tileSize: tileSize, rows: currentLevelRows())
        pathfinder = Pathfinder(map: gridMap)
        mazeBuilder = MazeBuilder(map: gridMap, goldDiscPositions: goldDiscPositions, machineNames: machineNames)
        hud = HUD(requiredItems: requiredItems)
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound)
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder, sound: sound)
        bossController.delegate = self
        wireContactRouter()

        buildLevel()
        hud.showMessage("Collect office dots and finish the TPS report!", duration: 3)
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
        switch event.keyCode {
        case 49:
            togglePause()
            return
        case 53:
            returnToTitleScene()
            return
        default:
            break
        }
        guard !isPaused else { return }
        guard let direction = MoveDirection(keyCode: event.keyCode), !event.isARepeat else { return }
        workerController.queueDirection(direction)
    }

    private func togglePause() {
        if isPaused {
            isPaused = false
            sound.resumeAudio()
            inputController.hideCursor()
            hud.showMessage("", duration: 0.1)
        } else {
            hud.showMessage("Paused — press SPACE to resume", duration: 9999)
            inputController.unhideCursor()
            isPaused = true
            sound.pauseAudio()
        }
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
        checkLevelComplete()
    }

    /// Level advances only after every dot AND every gold disc on the
    /// floor is collected AND at least one TPS report has been turned
    /// in. Called from each of the three trigger points (dot pickup,
    /// gold-disc pickup, TPS delivery).
    private func checkLevelComplete() {
        let dotsDone = state.collectedDots >= state.dotCount
        let discsDone = state.collectedGoldDiscs >= state.goldDiscCount
        guard dotsDone && discsDone else { return }
        if state.tpsReportsDelivered >= 1 {
            startNextLevel()
        } else {
            hud.showMessage("Turn in at least 1 TPS report to complete the level!", duration: 3)
        }
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
            } else if !self.workerController.isShielded {
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
        contactRouter.onGoldDiscTouched = { [weak self] node in
            node?.removeFromParent()
            guard let self else { return }
            self.state.bumpScore(by: 5)
            self.state.collectedGoldDiscs += 1
            self.sound.playGoldDisc()
            self.startGoldDiscMode()
            self.refreshHUD()
            self.checkLevelComplete()
        }
        contactRouter.onMachineTouchedWorker = { [weak self] body, name in
            self?.handleMachine(body: body, name: name)
        }
        contactRouter.onTpsBoxTouchedWorker = { [weak self] in self?.collectTPSReport() }
        contactRouter.onFishTouchedWorker = { [weak self] node in self?.catchTraveler(node) }
    }

    /// Points awarded for each successive report item: 1st→10, 2nd→25, 3rd→50, 4th→100
    private let reportItemPoints = [10, 25, 50, 100]

    private func handleMachine(body: SKPhysicsBody, name: String) {
        guard requiredItems.contains(name), !state.reportItems.contains(name) else { return }
        state.reportItems.insert(name)

        // Award escalating points for each collected report item
        let itemIndex = state.reportItems.count - 1
        if itemIndex < reportItemPoints.count {
            let pts = reportItemPoints[itemIndex]
            state.bumpScore(by: pts)
            state.currentReportScore += pts
            ScorePopup.show(pts, at: body.node?.position ?? .zero, in: self)
        }

        sound.playMachine(named: name)
        mazeBuilder.grayOutMachine(body)
        refreshHUD()
        if state.reportItems.count == requiredItems.count {
            hud.showMessage("TPS report complete! Deliver it to a brown box.", duration: 6)
        } else {
            hud.showMessage("Collected \(name) page for TPS report +\(reportItemPoints[itemIndex])", duration: 2)
        }
    }

    // MARK: - Level / round flow

    private func buildLevel() {
        sound.startBackgroundMusic(theme: musicTheme(for: state.level))
        gridMap.setRows(currentLevelRows())
        mazeBuilder.cubicleColor = cubicleColors[(state.level - 1) % cubicleColors.count]
        state.dotCount = mazeBuilder.build(in: self)
        state.goldDiscCount = mazeBuilder.placedGoldDiscs
        hud.install(in: self)
        workerController = WorkerController(spawnGrid: workerSpawn, gridMap: gridMap, sound: sound)
        workerController.delegate = self
        addChild(workerController.node)
        // 5-second spawn shield: orange + invulnerable for 4s, then
        // a 1s fade to teal. Applies on level start and every restart.
        workerController.applySpawnShield()
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

    private func musicTheme(for level: Int) -> MusicTheme {
        level % 12 == 0 ? .mib : .normal
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
        state.tpsReportsDelivered += 1
        state.reportItems.removeAll()

        // Award points based on level: 200, 300, 400, 500... (+100 per level)
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
        hud.showMessage(
            gainedLife ? "TPS report turned in! +\(tpsPoints), extra worker hired."
                       : "TPS report turned in! +\(tpsPoints), workers at max.",
            duration: 3
        )
        // If dots + gold discs were already cleared, this TPS delivery
        // is what finishes the level.
        checkLevelComplete()
    }

    private func bossCaughtWorker() {
        sound.playCaughtByBoss()
        state.lives -= 1

        // Show red negative popup for lost TPS report item points
        if state.currentReportScore > 0 {
            let lost = state.currentReportScore
            if let workerPos = workerController?.node.position {
                ScorePopup.show(-lost, at: workerPos, in: self, color: .systemRed)
            }
        }

        state.reportItems.removeAll()
        state.currentReportScore = 0
        mazeBuilder.resetGrayedMachines(in: self, names: requiredItems)
        refreshHUD()
        workerController.resetMotion()
        workerController.teleport(to: workerSpawn)
        // 5-second spawn shield: orange + invulnerable for 4s, then
        // 1s fade back to teal. PETE can't be caught during it.
        workerController.applySpawnShield()
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
        sound.stopGoldDiscBass()
        sound.stopBackgroundMusic()
        sound.playGameOver()
        workerController.resetMotion()
        bossController.stopAll()
        hud.showGameOver(in: self)
    }

    private func resetSceneAndBuild() {
        bossController.clear()
        travelerSpawner.reset()
        goldDisc.deactivate()
        // Kill any blue-mode bassline that was still looping when the
        // round ended so it doesn't bleed into the next level.
        sound.stopGoldDiscBass()
        removeAction(forKey: "goldDiscExpiry")
        removeAllActions()
        removeAllChildren()
        buildLevel()
    }

    private func restartGame() {
        hud.hideGameOver()
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

    // MARK: - Gold disc
    private func startGoldDiscMode() {
        goldDisc.activate()
        bossController.setGoldDiscActive(true)
        sound.startGoldDiscBass()
        run(.sequence([
            .wait(forDuration: 20),
            .run { [weak self] in self?.endGoldDiscMode() }
        ]), withKey: "goldDiscExpiry")
        hud.showMessage("Gold disc! Capture the bosses for 20 seconds.", duration: 3)
    }

    private func endGoldDiscMode() {
        goldDisc.deactivate()
        bossController.setGoldDiscActive(false)
        sound.stopGoldDiscBass()
        removeAction(forKey: "goldDiscExpiry")
        hud.showMessage("Gold disc mode ended.", duration: 2)
    }

    // MARK: - HUD

    private func refreshHUD() {
        hud.updateStatus(
            score: state.score, highScore: state.highScore, level: state.level,
            dots: state.collectedDots, total: state.dotCount,
            reports: state.tpsReportsDelivered, items: state.reportItems
        )
        hud.updateLives(state.lives)
        let cyclePosition = ((state.level - 1) % levelTravelers.count) + 1
        let emojis = (0..<cyclePosition).map { levelTravelers[$0].emoji }
        hud.updateLevelEmojis(emojis)
    }
}
