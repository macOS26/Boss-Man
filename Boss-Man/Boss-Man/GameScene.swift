import AppKit
import SpriteKit

final class GameScene: SKScene, PointerInputControllerDelegate, WorkerControllerDelegate, BossControllerDelegate {
    private let tileSize: CGFloat = 32
    private let workerSpawn = CGPoint(x: 18, y: 7)
    private let goldDiscDuration: TimeInterval = 20

    private let requiredItems = Strings.Machine.required
    private let machineNames: [Character: String] = [
        Strings.Tile.printerChar: Strings.Machine.printer,
        Strings.Tile.faxChar: Strings.Machine.fax,
        Strings.Tile.coverSheetChar: Strings.Machine.coverSheet,
        Strings.Tile.bookBinderChar: Strings.Machine.bookBinder,
        Strings.Tile.brownBoxChar: Strings.Machine.brownBox
    ]
    private let goldDiscPositions = [
        CGPoint(x: 2, y: 15), CGPoint(x: 33, y: 15),
        CGPoint(x: 2, y: 1),  CGPoint(x: 33, y: 1)
    ]
    private let cubicleColors: [NSColor] = [
        .systemBlue,   .systemTeal, .systemIndigo, .systemGreen,  .systemPink, .systemBrown,
        .systemPurple, .systemRed,  .systemOrange, .systemYellow, .systemCyan, .systemGray
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
        hud.showMessage(state.practiceMode ? Strings.Message.practiceMode : Strings.Message.intro, duration: 3)
        inputController.delegate = self
        inputController.start()
        view.window?.acceptsMouseMovedEvents = true
        inputController.hideCursor()
    }

