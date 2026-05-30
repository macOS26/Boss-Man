import SpriteKit

// Game scene, wasm port — first playable iteration.
//
// What's here:
//   - Load Level 1 from Levels.officeMaps (JSON loaded via SKSceneLoader's
//     asset_text bridge); falls back to the empty-room template if the file
//     isn't reachable.
//   - GridMap + MazeBuilder lay walls, dots, gold discs, water pellets and
//     record spawn positions for Pete (worker) and the four bosses.
//   - Pete (PixelPerson) drops at the workerSpawn tile and moves tile-by-tile,
//     queue-on-press style: pressing a direction sets a pending heading; Pete
//     adopts it the next time he reaches a tile centre and the direction is
//     walkable.
//   - Tunnel wrap: arriving at a tile with a tunnel partner teleports across.
//   - Dot / gold collection is purely visual right now; score / lives HUD
//     lands in task #74.
//   - Bosses, boss AI, contact dispatch, water pistol, gold-disc shielding
//     all queued for the next pass.
//
// Escape returns to the title screen.
final class GameScene: SKScene, SKPhysicsContactDelegate {
    private var gridMap: GridMap!
    private var pathfinder: Pathfinder!
    private var mazeBuilder: MazeBuilder!
    private var pete: PixelPerson!
    private var peteMover: TileMover!
    private let mazeRoot = SKNode()

    // Input buffer: pressing a direction sets `queued`; Pete adopts it the
    // next time the mover hits a tile centre and that direction is walkable.
    private var queued: MoveDirection? = nil
    // Pete's last committed heading, latched (apple's WorkerController.direction
    // is not cleared on a wall hit). Fed to the bosses so ambush/flanker keep
    // projecting ahead when Pete is blocked. Reset on respawn.
    private var lastPeteDir: MoveDirection? = nil
    private var swipeStart: CGPoint? = nil
    private var swipeFired = false
    private var moveAnchor: CGPoint? = nil
    private let swipeThreshold: CGFloat = 24
    private var fireButtonCenter = CGPoint.zero
    private let fireButtonRadius: CGFloat = 38
    private let peteStep: TimeInterval = 0.13   // ~7.7 tiles/s
    private let tileSize: CGFloat = 32
    private var containerOriginX: CGFloat = 0

    private let hud = HUD()
    private let sound = SoundManager()
    private let state = RoundState()
    private var travelerSpawner: TravelerSpawner!
    private var score = 0
    private var highScore = 0
    private var lives = 3
    private var levelIndex = 0
    // Set by the level editor's PLAY button: start on the edited level and
    // don't persist the score. startingLevel is 1-based (matches the editor).
    var practiceMode = false
    var startingLevel = 1
    private var dotsRemaining = 0
    private var dotsTotal     = 0
    private let dotPoints = 10
    private let goldPoints = 200

    private var bosses: [BossController] = []
    private var contactCooldown: TimeInterval = 0     // brief grace after a hit
    private var peteShielded: Bool = false             // bossman-apple's WorkerController.isShielded
    // Gold-disc (frighten) window — bossman-apple uses 20s.
    private var frightenSecondsLeft: TimeInterval = 0
    private let frightenDuration: TimeInterval = 20
    // Capture streak: bossman-apple awards 100 * streak per consecutive
    // boss captured during the SAME gold-disc window. Resets when a new
    // window starts.
    private var captureStreak = 0
    // Tracks how many gold discs Pete has collected this level vs how
    // many exist on the maze; both have to hit equality to clear it.
    private var goldDiscsRemaining = 0
    private var goldDiscsTotal = 0

    // TPS report tracking, mirroring bossman-apple's RoundState.reportItems
    // + tpsReportsDelivered. Indexes into reportItemPoints award 10/25/50/100
    // per collected item; the brown box turns them in for level*100+100.
    private var collectedReports: Set<String> = []
    // bossman-apple RoundState.currentReportScore: total value of items collected
    // toward the current TPS report; forfeited (red popup) if a boss catches Pete.
    private var currentReportScore = 0
    private var tpsReportsDelivered = 0
    private let requiredReports = Strings.Machine.required
    private let squareTracks = Persistence.bool(forKey: Strings.DefaultsKey.bossTracksSquare)
    private let reportItemPoints = [10, 25, 50, 100]

    private var waterAmmo: Int = 0
    private var waterDroplets: [WaterDroplet] = []
    private let waterShotsPerPellet = 5
    private let waterShotsPerGun    = 10
    private let waterDropletSpeed: CGFloat = 12 * 32     // 12 tiles/s
    private let waterHitPoints = 100

