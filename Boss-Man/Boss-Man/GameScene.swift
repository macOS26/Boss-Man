import AppKit
import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate, PointerInputControllerDelegate, WorkerControllerDelegate, BossControllerDelegate {
    private let tileSize: CGFloat = 32
    private let workerSpawn = CGPoint(x: 18, y: 7)
    private let powerPelletDuration: TimeInterval = 20

    private let requiredItems = ["Printer", "Fax", "Copy", "Collator"]
    private let machineNames: [Character: String] = [
        "P": "Printer",
        "F": "Fax",
        "C": "Copy",
        "M": "Collator",
        "D": "Desk"
    ]
    private let powerPelletPositions = [
        CGPoint(x: 2, y: 15),
        CGPoint(x: 33, y: 15),
        CGPoint(x: 2, y: 1),
        CGPoint(x: 33, y: 1)
    ]
    private let cubicleColors: [NSColor] = [
        .systemBlue, .systemTeal, .systemIndigo, .systemGreen, .systemPink, .systemBrown
    ]

    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var mazeBuilder: MazeBuilder!
    private var hud: HUD!
    private let sound = SoundManager()

    private let inputController = PointerInputController()
    private var travelerSpawner: TravelerSpawner!
    private var workerController: WorkerController!
    private var bossController: BossController!

    private var level = 1
    private var dotCount = 0
    private var collectedDots = 0
    private var tpsReportsCreated = 0
    private var reportItems: Set<String> = []
    private var lives = HUD.maxLives
    private(set) var isGameOver = false
    private static let highScoreKey = "Boss-Man.highScore"
    private var score = 0
    private var highScore = UserDefaults.standard.integer(forKey: GameScene.highScoreKey) {
        didSet {
            if highScore != oldValue {
                UserDefaults.standard.set(highScore, forKey: GameScene.highScoreKey)
            }
        }
    }

    private var lastUpdateTime: TimeInterval = 0
    private var gameOverFlash: TimeInterval = 0
    private(set) var isPowerPelletMode = false
    private var powerPelletModeEndsAt: TimeInterval = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        anchorPoint = CGPoint(x: 0, y: 0)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        gridMap = GridMap(tileSize: tileSize, rows: currentLevelRows())
        pathfinder = Pathfinder(map: gridMap)
        mazeBuilder = MazeBuilder(map: gridMap, powerPelletPositions: powerPelletPositions, machineNames: machineNames)
        hud = HUD(requiredItems: requiredItems)
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound)
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder)
        bossController.delegate = self

        buildLevel()
        hud.showMessage("Collect office dots and finish the TPS report!", duration: 3)
        sound.startBackgroundMusic()
        inputController.delegate = self
        inputController.start()
        // SKView forwards mouseDown/Dragged/Moved to the running scene as
        // long as the window opts in to mouse-moved delivery.
        view.window?.acceptsMouseMovedEvents = true
        inputController.hideCursor()
    }

    override func willMove(from view: SKView) {
        inputController.unhideCursor()
    }

    override func update(_ currentTime: TimeInterval) {
        lastUpdateTime = currentTime
        if isGameOver { return }
        if isPowerPelletMode && currentTime >= powerPelletModeEndsAt {
            endPowerPelletMode()
        }
        workerController.update(currentTime: currentTime)
        bossController.step(at: currentTime)
        travelerSpawner.step(at: currentTime)
        if gameOverFlash > 0, currentTime > gameOverFlash {
            gameOverFlash = 0
            workerController.node.setBodyColor(.systemTeal)
        }
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
        guard let direction = MoveDirection(keyCode: event.keyCode), !event.isARepeat else { return }
        queueDirection(direction)
    }

    override func mouseMoved(with event: NSEvent) {
        inputController.handleMouseDelta(dx: event.deltaX, dy: event.deltaY)
    }

    override func mouseDragged(with event: NSEvent) {
        inputController.handleMouseDelta(dx: event.deltaX, dy: event.deltaY)
    }

    var isGameOverForInput: Bool { isGameOver }

    func inputControllerDidRequest(_ direction: MoveDirection) {
        queueDirection(direction)
    }

    private func queueDirection(_ direction: MoveDirection) {
        workerController.queueDirection(direction)
    }

    // MARK: - WorkerControllerDelegate

    var workerGrid: CGPoint { workerController.grid }
    var workerDirection: MoveDirection? { workerController.direction }

    func workerDidEnterTile(_ grid: CGPoint) {
        guard mazeBuilder.collectDot(atColumn: Int(grid.x), row: Int(grid.y)) else { return }
        collectedDots += 1
        score += 1
        sound.playDotBlip()
        refreshHUD()
        if collectedDots >= dotCount { startNextLevel() }
    }

    // MARK: - BossControllerDelegate

    func bossDidCatchWorker() {
        bossCaughtWorker()
    }

    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint) {
        score += points
        sound.playCaptureBoss(streak: points / 100)
        showScorePopup(points, at: position)
        refreshHUD()
        hud.showMessage("\(name) captured! +\(points)", duration: 2)
    }

    // MARK: - Contact handling

    func didBegin(_ contact: SKPhysicsContact) {
        if isGameOver { return }
        let bodies = [contact.bodyA, contact.bodyB]

        if let bossBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.boss }),
           bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.worker }) {
            if isPowerPelletMode, let bossNode = bossBody.node as? PixelPerson {
                bossController.capture(boss: bossNode)
            } else {
                bossCaughtWorker()
            }
        }

        if let powerPelletBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.powerPellet }) {
            powerPelletBody.node?.removeFromParent()
            score += 5
            sound.playPowerPellet()
            startPowerPelletMode()
            refreshHUD()
        }

        if let machineBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.machine }),
           let name = machineBody.node?.name,
           requiredItems.contains(name),
           !reportItems.contains(name) {
            reportItems.insert(name)
            sound.playMachine(named: name)
            let machineNode = machineBody.node
            machineNode?.alpha = 0.55
            machineBody.contactTestBitMask = 0
            machineNode?.removeAction(forKey: "machineCooldown")
            machineNode?.run(.sequence([
                .wait(forDuration: 15),
                .run { [weak machineNode] in
                    machineNode?.alpha = 1
                    machineNode?.physicsBody?.contactTestBitMask = PhysicsCategory.worker
                }
            ]), withKey: "machineCooldown")
            refreshHUD()
            if reportItems.count == requiredItems.count {
                hud.showMessage("TPS report complete! Deliver it to a brown box.", duration: 4)
            } else {
                hud.showMessage("Collected \(name) page for TPS report", duration: 2)
            }
        }

        if bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.tpsBox }),
           bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.worker }) {
            collectTPSReport()
        }

        if let fishBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.fish }),
           bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.worker }) {
            catchTraveler(fishBody.node)
        }
    }

    // MARK: - Level / round flow

    private func buildLevel() {
        gridMap.setRows(currentLevelRows())
        mazeBuilder.cubicleColor = cubicleColors[(level - 1) % cubicleColors.count]
        dotCount = mazeBuilder.build(in: self)
        hud.install(in: self)
        spawnWorker()
        bossController.spawn(forLevel: level)
        refreshHUD()
        let scheduledLevel = level
        let traveler = currentTraveler()
        travelerSpawner.scheduleVisits(of: traveler) { [weak self] in
            guard let self else { return false }
            return self.level == scheduledLevel && !self.isGameOver
        }
    }

    private func spawnWorker() {
        workerController = WorkerController(spawnGrid: workerSpawn, gridMap: gridMap, sound: sound)
        workerController.delegate = self
        addChild(workerController.node)
    }

    private func currentLevelRows() -> [String] {
        officeMaps[(level - 1) % officeMaps.count]
    }

    private func currentTraveler() -> LevelTraveler {
        levelTravelers[(level - 1) % levelTravelers.count]
    }

    private func catchTraveler(_ node: SKNode?) {
        guard let caught = travelerSpawner.tryCatch(node) else { return }
        score += caught.traveler.points
        sound.playFishOrTreat()
        refreshHUD()
        hud.showMessage("Caught \(caught.emoji)! +\(caught.traveler.points)", duration: 2)
        showScorePopup(caught.traveler.points, at: caught.position)
    }

    private func collectTPSReport() {
        guard reportItems.count == requiredItems.count else {
            hud.showMessage("Brown boxes collect finished TPS reports.", duration: 2)
            return
        }
        tpsReportsCreated += 1
        reportItems.removeAll()
        score += 200
        sound.playTpsDeliver()
        let gainedLife = lives < HUD.maxLives
        if gainedLife { lives += 1 }
        refreshHUD()
        hud.showMessage(
            gainedLife
                ? "TPS report delivered! +200, extra worker hired."
                : "TPS report delivered! +200, workers at max.",
            duration: 3
        )
    }

    private func bossCaughtWorker() {
        sound.playCaughtByBoss()
        lives -= 1
        reportItems.removeAll()
        resetGrayedMachines()
        refreshHUD()
        workerController.node.setBodyColor(.systemOrange)
        gameOverFlash = CACurrentMediaTime() + 0.5
        workerController.resetMotion()
        workerController.teleport(to: workerSpawn)
        bossController.teleportAllToSpawn()
        if lives <= 0 {
            triggerGameOver()
        } else {
            hud.showMessage("A boss caught you! \(lives) workers left.", duration: 3)
        }
    }

    private func resetGrayedMachines() {
        for child in children {
            guard let name = child.name, requiredItems.contains(name) else { continue }
            child.removeAction(forKey: "machineCooldown")
            child.alpha = 1
            child.physicsBody?.contactTestBitMask = PhysicsCategory.worker
        }
    }

    private func triggerGameOver() {
        isGameOver = true
        inputController.unhideCursor()
        GameCenterClient.submitScore(score, to: LeaderboardPanel.leaderboardID)
        LocalHighScores.record(name: GameCenterClient.currentPlayerName(), score: score)
        sound.stopBackgroundMusic()
        sound.playGameOver()
        workerController.resetMotion()
        bossController.stopAll()
        hud.showGameOver(in: self)
    }

    private func restartGame() {
        hud.hideGameOver()
        sound.startBackgroundMusic()
        inputController.hideCursor()
        isGameOver = false
        level = 1
        lives = HUD.maxLives
        tpsReportsCreated = 0
        collectedDots = 0
        score = 0
        reportItems.removeAll()
        gameOverFlash = 0
        isPowerPelletMode = false
        powerPelletModeEndsAt = 0
        bossController.clear()
        travelerSpawner.reset()
        removeAllActions()
        removeAllChildren()
        buildLevel()
        hud.showMessage("New game! Collect dots and TPS reports.", duration: 3)
    }

    private func startNextLevel() {
        level += 1
        bossController.clear()
        travelerSpawner.reset()
        removeAllActions()
        removeAllChildren()
        reportItems.removeAll()
        gameOverFlash = 0
        isPowerPelletMode = false
        powerPelletModeEndsAt = 0
        collectedDots = 0
        buildLevel()
        sound.playLevelStart()
        hud.showMessage("Level \(level)! New office floor loaded.", duration: 3)
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
        isPowerPelletMode = true
        powerPelletModeEndsAt = lastUpdateTime + powerPelletDuration
        bossController.setPowerPelletActive(true)
        hud.showMessage("Power pellet! Capture the bosses for 20 seconds.", duration: 3)
    }

    private func endPowerPelletMode() {
        isPowerPelletMode = false
        powerPelletModeEndsAt = 0
        bossController.setPowerPelletActive(false)
        hud.showMessage("Power pellet mode ended.", duration: 2)
    }

    // MARK: - HUD + popups

    private func refreshHUD() {
        if score > highScore { highScore = score }
        hud.updateStatus(score: score, highScore: highScore, level: level, dots: collectedDots, total: dotCount, reports: tpsReportsCreated, items: reportItems)
        hud.updateLives(lives)
        let cyclePosition = ((level - 1) % levelTravelers.count) + 1
        let emojis = (0..<cyclePosition).map { levelTravelers[$0].emoji }
        hud.updateLevelEmojis(emojis)
    }

    private func showScorePopup(_ points: Int, at position: CGPoint) {
        let popup = SKLabelNode(fontNamed: "Menlo-Bold")
        popup.text = "\(points)"
        popup.fontSize = 18
        popup.fontColor = .systemYellow
        popup.position = CGPoint(x: position.x, y: position.y + 20)
        popup.zPosition = 12
        addChild(popup)
        popup.run(.sequence([
            .group([
                .moveBy(x: 0, y: 28, duration: 0.7),
                .fadeOut(withDuration: 0.7)
            ]),
            .removeFromParent()
        ]))
    }
}
