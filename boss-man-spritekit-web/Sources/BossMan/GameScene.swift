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
    private var tpsReportsDelivered = 0
    private let requiredReports = Strings.Machine.required
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

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        anchorPoint = .zero
        // Top-down maze — no gravity. SKPhysicsWorld.contactDelegate gets
        // didBegin for every (categoryBitMask & contactTestBitMask) pair.
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        let rows = Levels.officeMaps.first ?? []
        gridMap = GridMap(tileSize: tileSize, rows: rows)
        pathfinder = Pathfinder(map: gridMap)

        let mazeHeight = CGFloat(gridMap.rowCount) * tileSize
        let mazeWidth  = CGFloat(gridMap.columnCount) * tileSize
        // Reserve the top HUD panel and centre the maze in what's left so
        // labels never sit on top of cubicle tiles (bossman-apple parity).
        let availableHeight = size.height - HUD.panelHeight
        gridMap.yOffset = max(20, (availableHeight - mazeHeight) / 2)
        containerOriginX = max(0, (size.width - mazeWidth) / 2)

        mazeRoot.position = CGPoint(x: containerOriginX, y: 0)
        addChild(mazeRoot)

        mazeBuilder = MazeBuilder(map: gridMap)
        // Per-level cubicle color rotation — bossman-apple GameScene:288.
        mazeBuilder.cubicleColor = SpriteFactory.cubicleColors[
            levelIndex % SpriteFactory.cubicleColors.count]
        dotsRemaining = mazeBuilder.build(in: mazeRoot)
        dotsTotal = dotsRemaining
        goldDiscsRemaining = mazeBuilder.goldDiscPositions.count
        goldDiscsTotal = goldDiscsRemaining

        hud.install(in: self)
        highScore = Persistence.int(forKey: Strings.DefaultsKey.highScore)
        refreshHUD()

        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        pete = SpriteFactory.petePerson()
        pete.zPosition = 5
        // bossman-apple WorkerController.configureNode: circle r=10, worker
        // category, contact-test against every interactable. We use it
        // purely as a contact-sensing body — collisions are off because the
        // TileMover already enforces wall blocking.
        let peteBody = SKPhysicsBody(circleOfRadius: 10)
        peteBody.isDynamic = false
        peteBody.categoryBitMask = PhysicsCategory.worker
        peteBody.contactTestBitMask = PhysicsCategory.fish
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
                                      containerOriginX: containerOriginX)
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
        let local = gridMap.point(for: g)
        return CGPoint(x: local.x + containerOriginX, y: local.y)
    }

    // MARK: - Input

    override func mouseDown(at p: CGPoint) {
        // Route clicks to the username dialog when it's open so the Save /
        // Skip buttons fire even though the rest of the scene is paused.
        if let dialog = usernameDialog {
            dialog.handleMouseDown(at: p)
            return
        }
    }

    override func keyDown(_ key: Int) {
        // Username dialog absorbs every key while open. Returning early
        // also prevents Escape from bouncing us back to the title before
        // the player has typed their name.
        if let dialog = usernameDialog {
            dialog.handleKey(key, shift: false)
            return
        }
        if gameOver { return }
        if key == 36 {        // Escape
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

        // Bill (blueprint 0) is the BLINKY anchor that Bob's flanker
        // personality reflects through. If Bill isn't on the level we
        // pass nil and Bob falls back to direct chase.
        let blinky = bosses.first(where: { $0.blueprintIndex == 0 })?.grid
        for boss in bosses {
            boss.step(dt: dt,
                      peteGrid: peteMover.grid,
                      peteDirection: peteMover.dir,
                      blinkyGrid: blinky)
        }

        stepWaterDroplets(dt: dt)

        if frightenSecondsLeft > 0 {
            frightenSecondsLeft -= TimeInterval(dt)
            if frightenSecondsLeft <= 0 {
                frightenSecondsLeft = 0
                for b in bosses { b.setFrightened(false) }
            }
        }
        if contactCooldown > 0 {
            contactCooldown -= TimeInterval(dt)
        } else if let b = bossOnPete() {
            if b.isFrightened {
                // bossman-apple capture streak: each consecutive boss eaten
                // during the same gold-disc window is worth 100 x streak.
                captureStreak += 1
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
            sound.playGoldDisc()
            hud.flash(Strings.Message.goldDiscActivated, duration: 3)
        }
        if mazeBuilder.collectWaterPellet(at: grid) {
            waterAmmo += waterShotsPerPellet
            sound.playWaterGunPickup()
            refreshHUD()
        }
        if mazeBuilder.collectWaterGun(at: grid) {
            waterAmmo += waterShotsPerGun
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
            let names = missing.compactMap { Strings.Machine.displayName[$0] }.joined(separator: ", ")
            hud.flash(Strings.Message.tpsMissingItems(missing), duration: 3)
            sound.playTpsMissingItems(missing)
            return
        }
        let pts = (levelIndex + 1) * 100 + 100
        score += pts
        ScorePopup.show(pts, at: pos, in: self)
        tpsReportsDelivered += 1
        collectedReports.removeAll()
        mazeBuilder.resetGrayedMachines()    // ready for the next round
        sound.playTpsDeliver()
        hud.flash(Strings.Message.tpsTurnedIn(points: pts), duration: 3)
        refreshHUD()
        // A delivered report can be the last thing keeping the level
        // from completing if Pete already swept the dots + discs.
        checkLevelComplete()
    }

    private func handlePeteHit(catcher: BossController? = nil) {
        lives = max(0, lives - 1)
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
        }
        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        resetPete(to: spawn)
        applyPeteSpawnShield()
        sound.playCaughtByBoss()
    }

    private func resetPete(to spawn: CGPoint) {
        peteMover.grid = spawn
        peteMover.dir = nil
        peteMover.moving = false
        peteMover.moveT = 0
        pete.position = peteMover.centre(of: spawn)
        queued = nil
    }

    private func triggerGameOver() {
        gameOver = true
        peteMover.dir = nil
        queued = nil
        sound.stopMusic()

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

        if score > 0 {
            presentUsernameDialog()
        } else {
            scheduleReturnToTitle(delay: 3.0)
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
                self.scheduleReturnToTitle(delay: 1.2)
            },
            onSkip: { [weak self] in
                guard let self else { return }
                LocalHighScores.submit(name: "ANON", score: self.score)
                self.dismissUsernameDialog()
                self.scheduleReturnToTitle(delay: 1.2)
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

    private func scheduleReturnToTitle(delay: TimeInterval) {
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in self?.returnToTitle() },
        ]))
    }

    private func togglePause() {
        isUserPaused.toggle()
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

        let rows = Levels.officeMaps[levelIndex]
        gridMap.setRows(rows)
        mazeBuilder.cubicleColor = SpriteFactory.cubicleColors[
            levelIndex % SpriteFactory.cubicleColors.count]
        dotsRemaining = mazeBuilder.build(in: mazeRoot)
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
                                      containerOriginX: containerOriginX)
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
            Persistence.set(highScore, forKey: Strings.DefaultsKey.highScore)
        }
        hud.update(score: score, highScore: highScore,
                   level: levelIndex + 1, dotsLeft: dotsRemaining,
                   totalDots: dotsTotal, reports: tpsReportsDelivered)
        hud.update(lives: lives)
        hud.update(ammo: waterAmmo)
        hud.updateTPSChecklist(collected: collectedReports)
    }
}