    private var gameOver = false
    private var isUserPaused = false
    private var pauseOverlay: SKNode? = nil
    private var usernameDialog: UsernameDialog? = nil

    override func willMove(from view: SKView) {
        // Guaranteed teardown: stop music + speech so this scene's looping
        // music voice never outlives it and stacks under the next game's
        // music (the choppy-on-restart bug).
        sound.stopAllAudio()
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        anchorPoint = .zero
        // Top-down maze — no gravity. SKPhysicsWorld.contactDelegate gets
        // didBegin for every (categoryBitMask & contactTestBitMask) pair.
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        levelIndex = max(0, min(startingLevel - 1, Levels.names.count - 1))
        let rows = LevelStore.loadLevel(index: levelIndex)
        gridMap = GridMap(tileSize: tileSize, rows: rows)
        pathfinder = Pathfinder(map: gridMap)

        let mazeHeight = CGFloat(gridMap.rowCount) * tileSize
        let mazeWidth  = CGFloat(gridMap.columnCount) * tileSize
        // Reserve the top HUD panel and centre the maze in what's left so
        // labels never sit on top of cubicle tiles (bossman-apple parity).
        let availableHeight = size.height - HUD.panelHeight
        gridMap.yOffset = max(20, (availableHeight - mazeHeight) / 2)
        // Horizontal centering now lives in gridMap.xOffset (mirrors yOffset),
        // so gridMap.point(for:) returns final centred coords for tiles, Pete,
        // and bosses alike — and apple's WorkerController drops in unchanged.
        gridMap.xOffset = max(0, (size.width - mazeWidth) / 2)
        containerOriginX = gridMap.xOffset

        mazeRoot.position = .zero
        addChild(mazeRoot)

        mazeBuilder = MazeBuilder(map: gridMap)
        // Per-level cubicle color rotation — bossman-apple GameScene:288.
        mazeBuilder.cubicleColor = SpriteFactory.cubicleColors[
            levelIndex % SpriteFactory.cubicleColors.count]
        dotsRemaining = mazeBuilder.build(in: mazeRoot, view: view)
        dotsTotal = dotsRemaining
        goldDiscsRemaining = mazeBuilder.goldDiscPositions.count
        goldDiscsTotal = goldDiscsRemaining

        hud.install(in: self)
        highScore = Persistence.int(forKey: Strings.DefaultsKey.highScore)
        refreshHUD()

        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        pete = SpriteFactory.petePerson()
        pete.zPosition = 5
        // bossman-apple WorkerController: "PETE" name tag, Menlo-Bold 9, white,
        // 24pt above center.
        let peteTag = SKLabelNode(fontNamed: Strings.Font.menloBold)
        peteTag.text = Strings.Worker.pete
        peteTag.fontSize = 9
        peteTag.fontColor = .white
        peteTag.position = CGPoint(x: 0, y: 24)
        pete.addChild(peteTag)
        // Verbatim from bossman-apple WorkerController.configureNode
        // (lines 40-44): circle r=10, worker category, contact-test
        // against everything Pete interacts with, collision against
        // walls. The body is plain dynamic (default) — no sensor flag,
        // no kinematic gymnastics. SuperBox64 SpriteKit auto-syncs
        // node.position into Box2D each frame, so the TileMover-driven
        // position drives the body's world location.
        let peteBody = SKPhysicsBody(circleOfRadius: 10)
        peteBody.allowsRotation = false
        peteBody.categoryBitMask = PhysicsCategory.worker
        peteBody.contactTestBitMask =
            PhysicsCategory.dot | PhysicsCategory.boss |
            PhysicsCategory.machine | PhysicsCategory.tpsBox |
            PhysicsCategory.goldDisc | PhysicsCategory.fish |
            PhysicsCategory.waterGun | PhysicsCategory.waterPellet
        // No collision resolution: Pete's tile stepper already keeps him out of
        // walls, and letting Box2D push a directly-positioned dynamic body
        // produced micro-jitter. Contacts still fire via contactTestBitMask.
        peteBody.collisionBitMask = 0
        pete.physicsBody = peteBody
        addChild(pete)
        peteMover = TileMover(node: pete, spawn: spawn, map: gridMap,
                              step: peteStep, containerOriginX: containerOriginX)

        for (index, bossSpawn) in mazeBuilder.bossSpawns.enumerated() {
            let boss = BossController(blueprintIndex: bossSpawn.index,
                                      spawn: bossSpawn.position,
                                      map: gridMap,
                                      pathfinder: pathfinder,
                                      tileSize: tileSize,
                                      containerOriginX: containerOriginX,
                                      squareTracks: squareTracks,
                                      mib: (levelIndex + 1) % 12 == 0)
            boss.install(in: self)
            bosses.append(boss)
            _ = index
        }

        travelerSpawner = TravelerSpawner(scene: self,
                                          gridMap: gridMap,
                                          sound: sound,
                                          containerOriginX: containerOriginX)
        scheduleTravelerForCurrentLevel()
        hud.update(travelers: unlockedTravelers())
        // bossman-apple: startBackgroundMusic(theme:) on level load.
        // Every 12th level switches to the MIB ("Sunglasses At Night") theme.
        sound.startMusic(musicTheme(for: levelIndex + 1))
        sound.playLevelStart()
        installFireButton()
        if practiceMode { hud.flash(Strings.Message.practiceMode, duration: 3) }
    }