    override func willMove(from view: SKView) {
        inputController.unhideCursor()
    }

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
            hud.showMessage(Strings.HUD.empty, duration: 0.1)
        } else {
            hud.showMessage(Strings.Message.paused, duration: 9999)
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

    override func mouseUp(with event: NSEvent) {
        guard isGameOver else { return }
        let loc = convert(event.location(in: self), from: self)
        let hitNames = nodes(at: loc).compactMap { $0.name }

        if hitNames.contains(UsernameDialog.confirmButtonName),
           let dialog = childNode(withName: UsernameDialog.nodeName) as? UsernameDialog {
            dialog.handleConfirm()
            dialog.removeFromParent()
        } else if hitNames.contains(UsernameDialog.skipButtonName),
                  let dialog = childNode(withName: UsernameDialog.nodeName) as? UsernameDialog {
            dialog.handleSkip()
            dialog.removeFromParent()
        }
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

    // MARK: - BossControllerDelegate
    func bossDidCatchWorker() { bossCaughtWorker() }

    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint) {
        state.bumpScore(by: points)
        sound.playCaptureBoss(streak: points / 100)
        ScorePopup.show(points, at: position, in: self)
        refreshHUD()
        hud.showMessage(Strings.Message.bossCaptured(name: name, points: points), duration: 2)
    }

    // MARK: - Contact wiring
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

    private let reportItemPoints = [10, 25, 50, 100]

    private func handleMachine(body: SKPhysicsBody, name: String) {
        guard requiredItems.contains(name), !state.reportItems.contains(name) else { return }
        state.reportItems.insert(name)

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
            hud.showMessage(Strings.Message.tpsReportReady, duration: 6)
        } else {
            hud.showMessage(Strings.Message.reportItemCollected(name: name,
                                                                points: reportItemPoints[itemIndex]),
                            duration: 2)
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
        let spawn = mazeBuilder.workerSpawnFromMap ?? workerSpawn
        workerController = WorkerController(spawnGrid: spawn, gridMap: gridMap, sound: sound)
        workerController.delegate = self
        addChild(workerController.node)
        workerController.applySpawnShield()
        bossController.spawn(forLevel: state.level,
                             spawnOverrides: mazeBuilder.bossSpawnsFromMap)
        refreshHUD()
        let scheduledLevel = state.level
        travelerSpawner.scheduleVisits(of: currentTraveler()) { [weak self] in
            guard let self else { return false }
            return self.state.level == scheduledLevel && !self.isGameOver
        }
    }

    private func currentLevelRows() -> [String] {
        let idx = (state.level - 1) % Levels.levelNames.count
        let name = Levels.levelNames[idx]
        if let custom = LevelStore.shared.loadLevel(name: name) {
            return custom
        }
        return officeMaps[idx % officeMaps.count]
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
        hud.showMessage(Strings.Message.travelerCaught(emoji: caught.emoji,
                                                       points: caught.traveler.points),
                        duration: 2)
        ScorePopup.show(caught.traveler.points, at: caught.position, in: self)
    }

    private func collectTPSReport() {
        guard state.reportItems.count == requiredItems.count else {
            hud.showMessage(Strings.Message.brownBoxHint, duration: 2)
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
        hud.showMessage(Strings.Message.tpsTurnedIn(points: tpsPoints, gainedLife: gainedLife),
                        duration: 3)
        checkLevelComplete()
    }

    private func bossCaughtWorker() {
        sound.playCaughtByBoss()
        state.lives -= 1

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
        workerController.teleport(to: mazeBuilder.workerSpawnFromMap ?? workerSpawn)
        workerController.applySpawnShield()
        bossController.teleportAllToSpawn()
        if state.lives <= 0 {
            triggerGameOver()
        } else {
            hud.showMessage(Strings.Message.bossCaughtYou(state.lives), duration: 3)
        }
    }

    private func triggerGameOver() {
        isGameOver = true
        inputController.unhideCursor()
        if !state.practiceMode {
            GameCenterClient.submitScore(state.score, to: LeaderboardPanel.leaderboardID)

            // Check if this score qualifies for the local leaderboard
            let defaultName = LocalHighScores.savedUsername ?? GameCenterClient.currentPlayerName()
            if LocalHighScores.qualifies(name: defaultName, score: state.score) {
                showUsernameDialog(defaultName: defaultName)
            } else {
                LocalHighScores.record(name: defaultName, score: state.score)
            }
        }
        sound.stopGoldDiscBass()
        sound.stopBackgroundMusic()
        sound.playGameOver()
        workerController.resetMotion()
        bossController.stopAll()
        hud.showGameOver(in: self)
    }

    private func showUsernameDialog(defaultName: String) {
        let dialog = UsernameDialog(
            size: CGSize(width: 320, height: 220),
            fontName: Strings.Font.menloBold,
            onConfirm: { [weak self] name in
                guard let self else { return }
                LocalHighScores.record(name: name, score: self.state.score)
            },
            onSkip: { [weak self] in
                guard let self else { return }
                LocalHighScores.record(name: defaultName, score: self.state.score)
            }
        )
        dialog.position = CGPoint(x: frame.midX, y: frame.midY)
        dialog.zPosition = 2000
        addChild(dialog)
        dialog.attachFieldToView()
    }

    private func resetSceneAndBuild() {
        bossController.clear()
        travelerSpawner.reset()
        goldDisc.deactivate()
        sound.stopGoldDiscBass()
        removeAction(forKey: Strings.ActionKey.goldDiscExpiry)
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
        hud.showMessage(Strings.Message.newGame, duration: 3)
    }

    private func startNextLevel() {
        state.advanceLevel()
        resetSceneAndBuild()
        sound.playLevelStart()
        hud.showMessage(Strings.Message.levelLoaded(state.level), duration: 3)
    }

    private func returnToTitleScene() {
        guard let view else { return }
        hud.hideGameOver()
        sound.stopBackgroundMusic()
        // ESC during a playtest launched from the level editor returns
        // to the editor (on the same floor), not the title screen.
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

    // MARK: - Gold disc
    private func startGoldDiscMode() {
        goldDisc.activate()
        bossController.setGoldDiscActive(true)
        sound.startGoldDiscBass()
        run(.sequence([
            .wait(forDuration: 20),
            .run { [weak self] in self?.endGoldDiscMode() }
        ]), withKey: Strings.ActionKey.goldDiscExpiry)
        hud.showMessage(Strings.Message.goldDiscActivated, duration: 3)
    }

    private func endGoldDiscMode() {
        goldDisc.deactivate()
        bossController.setGoldDiscActive(false)
        sound.stopGoldDiscBass()
        removeAction(forKey: Strings.ActionKey.goldDiscExpiry)
        hud.showMessage(Strings.Message.goldDiscEnded, duration: 2)
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
