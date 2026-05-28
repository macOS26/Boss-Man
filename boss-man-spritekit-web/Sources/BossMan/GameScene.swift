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
final class GameScene: SKScene {
    private var gridMap: GridMap!
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
    private var frightenSecondsLeft: TimeInterval = 0
    private let frightenDuration: TimeInterval = 6
    private let eatBossPoints = 500

    private var waterAmmo: Int = 0
    private var waterDroplets: [WaterDroplet] = []
    private let waterShotsPerPellet = 5
    private let waterShotsPerGun    = 10
    private let waterDropletSpeed: CGFloat = 12 * 32     // 12 tiles/s
    private let waterHitPoints = 100

    private var gameOver = false
    private var isUserPaused = false
    private var pauseOverlay: SKNode? = nil

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        anchorPoint = .zero

        let rows = Levels.officeMaps.first ?? []
        gridMap = GridMap(tileSize: tileSize, rows: rows)

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
        dotsRemaining = mazeBuilder.build(in: mazeRoot)
        dotsTotal = dotsRemaining

        hud.install(in: self)
        highScore = Persistence.int(forKey: Strings.DefaultsKey.highScore)
        refreshHUD()

        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        pete = SpriteFactory.petePerson()
        pete.zPosition = 5
        addChild(pete)
        peteMover = TileMover(node: pete, spawn: spawn, map: gridMap,
                              step: peteStep, containerOriginX: containerOriginX)

        for (index, bossSpawn) in mazeBuilder.bossSpawns.enumerated() {
            let boss = BossController(blueprintIndex: bossSpawn.index,
                                      spawn: bossSpawn.position,
                                      map: gridMap,
                                      tileSize: tileSize,
                                      containerOriginX: containerOriginX)
            boss.install(in: self)
            bosses.append(boss)
            _ = index
        }
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

    override func keyDown(_ key: Int) {
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
        waterAmmo -= 1
        let drop = WaterDroplet(direction: h, speed: waterDropletSpeed)
        drop.position = pete.position
        drop.zPosition = 6
        addChild(drop)
        waterDroplets.append(drop)
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

        for boss in bosses { boss.step(dt: dt, peteGrid: peteMover.grid) }

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
                score += eatBossPoints
                refreshHUD()
                ScorePopup.show(eatBossPoints, at: b.sprite.position, in: self,
                                color: SKColor(red: 0.3, green: 0.7, blue: 1, alpha: 1))
                b.returnHome()
                contactCooldown = 0.4
            } else {
                handlePeteHit()
            }
        }
    }

    private func bossOnPete() -> BossController? {
        let r = tileSize * 0.55
        let r2 = r * r
        for b in bosses {
            let dx = b.sprite.position.x - pete.position.x
            let dy = b.sprite.position.y - pete.position.y
            if dx * dx + dy * dy < r2 { return b }
        }
        return nil
    }

    // Called by the TileMover when Pete snaps to a new tile centre — picks
    // up dots/gold/water-pickups and fires the level transition. The mover
    // already handles tunnel wrap before this runs, so `grid` is the final
    // post-wrap cell.
    private func handlePeteArrival(at grid: CGPoint) {
        if mazeBuilder.collectDot(at: grid) {
            score += dotPoints
            dotsRemaining = max(0, dotsRemaining - 1)
            refreshHUD()
            if dotsRemaining == 0 { advanceLevel() }
        }
        if mazeBuilder.collectGold(at: grid) {
            score += goldPoints
            refreshHUD()
            ScorePopup.show(goldPoints, at: peteMover.centre(of: grid), in: self)
            frightenSecondsLeft = frightenDuration
            for b in bosses { b.setFrightened(true) }
            hud.flash("FRIGHTEN!", duration: 1.2)
        }
        if mazeBuilder.collectWaterPellet(at: grid) {
            waterAmmo += waterShotsPerPellet
            refreshHUD()
        }
        if mazeBuilder.collectWaterGun(at: grid) {
            waterAmmo += waterShotsPerGun
            refreshHUD()
            hud.flash("WATER GUN!", duration: 1.0)
        }
    }

    private func handlePeteHit() {
        lives = max(0, lives - 1)
        refreshHUD()
        if lives == 0 {
            triggerGameOver()
            return
        }
        hud.flash("OUCH!")
        contactCooldown = 1.2
        // Respawn Pete at the worker spawn so a stuck Pete doesn't immediately
        // retake another hit; bosses keep their position.
        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        resetPete(to: spawn)
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

        if score > 0 {
            let playerName = Persistence.string(forKey: Strings.DefaultsKey.playerName) ?? "ANON"
            LocalHighScores.submit(name: playerName, score: score)
        }

        let overlay = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        overlay.fillColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.55)
        overlay.strokeColor = .clear
        overlay.zPosition = 50
        addChild(overlay)

        let big = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
        big.text = "GAME OVER"
        big.fontSize = 86
        big.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.34, alpha: 1)
        big.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        big.zPosition = 51
        addChild(big)

        let summary = SKLabelNode(fontNamed: Strings.Font.menloBold)
        summary.text = "FINAL SCORE \(score)   HIGH \(highScore)"
        summary.fontSize = 22
        summary.fontColor = .white
        summary.position = CGPoint(x: size.width / 2, y: size.height * 0.44)
        summary.zPosition = 51
        addChild(summary)

        run(SKAction.sequence([
            SKAction.wait(forDuration: 3.0),
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
        hud.flash("LEVEL \(levelIndex + 1)!", duration: 1.4)

        for boss in bosses { boss.sprite.removeFromParent() }
        bosses.removeAll()
        mazeRoot.removeAllChildren()

        let rows = Levels.officeMaps[levelIndex]
        gridMap.setRows(rows)
        dotsRemaining = mazeBuilder.build(in: mazeRoot)
        dotsTotal = dotsRemaining

        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        resetPete(to: spawn)

        for bossSpawn in mazeBuilder.bossSpawns {
            let boss = BossController(blueprintIndex: bossSpawn.index,
                                      spawn: bossSpawn.position,
                                      map: gridMap,
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
                            b.returnHome()
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
                   totalDots: dotsTotal)
        hud.update(lives: lives)
        hud.update(ammo: waterAmmo)
    }
}