    // MARK: - Touch / trackpad controls (mobile)

    // A round translucent fire button in the bottom-right. Tapping it fires the
    // water gun; a swipe anywhere else steers Pete (see mouseDown/Moved/Up).
    // A virtual joystick may join it on the left side later.
    private func installFireButton() {
        let onLeft = Persistence.bool(forKey: Strings.DefaultsKey.waterGunLeft)
        fireButtonCenter = CGPoint(x: onLeft ? 64 : size.width - 64, y: 72)
        let ring = SKShapeNode(circleOfRadius: fireButtonRadius)
        ring.position = fireButtonCenter
        ring.fillColor = SKColor(white: 1, alpha: 0.14)
        ring.strokeColor = SKColor(white: 1, alpha: 0.5)
        ring.lineWidth = 2
        ring.zPosition = 50
        let core = SKShapeNode(circleOfRadius: fireButtonRadius * 0.34)
        core.fillColor = SKColor(red: 0.40, green: 0.70, blue: 1.0, alpha: 0.6)
        core.strokeColor = .clear
        core.zPosition = 51
        ring.addChild(core)
        addChild(ring)
    }

    // A swipe (touch / mouse click-drag) or a bare trackpad slide resolves to
    // one cardinal direction once it clears the threshold. Latched through the
    // same `queued` path an arrow key uses.
    private func swipeDirection(_ dx: CGFloat, _ dy: CGFloat) -> MoveDirection? {
        guard max(abs(dx), abs(dy)) >= swipeThreshold else { return nil }
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .up : .down            // scene is y-up: swipe up => +y
    }

    private func steer(_ dir: MoveDirection) {
        queued = dir
        pete?.setFacing(dir)
    }

    // bossman-apple SoundManager: every 12th level uses the alternate
    // MIB theme. level here is 1-indexed (the displayed level number).
    private func musicTheme(for level: Int) -> SoundManager.MusicTheme {
        level % 12 == 0 ? .mib : .normal
    }

    private func currentTraveler() -> LevelTraveler {
        levelTravelers[levelIndex % levelTravelers.count]
    }

    // Verbatim port of bossman-apple's refreshHUD: cyclePosition = ((level-1)
    // % count) + 1, then Array(levelTravelers.prefix(cyclePosition)). Level 1
    // -> just the fish; later levels add one glyph each until the cycle
    // wraps. Right-justified by the HUD container's positioning math.
    private func unlockedTravelers() -> [LevelTraveler] {
        let cyclePosition = (levelIndex % levelTravelers.count) + 1
        return Array(levelTravelers.prefix(cyclePosition))
    }

