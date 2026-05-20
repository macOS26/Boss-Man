import AppKit
import GameController
import GameKit
import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate, PointerInputControllerDelegate {
    // MARK: - PointerInputControllerDelegate

    var isGameOverForInput: Bool { isGameOver }

    func inputControllerDidRequest(_ direction: MoveDirection) {
        queueDirection(direction)
    }

    private struct BossEntity {
        let name: String
        let baseColor: NSColor
        let tieColor: NSColor
        let pantsColor: NSColor
        let spawn: CGPoint
        let ai: BossAI
        let node: PixelPerson
        let tag: SKLabelNode
        let moveInterval: TimeInterval
        let moveDuration: TimeInterval
        var lastMove: TimeInterval
    }

    private let tileSize: CGFloat = 32
    private let workerSpawn = CGPoint(x: 18, y: 7)
    private let workerMoveInterval: TimeInterval = 0.14
    private let workerMoveDuration: TimeInterval = 0.14
    private let bossMoveInterval: TimeInterval = 0.36
    private let bossMoveDuration: TimeInterval = 0.22
    private let bossDetectionRange: CGFloat = 10
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

    private let bossBlueprints: [(name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double)] = [
        (
            name: "BOSS",
            color: .systemRed,
            tie: .black,
            pants: .darkGray,
            spawn: CGPoint(x: 34, y: 15),
            // Blinky: makes a beeline for the worker's tile.
            personality: .directChase,
            speed: 1.0
        ),
        (
            name: "LUMBERGH",
            color: .systemPurple,
            tie: .systemYellow,
            pants: .darkGray,
            spawn: CGPoint(x: 1, y: 1),
            // Pinky: aims four tiles ahead of where the worker is heading to cut him off.
            personality: .ambushAhead(tiles: 4),
            speed: 0.85
        ),
        (
            name: "WADDAMS",
            color: .systemOrange,
            tie: .systemRed,
            pants: .darkGray,
            spawn: CGPoint(x: 34, y: 1),
            // Clyde: chases until within 8 tiles, then retreats to a corner scatter point.
            personality: .timidScatter(scatterGrid: CGPoint(x: 1, y: 1), threshold: 8),
            speed: 0.70
        ),
        (
            name: "BOLTON",
            color: .systemPink,
            tie: .systemTeal,
            pants: .darkGray,
            // Home is the corner cell PETE used to spawn from.
            spawn: CGPoint(x: 1, y: 15),
            // Inky: pivots two tiles ahead of the worker then mirrors BOSS's position through it.
            personality: .flanker(pivotTiles: 2),
            speed: 0.78
        )
    ]

    private let cubicleColors: [NSColor] = [
        .systemBlue,
        .systemTeal,
        .systemIndigo,
        .systemGreen,
        .systemPink,
        .systemBrown
    ]

    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var mazeBuilder: MazeBuilder!
    private var hud: HUD!
    private let sound = SoundManager()

    private var worker: PixelPerson!
    private var bosses: [BossEntity] = []

    private var level = 1
    private var dotCount = 0
    private var collectedDots = 0
    private var tpsReportsCreated = 0
    private var reportItems: Set<String> = []
    private var workerGrid = CGPoint(x: 1, y: 15)
    private var lives = HUD.maxLives
    private var isGameOver = false
    private static let highScoreKey = "Boss-Man.highScore"
    private var score = 0
    private var highScore = UserDefaults.standard.integer(forKey: GameScene.highScoreKey) {
        didSet {
            if highScore != oldValue {
                UserDefaults.standard.set(highScore, forKey: GameScene.highScoreKey)
            }
        }
    }

    private var powerPelletCapturesThisCycle = 0

    private var workerDirection: MoveDirection?
    private var queuedWorkerDirection: MoveDirection?
    private var isWorkerMoving = false
    private var lastWorkerMove: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var gameOverFlash: TimeInterval = 0

    private var isPowerPelletMode = false
    private var powerPelletModeEndsAt: TimeInterval = 0

    private let inputController = PointerInputController()
    private var travelerSpawner: TravelerSpawner!

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

    override func keyDown(with event: NSEvent) {
        if isGameOver {
            switch event.keyCode {
            case 49: restartGame()        // Space → new game
            case 53: returnToTitleScene() // Escape → back to intro
            default: break
            }
            return
        }
        guard let direction = MoveDirection(keyCode: event.keyCode), !event.isARepeat else { return }
        queueDirection(direction)
    }

    private func returnToTitleScene() {
        guard let view else { return }
        hud.hideGameOver()
        sound.stopBackgroundMusic()
        let title = TitleScene(size: size)
        title.scaleMode = .aspectFit
        view.presentScene(title, transition: .fade(withDuration: 0.5))
    }

    /// Single entry point for every input source (keyboard, gamepad
    /// D-pad/thumbstick, trackpad swipe). Mirrors the Pac-Man turn-buffer
    /// contract: set the desired direction, seed workerDirection only if
    /// PETE is currently idle.
    private func queueDirection(_ direction: MoveDirection) {
        queuedWorkerDirection = direction
        if workerDirection == nil { workerDirection = direction }
    }

    // MARK: - Mouse / trackpad pointer

    override func mouseMoved(with event: NSEvent) {
        inputController.handleMouseDelta(dx: event.deltaX, dy: event.deltaY)
    }

    override func mouseDragged(with event: NSEvent) {
        inputController.handleMouseDelta(dx: event.deltaX, dy: event.deltaY)
    }

    override func update(_ currentTime: TimeInterval) {
        lastUpdateTime = currentTime
        if isGameOver { return }
        if isPowerPelletMode && currentTime >= powerPelletModeEndsAt {
            endPowerPelletMode()
        }

        if !isWorkerMoving, currentTime - lastWorkerMove > workerMoveInterval {
            attemptWorkerStep()
        }

        stepBosses(currentTime: currentTime)
        travelerSpawner.step(at: currentTime)

        if gameOverFlash > 0, currentTime > gameOverFlash {
            gameOverFlash = 0
            worker.setBodyColor(.systemTeal)
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        if isGameOver { return }
        let bodies = [contact.bodyA, contact.bodyB]

        if let bossBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.boss }),
           bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.worker }) {
            if isPowerPelletMode {
                if let bossNode = bossBody.node as? PixelPerson,
                   let index = bosses.firstIndex(where: { $0.node === bossNode }) {
                    captureBoss(at: index)
                }
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

        if bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.tpsBox }) &&
            bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.worker }) {
            collectTPSReport()
        }

        if let fishBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.fish }),
           bodies.contains(where: { $0.categoryBitMask == PhysicsCategory.worker }) {
            catchTraveler(fishBody.node)
        }
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

    private func catchTraveler(_ node: SKNode?) {
        guard let caught = travelerSpawner.tryCatch(node) else { return }
        score += caught.traveler.points
        sound.playFishOrTreat()
        refreshHUD()
        hud.showMessage("Caught \(caught.emoji)! +\(caught.traveler.points)", duration: 2)
        showScorePopup(caught.traveler.points, at: caught.position)
    }

    private func currentLevelRows() -> [String] {
        officeMaps[(level - 1) % officeMaps.count]
    }

    private func buildLevel() {
        gridMap.setRows(currentLevelRows())
        mazeBuilder.cubicleColor = cubicleColors[(level - 1) % cubicleColors.count]
        dotCount = mazeBuilder.build(in: self)
        hud.install(in: self)
        spawnCharacters()
        refreshHUD()
        let scheduledLevel = level
        let traveler = currentTraveler()
        travelerSpawner.scheduleVisits(of: traveler) { [weak self] in
            guard let self else { return false }
            return self.level == scheduledLevel && !self.isGameOver
        }
    }

    private func currentTraveler() -> LevelTraveler {
        levelTravelers[(level - 1) % levelTravelers.count]
    }

    private func refreshHUD() {
        if score > highScore { highScore = score }
        hud.updateStatus(score: score, highScore: highScore, level: level, dots: collectedDots, total: dotCount, reports: tpsReportsCreated, items: reportItems)
        hud.updateLives(lives)
        // Ladder resets every 11 levels; Level: counter keeps incrementing.
        let cyclePosition = ((level - 1) % levelTravelers.count) + 1
        let emojis = (0..<cyclePosition).map { levelTravelers[$0].emoji }
        hud.updateLevelEmojis(emojis)
    }

    private func spawnCharacters() {
        workerGrid = workerSpawn

        worker = PixelPerson(
            bodyColor: .systemTeal,
            tieColor: .systemBlue,
            hairColor: NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1),
            walkExaggeration: 1
        )
        worker.name = "PETE"
        worker.position = gridMap.point(for: workerGrid)
        let workerTag = SKLabelNode(fontNamed: "Menlo-Bold")
        workerTag.text = "PETE"
        workerTag.fontSize = 9
        workerTag.fontColor = .white
        workerTag.position = CGPoint(x: 0, y: 24)
        worker.addChild(workerTag)
        worker.physicsBody = SKPhysicsBody(circleOfRadius: 12)
        worker.physicsBody?.allowsRotation = false
        worker.physicsBody?.categoryBitMask = PhysicsCategory.worker
        worker.physicsBody?.contactTestBitMask = PhysicsCategory.dot | PhysicsCategory.boss | PhysicsCategory.machine | PhysicsCategory.tpsBox | PhysicsCategory.powerPellet | PhysicsCategory.fish
        worker.physicsBody?.collisionBitMask = PhysicsCategory.wall
        worker.zPosition = 10
        addChild(worker)

        bosses.removeAll()
        let activeBossCount = min(max(level, 1), bossBlueprints.count)
        for blueprint in bossBlueprints.prefix(activeBossCount) {
            let ai = BossAI(homeGrid: blueprint.spawn, detectionRange: bossDetectionRange, personality: blueprint.personality, pathfinder: pathfinder, map: gridMap)
            ai.teleport(to: blueprint.spawn)

            let node = PixelPerson(
                bodyColor: blueprint.color,
                tieColor: blueprint.tie,
                hairColor: NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.35, alpha: 1),
                shoeOutlineColor: .white,
                pantsColor: blueprint.pants
            )
            node.name = blueprint.name
            node.position = gridMap.point(for: blueprint.spawn)
            node.physicsBody = SKPhysicsBody(circleOfRadius: 13)
            node.physicsBody?.allowsRotation = false
            node.physicsBody?.categoryBitMask = PhysicsCategory.boss
            node.physicsBody?.contactTestBitMask = PhysicsCategory.worker
            node.physicsBody?.collisionBitMask = PhysicsCategory.wall
            node.zPosition = 11
            addChild(node)

            let tag = SKLabelNode(fontNamed: "Menlo-Bold")
            tag.text = blueprint.name
            tag.fontSize = 9
            tag.fontColor = .white
            tag.position = CGPoint(x: 0, y: 24)
            node.addChild(tag)

            // Per-boss timing: slower speed → longer interval & matching animation duration.
            let interval = bossMoveInterval / blueprint.speed
            let duration = bossMoveDuration / blueprint.speed
            bosses.append(BossEntity(
                name: blueprint.name,
                baseColor: blueprint.color,
                tieColor: blueprint.tie,
                pantsColor: blueprint.pants,
                spawn: blueprint.spawn,
                ai: ai,
                node: node,
                tag: tag,
                moveInterval: interval,
                moveDuration: duration,
                lastMove: 0
            ))
        }
    }

    /// Pac-Man turn buffer: at each grid-aligned step, try the queued
    /// direction first; if the corridor is open, adopt it and clear the
    /// queue. Otherwise keep moving in the current direction. The queue
    /// is intentionally NOT cleared when blocked — it persists until the
    /// corresponding path opens up, so a player who pressed Up while
    /// running west will turn the moment a north opening appears.
    private func attemptWorkerStep() {
        if let queued = queuedWorkerDirection,
           gridMap.isWalkable(neighbor(of: workerGrid, in: queued)) {
            workerDirection = queued
            queuedWorkerDirection = nil
        }
        guard let direction = workerDirection else { return }
        let next = neighbor(of: workerGrid, in: direction)
        guard gridMap.isWalkable(next) else {
            worker.stopWalking()
            return
        }
        lastWorkerMove = lastUpdateTime
        let delta = direction.delta
        tryMoveWorker(dx: delta.dx, dy: delta.dy)
    }

    private func neighbor(of grid: CGPoint, in direction: MoveDirection) -> CGPoint {
        let d = direction.delta
        return CGPoint(x: Int(grid.x) + d.dx, y: Int(grid.y) + d.dy)
    }

    private func tryMoveWorker(dx: Int, dy: Int) {
        guard !isWorkerMoving else { return }
        let next = CGPoint(x: Int(workerGrid.x) + dx, y: Int(workerGrid.y) + dy)
        guard gridMap.isWalkable(next) else {
            worker.stopWalking()
            return
        }
        isWorkerMoving = true
        workerGrid = next
        worker.startWalking()
        sound.playFootstep()
        worker.run(.sequence([
            SKAction.move(to: gridMap.point(for: next), duration: workerMoveDuration),
            .run { [weak self] in
                guard let self else { return }
                self.collectDotIfAny(at: next)
                if let partner = self.gridMap.tunnelPartner(of: next),
                   self.gridMap.isWalkable(partner) {
                    self.worker.position = self.gridMap.point(for: partner)
                    self.workerGrid = partner
                    self.collectDotIfAny(at: partner)
                }
                self.isWorkerMoving = false
                self.lastWorkerMove = self.lastUpdateTime
                if !self.isGameOver {
                    self.attemptWorkerStep()
                }
            }
        ]), withKey: "workerMove")
    }

    private func collectDotIfAny(at grid: CGPoint) {
        let column = Int(grid.x)
        let row = Int(grid.y)
        guard mazeBuilder.collectDot(atColumn: column, row: row) else { return }
        collectedDots += 1
        score += 1
        sound.playDotBlip()
        refreshHUD()
        if collectedDots >= dotCount {
            startNextLevel()
        }
    }

    private func stepBosses(currentTime: TimeInterval) {
        for index in bosses.indices {
            if currentTime - bosses[index].lastMove > bosses[index].moveInterval {
                bosses[index].lastMove = currentTime
                stepBoss(at: index)
            }
        }
    }

    private func stepBoss(at index: Int) {
        let boss = bosses[index]
        let blinkyGrid = bosses.first?.ai.grid
        guard let move = boss.ai.planNextStep(workerGrid: workerGrid, workerDirection: workerDirection, blinkyGrid: blinkyGrid, flee: isPowerPelletMode) else {
            boss.node.stopWalking()
            return
        }
        boss.node.startWalking()
        let bossIndex = index
        let isPartnerEdge = abs(move.to.x - move.from.x) + abs(move.to.y - move.from.y) > 1
        if isPartnerEdge {
            boss.node.removeAction(forKey: "bossMove")
            boss.node.position = gridMap.point(for: move.to)
        } else {
            boss.node.run(.sequence([
                SKAction.move(to: gridMap.point(for: move.to), duration: boss.moveDuration),
                .run { [weak self] in
                    guard let self else { return }
                    if let partner = self.gridMap.tunnelPartner(of: move.to),
                       self.gridMap.isWalkable(partner) {
                        self.bosses[bossIndex].node.position = self.gridMap.point(for: partner)
                        self.bosses[bossIndex].ai.teleport(to: partner)
                    }
                }
            ]), withKey: "bossMove")
        }
        if Pathfinder.manhattanDistance(move.to, workerGrid) < 0.5 {
            if isPowerPelletMode {
                captureBoss(at: index)
            } else {
                bossCaughtWorker()
            }
        }
    }

    private func bossCaughtWorker() {
        sound.playCaughtByBoss()
        lives -= 1
        reportItems.removeAll()
        resetGrayedMachines()
        refreshHUD()
        worker.setBodyColor(.systemOrange)
        gameOverFlash = CACurrentMediaTime() + 0.5
        workerGrid = workerSpawn
        for boss in bosses {
            boss.ai.teleport(to: boss.spawn)
            boss.node.removeAllActions()
            boss.node.stopWalking()
            boss.node.run(SKAction.move(to: gridMap.point(for: boss.spawn), duration: 0.2))
        }
        workerDirection = nil
        queuedWorkerDirection = nil
        isWorkerMoving = false
        worker.removeAction(forKey: "workerMove")
        worker.stopWalking()
        worker.run(SKAction.move(to: gridMap.point(for: workerGrid), duration: 0.2))
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
        workerDirection = nil
        queuedWorkerDirection = nil
        isWorkerMoving = false
        worker.removeAllActions()
        worker.stopWalking()
        for boss in bosses {
            boss.node.removeAllActions()
            boss.node.stopWalking()
        }
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
        powerPelletCapturesThisCycle = 0
        reportItems.removeAll()
        workerDirection = nil
        queuedWorkerDirection = nil
        isWorkerMoving = false
        lastWorkerMove = 0
        gameOverFlash = 0
        isPowerPelletMode = false
        powerPelletModeEndsAt = 0
        bosses.removeAll()
        travelerSpawner?.reset()
        removeAllActions()
        removeAllChildren()
        buildLevel()
        hud.showMessage("New game! Collect dots and TPS reports.", duration: 3)
    }

    private func startPowerPelletMode() {
        isPowerPelletMode = true
        powerPelletModeEndsAt = lastUpdateTime + powerPelletDuration
        powerPelletCapturesThisCycle = 0
        for boss in bosses {
            boss.node.setBodyColor(.systemBlue)
        }
        updateBossTags()
        hud.showMessage("Power pellet! Capture the bosses for 20 seconds.", duration: 3)
    }

    private func endPowerPelletMode() {
        isPowerPelletMode = false
        powerPelletModeEndsAt = 0
        powerPelletCapturesThisCycle = 0
        for boss in bosses {
            boss.node.setBodyColor(boss.baseColor)
        }
        updateBossTags()
        hud.showMessage("Power pellet mode ended.", duration: 2)
    }

    private func updateBossTags() {
        if isPowerPelletMode {
            let nextValue = 100 * (powerPelletCapturesThisCycle + 1)
            for boss in bosses {
                boss.tag.text = "\(nextValue)"
                boss.tag.fontColor = .systemYellow
            }
        } else {
            for boss in bosses {
                boss.tag.text = boss.name
                boss.tag.fontColor = .white
            }
        }
    }

    private func captureBoss(at index: Int) {
        let boss = bosses[index]
        powerPelletCapturesThisCycle += 1
        let pointsForThisCapture = 100 * powerPelletCapturesThisCycle
        score += pointsForThisCapture
        sound.playCaptureBoss(streak: powerPelletCapturesThisCycle)
        showScorePopup(pointsForThisCapture, at: boss.node.position)
        boss.ai.teleport(to: boss.spawn)
        boss.node.removeAllActions()
        boss.node.stopWalking()
        boss.node.physicsBody?.categoryBitMask = 0
        let homePoint = gridMap.point(for: boss.spawn)
        let bossNode = boss.node
        bossNode.run(.sequence([
            .group([
                .scale(to: 1.6, duration: 0.25),
                .fadeOut(withDuration: 0.25)
            ]),
            .run { [weak bossNode] in bossNode?.position = homePoint },
            .group([
                .scale(to: 1.0, duration: 0.2),
                .fadeIn(withDuration: 0.2)
            ]),
            .run { [weak bossNode] in
                bossNode?.physicsBody?.categoryBitMask = PhysicsCategory.boss
            }
        ]))
        boss.node.setBodyColor(isPowerPelletMode ? .systemBlue : boss.baseColor)
        updateBossTags()
        refreshHUD()
        hud.showMessage("\(boss.name) captured! +\(pointsForThisCapture)", duration: 2)
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
        if gainedLife {
            hud.showMessage("TPS report delivered! +200, extra worker hired.", duration: 3)
        } else {
            hud.showMessage("TPS report delivered! +200, workers at max.", duration: 3)
        }
    }

    private func startNextLevel() {
        level += 1
        bosses.removeAll()
        travelerSpawner?.reset()
        removeAllActions()
        removeAllChildren()
        reportItems.removeAll()
        workerDirection = nil
        queuedWorkerDirection = nil
        isWorkerMoving = false
        lastWorkerMove = 0
        gameOverFlash = 0
        isPowerPelletMode = false
        powerPelletModeEndsAt = 0
        powerPelletCapturesThisCycle = 0
        collectedDots = 0
        buildLevel()
        sound.playLevelStart()
        hud.showMessage("Level \(level)! New office floor loaded.", duration: 3)
    }
}