    private func scheduleTravelerForCurrentLevel() {
        travelerSpawner.scheduleVisits(of: currentTraveler(),
                                       whileActive: { [weak self] in
                                           guard let self else { return false }
                                           return !self.gameOver && !self.isUserPaused
                                       })
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
    // Pete-spawn falls through to firstWalkableCell which skips hideouts —
    // we want Pete to start in the open, not in a corner alcove.


    // Convert a grid cell to a scene-space coordinate (including the maze
    // root's horizontal offset that centres the maze in the scene).
    private func sceneCoord(forGrid g: CGPoint) -> CGPoint {
        gridMap.point(for: g)
    }

    // MARK: - Input

    override func mouseDown(at p: CGPoint) {
        // Route clicks to the username dialog when it's open so the Save /
        // Skip buttons fire even though the rest of the scene is paused.
        if let dialog = usernameDialog {
            dialog.handleMouseDown(at: p)
            return
        }
        if gameOver || isUserPaused { return }
        moveAnchor = p
        // Tap the round button => fire; press anywhere else begins a swipe.
        if fireButtonCenter.distance(to: p) <= fireButtonRadius {
            fireWater()
            swipeStart = nil
            return
        }
        swipeStart = p
        swipeFired = false
    }

    override func mouseMoved(to p: CGPoint) {
        if gameOver || isUserPaused { moveAnchor = p; return }
        // Button held (touch drag or mouse click-drag): resolve vs the press origin.
        if let start = swipeStart {
            if !swipeFired, let d = swipeDirection(p.x - start.x, p.y - start.y) {
                steer(d); swipeFired = true
            }
            return
        }
        // Bare trackpad slide (no button down) steers toward sustained motion;
        // re-anchor each time so a continued slide keeps issuing directions.
        guard let anchor = moveAnchor else { moveAnchor = p; return }
        if let d = swipeDirection(p.x - anchor.x, p.y - anchor.y) {
            steer(d); moveAnchor = p
        }
    }

    override func mouseUp(at p: CGPoint) {
        if let start = swipeStart, !swipeFired, !gameOver, !isUserPaused,
           let d = swipeDirection(p.x - start.x, p.y - start.y) {
            steer(d)
        }
        swipeStart = nil
        moveAnchor = p
    }

    override func keyDown(_ key: Int) {
        // Username dialog absorbs every key while open. Returning early
        // also prevents Escape from bouncing us back to the title before
        // the player has typed their name.
        if let dialog = usernameDialog {
            dialog.handleKey(key, shift: false)
            return
        }
        if gameOver {
            // bossman-apple keeps the GAME OVER card over the live scene and
            // waits for the player: P starts a new game, Esc returns to title.
            if key == 15 { restartGame() }
            else if key == 36 { returnToTitle() }
            return
        }
        if key == 36 {        // Escape
            sound.stopAllAudio()
            let title = TitleScene(size: size)
            title.scaleMode = .aspectFit
            view?.presentScene(title, transition: .fade(withDuration: 0.4))
            return
        }
        if key == 15 {        // P toggles pause
            togglePause()
            return
        }
        if isUserPaused { return }   // ignore movement / fire while paused
        if key == 57 {                              // Space — fire water
            fireWater()
            return
        }
        if let dir = MoveDirection(keyCode: key) {
            queued = dir
            pete?.setFacing(dir)
        }
    }

    private func fireWater() {
        guard waterAmmo > 0, let h = peteMover.dir ?? queued else { return }
        // bossman-apple disables the water gun while the gold-disc window
        // is active — players can't double-dip on power-ups.
        if frightenSecondsLeft > 0 {
            hud.flash(Strings.Message.waterGunBlueMode, duration: 2)
            return
        }
        waterAmmo -= 1
        let drop = WaterDroplet(direction: h, speed: waterDropletSpeed)
        drop.position = pete.position
        drop.zPosition = 6
        addChild(drop)
        waterDroplets.append(drop)
        sound.playWaterGunShoot()
        refreshHUD()
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard pete != nil, peteMover != nil else { return }
        if gameOver || isUserPaused { return }
        let dt: TimeInterval = 1.0 / 60.0

        // Time-based tile stepper: when Pete reaches a tile centre, decide()
        // picks the next direction (queued > current); the mover lerps to the
        // next tile over `peteStep` seconds with the lerp parameter clamped
        // 0..1 — so overshoot vibration is impossible. onArrive runs the
        // pickup/level/respawn bookkeeping in scene coords.
        let decide: (TileMover) -> MoveDirection? = { [weak self] e in
            guard let self else { return nil }
            if let q = self.queued, e.canStep(q) { return q }
            if let d = e.dir, e.canStep(d) { return d }
            return nil
        }
        let onArrive: (TileMover) -> Void = { [weak self] e in
            guard let self else { return }
            self.handlePeteArrival(at: e.grid)
            if let d = e.dir { self.pete?.setFacing(d) }
        }
        peteMover.advance(dt, decide: decide, onArrive: onArrive)
        // bossman-apple latches workerDirection: it is NOT cleared when Pete is
        // held against a wall, so Dom (ambush) and Bob (flanker) keep projecting
        // along Pete's last heading instead of collapsing to direct chase.
        if let d = peteMover.dir { lastPeteDir = d }

        // BLINKY anchor for Bob's flanker reflection = the FIRST-SPAWNED boss
        // (bossman-apple's entities.first), in maze scan order — NOT necessarily
        // Bill. bosses[] is built in bossSpawns scan order, so bosses.first matches.
        let blinky = bosses.first?.grid
        for boss in bosses {
            boss.step(dt: dt,
                      peteGrid: peteMover.grid,
                      peteDirection: lastPeteDir,
                      blinkyGrid: blinky)
        }

        stepWaterDroplets(dt: dt)

        if frightenSecondsLeft > 0 {
            frightenSecondsLeft -= TimeInterval(dt)
            if frightenSecondsLeft <= 0 {
                frightenSecondsLeft = 0
                for b in bosses { b.setFrightened(false) }
                refreshBossTags()
                sound.stopGoldDiscBass()
            }
        }
        if contactCooldown > 0 {
            contactCooldown -= TimeInterval(dt)
        } else if let b = bossOnPete() {
            if b.isFrightened {
                // bossman-apple capture streak: each consecutive boss eaten
                // during the same gold-disc window is worth 100 x streak.
                captureStreak += 1
                refreshBossTags()
                let points = 100 * captureStreak
                score += points
                refreshHUD()
                ScorePopup.show(points, at: b.sprite.position, in: self,
                                color: SKColor(red: 0.3, green: 0.7, blue: 1, alpha: 1))
                sound.playCaptureBoss(streak: captureStreak)
                // Scale-up + fade-out, snap home, scale-down + fade-in.
                b.capture()
                contactCooldown = 0.4
            } else if !peteShielded {
                handlePeteHit(catcher: b)
            }
        }
    }

    private func bossOnPete() -> BossController? {
        let r = tileSize * 0.55
        let r2 = r * r
        for b in bosses {
            if b.isImmobilized { continue }    // freezed-spawn bosses can't catch
            let dx = b.sprite.position.x - pete.position.x
            let dy = b.sprite.position.y - pete.position.y
            if dx * dx + dy * dy < r2 { return b }
        }
        return nil
    }

    // bossman-apple's WorkerController.applySpawnShield. Pete is invulnerable
    // for ~3s after a respawn, with a fade-in-fade-out blink so the player
    // sees the grace window.
    private func applyPeteSpawnShield() {
        peteShielded = true
        pete.removeAction(forKey: Strings.ActionKey.spawnShield)
        pete.removeAction(forKey: Strings.ActionKey.spawnShieldBlink)
        pete.alpha = 1
        let blinkCycle = SKAction.sequence([
            .fadeAlpha(to: 0.35, duration: 0.6),
            .fadeAlpha(to: 1.0,  duration: 0.6),
        ])
        pete.run(.sequence([
            .repeat(blinkCycle, count: 2),
            .run { [weak self] in self?.pete?.alpha = 1 }
        ]), withKey: Strings.ActionKey.spawnShieldBlink)
        pete.run(.sequence([
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.peteShielded = false }
        ]), withKey: Strings.ActionKey.spawnShield)
    }

    // Called by the TileMover when Pete snaps to a new tile centre — picks
    // up dots/gold/water-pickups and fires the level transition. The mover
    // already handles tunnel wrap before this runs, so `grid` is the final
    // post-wrap cell.
    private func handlePeteArrival(at grid: CGPoint) {
        if mazeBuilder.collectDot(at: grid) {
            score += dotPoints
            dotsRemaining = max(0, dotsRemaining - 1)
            sound.playDotBlip()
            refreshHUD()
            checkLevelComplete()
        }
        if mazeBuilder.collectGold(at: grid) {
            score += goldPoints
            goldDiscsRemaining = max(0, goldDiscsRemaining - 1)
            // bossman-apple resets the capture streak when a NEW gold-disc
            // window opens, so the first eaten boss is worth 100 again.
            captureStreak = 0
            refreshHUD()
            ScorePopup.show(goldPoints, at: peteMover.centre(of: grid), in: self)
            frightenSecondsLeft = frightenDuration
            for b in bosses { b.setFrightened(true) }
            refreshBossTags()
            sound.playGoldDisc()
            sound.startGoldDiscBass()
            hud.flash(Strings.Message.goldDiscActivated, duration: 3)
        }
        if mazeBuilder.collectWaterPellet(at: grid) {
            waterAmmo += waterShotsPerPellet
            score += 50
            ScorePopup.show(50, at: peteMover.centre(of: grid), in: self)
            sound.playWaterGunPickup()
            refreshHUD()
        }
        if mazeBuilder.collectWaterGun(at: grid) {
            waterAmmo += waterShotsPerGun
            score += 75
            ScorePopup.show(75, at: peteMover.centre(of: grid), in: self)
            sound.playWaterGunPickup()
            refreshHUD()
            hud.flash(Strings.Message.waterGunActivated, duration: 3)
        }
        // Traveler catch is fired by SKPhysicsContactDelegate.didBegin now,
        // not by tile-arrival — the Box2D contact reports the instant
        // Pete's worker body overlaps the fish body, regardless of which
        // tile either one is animating between.
        if let machine = mazeBuilder.collectMachine(at: grid),
           requiredReports.contains(machine.name),
           !collectedReports.contains(machine.name) {
            collectedReports.insert(machine.name)
            let idx = collectedReports.count - 1
            let pts = idx < reportItemPoints.count ? reportItemPoints[idx] : 100
            score += pts
            currentReportScore += pts
            ScorePopup.show(pts, at: machine.position, in: self)
            sound.playMachine(named: machine.name)
            refreshHUD()
            if collectedReports.count == requiredReports.count {
                hud.flash(Strings.Message.tpsReportReady, duration: 3)
            } else {
                let display = Strings.Machine.displayName[machine.name] ?? machine.name
                hud.flash(Strings.Message.reportItemCollected(name: display, points: pts), duration: 2)
            }
        }
        if let boxPos = mazeBuilder.touchedBrownBox(at: grid) {
            collectTPSReport(at: boxPos)
        }
    }

    // MARK: - SKPhysicsContactDelegate
    // bossman-apple wires this through ContactRouter; bossman-web routes
    // the same contacts directly. didBegin fires once per
    // (categoryBitMask & contactTestBitMask) match.
    func didBegin(_ contact: SKPhysicsContact) {
        if gameOver { return }
        let bodies = [contact.bodyA, contact.bodyB]
        let hasWorker = bodies.contains { $0.categoryBitMask == PhysicsCategory.worker }
        if hasWorker, let fishBody = bodies.first(where: { $0.categoryBitMask == PhysicsCategory.fish }),
           let fishNode = fishBody.node {
            handleTravelerCaught(node: fishNode)
        }
    }

    private func handleTravelerCaught(node: SKNode) {
        guard let active = travelerSpawner.activeNode, active === node,
              let traveler = travelerSpawner.activeTraveler else { return }
        let info = travelerSpawner.consumeCatch(fish: node, traveler: traveler)
        score += info.traveler.points
        ScorePopup.show(info.traveler.points, at: info.position, in: self,
                        color: SKColor(red: 1.0, green: 0.91, blue: 0.34, alpha: 1))
        sound.playFishOrTreat()
        refreshHUD()
    }

    // bossman-apple's checkLevelComplete: a level only advances when ALL
    // three conditions hold. Otherwise show a hint so the player knows
    // they still have a TPS report to deliver.
    private func checkLevelComplete() {
        let dotsDone = dotsRemaining == 0
        let discsDone = goldDiscsRemaining == 0
        guard dotsDone && discsDone else { return }
        if tpsReportsDelivered >= 1 {
            advanceLevel()
        } else if dotsDone {
            // Pete swept the floor but no TPS report yet — nudge them.
            hud.flash(Strings.Message.needTPSReport, duration: 3)
        }
    }

    // bossman-apple's collectTPSReport — when Pete touches the brown box
    // with all four items collected, turn them in for level*100+100,
    // bump the report counter, clear the set. Missing items just shows a
    // message.
    private func collectTPSReport(at pos: CGPoint) {
        guard collectedReports.count == requiredReports.count else {
            let missing = requiredReports.filter { !collectedReports.contains($0) }
            hud.flash(Strings.Message.tpsMissingItems(missing), duration: 3)
            sound.playTpsMissingItems(missing)
            return
        }
        // bossman-apple GameScene.collectTPSReport:342 — points scale with
        // the level (state.level * 100 + 100). At level 1: 200, level 2:
        // 300, etc.
        let pts = (levelIndex + 1) * 100 + 100
        score += pts
        ScorePopup.show(pts, at: pos, in: self)
        tpsReportsDelivered += 1
        collectedReports.removeAll()
        currentReportScore = 0
        mazeBuilder.resetGrayedMachines()    // ready for the next round
        // bossman-apple GameScene.collectTPSReport:350-351 — Pete is hired
        // an extra worker on delivery, capped at HUD.maxLives.
        let gainedLife = lives < HUD.maxLives
        if gainedLife { lives += 1 }
        sound.playTpsDeliver()
        hud.flash(Strings.Message.tpsTurnedIn(points: pts, gainedLife: gainedLife),
                  duration: 3)
        refreshHUD()
        // A delivered report can be the last thing keeping the level
        // from completing if Pete already swept the dots + discs.
        checkLevelComplete()
    }

    private func handlePeteHit(catcher: BossController? = nil) {
        lives = max(0, lives - 1)
        // bossman-apple bossCaughtWorker: a catch forfeits the in-progress TPS
        // report — flash its value in red, clear the collected items, and
        // re-enable the machines so they can be collected again.
        if currentReportScore > 0 {
            ScorePopup.show(-currentReportScore, at: pete.position, in: self,
                            color: SKColor(red: 1, green: 0.23, blue: 0.19, alpha: 1))
        }
        currentReportScore = 0
        collectedReports.removeAll()
        mazeBuilder.resetGrayedMachines()
        refreshHUD()
        if lives == 0 {
            triggerGameOver()
            return
        }
        hud.flash(Strings.Message.bossCaughtYou(lives), duration: 3)
        contactCooldown = 1.2
        // bossman-apple bossCaughtWorker flow: every boss is sent home
        // and runs the full applySpawnFreeze sequence (1.5s fade-in +
        // 2s immobilized + 3 throb pulses). The boss that actually
        // touched Pete additionally has its alpha snapped to 0 first
        // via relocateAfterCatch so Pete can't get re-tagged on the
        // same contact frame.
        catcher?.relocateAfterCatch()
        for b in bosses { b.respawnAfterPeteCaught() }
        // Apple also ends a gold-disc window early on a catch and
        // bails out of any in-progress capture streak.
        if frightenSecondsLeft > 0 {
            frightenSecondsLeft = 0
            for b in bosses { b.setFrightened(false) }
            captureStreak = 0
            refreshBossTags()
            sound.stopGoldDiscBass()
        }
        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        resetPete(to: spawn)
        applyPeteSpawnShield()
        sound.playCaughtByBoss()
    }

    private func resetPete(to spawn: CGPoint) {
        peteMover.grid = spawn
        peteMover.dir = nil
        lastPeteDir = nil
        peteMover.moving = false
        peteMover.moveT = 0
        pete.position = peteMover.centre(of: spawn)
        queued = nil
    }

    private func triggerGameOver() {
        gameOver = true
        peteMover.dir = nil
        lastPeteDir = nil
        queued = nil
        sound.stopAllAudio()

        // bossman-apple HUD.showGameOver: translucent dim, orange-bordered
        // central card, big red GAME OVER + pulsing prompt + "PRESS ESC".
        hud.showGameOver(in: self)

        let summary = SKLabelNode(fontNamed: Strings.Font.menloBold)
        summary.text = "FINAL SCORE \(score)   HIGH \(highScore)"
        summary.fontSize = 22
        summary.fontColor = .white
        summary.position = CGPoint(x: size.width / 2, y: size.height / 2 - 100)
        summary.zPosition = 102
        addChild(summary)

        // bossman-apple does NOT auto-transition on game over: the dim GAME
        // OVER card sits on top of the still-live maze and every sprite stays
        // on the board until the player presses P (new game) or Esc (title).
        if score > 0 && !practiceMode {
            presentUsernameDialog()
        }
    }

    private func presentUsernameDialog() {
        let dialog = UsernameDialog(
            size: CGSize(width: 360, height: 220),
            fontName: Strings.Font.menloBold,
            onConfirm: { [weak self] name in
                guard let self else { return }
                LocalHighScores.submit(name: name, score: self.score)
                self.dismissUsernameDialog()
            },
            onSkip: { [weak self] in
                guard let self else { return }
                LocalHighScores.submit(name: "ANON", score: self.score)
                self.dismissUsernameDialog()
            }
        )
        dialog.position = CGPoint(x: size.width / 2, y: size.height * 0.40)
        dialog.zPosition = 200
        addChild(dialog)
        usernameDialog = dialog
    }

    private func dismissUsernameDialog() {
        usernameDialog?.removeFromParent()
        usernameDialog = nil
    }

    private func restartGame() {
        sound.stopAllAudio()
        let game = GameScene(size: size)
        game.scaleMode = .aspectFit
        view?.presentScene(game, transition: .fade(withDuration: 0.4))
    }

    private func togglePause() {
        isUserPaused.toggle()
        if isUserPaused { sound.pauseAudio() } else { sound.resumeAudio() }
        // bossman-apple sets the scene's isPaused so SpriteKit freezes every
        // running action. SuperBox64's stepActions scales each subtree by
        // node.speed, so speed = 0 on the scene halts ALL animations (walk
        // cycles, boss throb, blinks) at once; 1 resumes them.
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
    }

    private func returnToTitle() {
        sound.stopAllAudio()
        let title = TitleScene(size: size)
        title.scaleMode = .aspectFit
        view?.presentScene(title, transition: .fade(withDuration: 0.5))
    }

    private func advanceLevel() {
        levelIndex = (levelIndex + 1) % max(1, Levels.officeMaps.count)
        hud.flash(Strings.Message.levelLoaded(levelIndex + 1), duration: 3)
        sound.startMusic(musicTheme(for: levelIndex + 1))
        sound.playLevelStart()

        for boss in bosses { boss.sprite.removeFromParent() }
        bosses.removeAll()
        mazeRoot.removeAllChildren()
        travelerSpawner.reset()

        let rows = LevelStore.loadLevel(index: levelIndex)
        gridMap.setRows(rows)
        mazeBuilder.cubicleColor = SpriteFactory.cubicleColors[
            levelIndex % SpriteFactory.cubicleColors.count]
        dotsRemaining = mazeBuilder.build(in: mazeRoot, view: view)
        dotsTotal = dotsRemaining
        goldDiscsRemaining = mazeBuilder.goldDiscPositions.count
        goldDiscsTotal = goldDiscsRemaining
        tpsReportsDelivered = 0
        // Each level starts a fresh TPS round, matching bossman-apple's
        // RoundState.advanceLevel reset.
        collectedReports.removeAll()
        scheduleTravelerForCurrentLevel()
        hud.update(travelers: unlockedTravelers())

        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        resetPete(to: spawn)

        for bossSpawn in mazeBuilder.bossSpawns {
            let boss = BossController(blueprintIndex: bossSpawn.index,
                                      spawn: bossSpawn.position,
                                      map: gridMap,
                                      pathfinder: pathfinder,
                                      tileSize: tileSize,
                                      containerOriginX: containerOriginX,
                                      squareTracks: squareTracks,
                                      mib: (levelIndex + 1) % 12 == 0)
            boss.install(in: self)
            bosses.append(boss)
        }

        refreshHUD()
    }

    private func stepWaterDroplets(dt: TimeInterval) {
        guard !waterDroplets.isEmpty else { return }
        var i = waterDroplets.count - 1
        while i >= 0 {
            let drop = waterDroplets[i]
            let expired = drop.step(dt: dt)
            var consumed = expired

            if !consumed {
                let g = gridCellAtScenePoint(drop.position)
                if !gridMap.isWalkable(g) { consumed = true }
                else {
                    for b in bosses {
                        let dx = b.sprite.position.x - drop.position.x
                        let dy = b.sprite.position.y - drop.position.y
                        if dx * dx + dy * dy < (tileSize * 0.45) * (tileSize * 0.45) {
                            score += waterHitPoints
                            ScorePopup.show(waterHitPoints, at: b.sprite.position, in: self,
                                            color: SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1))
                            spawnWaterSplash(at: b.sprite.position)
                            sound.playWaterGunSplash()
                            // bossman-apple: boss disappears for 5s,
                            // then spawn-freeze fades it back in.
                            b.splash()
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
    // Quick water-splash animation: six expanding droplets around the hit
    // point, fading out over 0.4s. Matches bossman-apple's splash burst.
    private func spawnWaterSplash(at p: CGPoint) {
        let burst = SKNode()
        burst.position = p
        burst.zPosition = 8
        addChild(burst)
        let droplets = 6
        let dist: CGFloat = tileSize * 0.45
        // Hand-rolled (cos, sin) for the six directions so we don't drag in
        // libm import on wasm. Six unit vectors spaced 60° apart.
        let unit: [(CGFloat, CGFloat)] = [
            ( 1.0,  0.0),
            ( 0.5,  0.866025),
            (-0.5,  0.866025),
            (-1.0,  0.0),
            (-0.5, -0.866025),
            ( 0.5, -0.866025),
        ]
        for i in 0..<droplets {
            let (ux, uy) = unit[i]
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
    }

    private func gridCellAtScenePoint(_ p: CGPoint) -> CGPoint {
        let localX = p.x - containerOriginX
        let col = Int((localX) / tileSize)
        let row = Int((p.y - gridMap.yOffset) / tileSize)
        return CGPoint(x: col, y: row)
    }

    private func refreshHUD() {
        if score > highScore {
            highScore = score
            if !practiceMode {
                Persistence.set(highScore, forKey: Strings.DefaultsKey.highScore)
            }
        }
        hud.update(score: score, highScore: highScore,
                   level: levelIndex + 1, dotsLeft: dotsRemaining,
                   totalDots: dotsTotal, reports: tpsReportsDelivered)
        hud.update(lives: lives)
        hud.update(ammo: waterAmmo)
        hud.updateTPSChecklist(collected: collectedReports)
    }

    // bossman-apple refreshTags(goldDiscActive:): the next-capture value is
    // 100 * (captureStreak + 1); each boss shows it (yellow) while frightened,
    // else its name (white).
    private func refreshBossTags() {
        let next = 100 * (captureStreak + 1)
        for b in bosses { b.refreshTag(nextPoints: next) }
    }
}
