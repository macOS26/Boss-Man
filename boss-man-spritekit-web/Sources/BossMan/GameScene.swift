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
    private let mazeRoot = SKNode()

    private var peteGrid = CGPoint.zero
    private var heading: MoveDirection? = nil
    private var queued:  MoveDirection? = nil
    private var moveSpeed: CGFloat = 8.0    // tiles per second
    private let tileSize: CGFloat = 32
    private var containerOriginX: CGFloat = 0

    private let hud = HUD()
    private var score = 0
    private var highScore = 0
    private var lives = 3
    private var levelIndex = 0
    private var dotsRemaining = 0
    private let dotPoints = 10
    private let goldPoints = 200

    private var bosses: [BossController] = []
    private var contactCooldown: TimeInterval = 0     // brief grace after a hit
    private var frightenSecondsLeft: TimeInterval = 0
    private let frightenDuration: TimeInterval = 6
    private let eatBossPoints = 500

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        anchorPoint = .zero

        let rows = Levels.officeMaps.first ?? []
        gridMap = GridMap(tileSize: tileSize, rows: rows)

        let mazeHeight = CGFloat(gridMap.rowCount) * tileSize
        let mazeWidth  = CGFloat(gridMap.columnCount) * tileSize
        gridMap.yOffset = max(40, (size.height - mazeHeight) / 2)
        containerOriginX = max(0, (size.width - mazeWidth) / 2)

        mazeRoot.position = CGPoint(x: containerOriginX, y: 0)
        addChild(mazeRoot)

        mazeBuilder = MazeBuilder(map: gridMap)
        dotsRemaining = mazeBuilder.build(in: mazeRoot)

        hud.install(in: self)
        highScore = Persistence.int(forKey: Strings.DefaultsKey.highScore)
        refreshHUD()

        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        peteGrid = spawn
        pete = SpriteFactory.petePerson()
        pete.position = sceneCoord(forGrid: spawn)
        pete.zPosition = 5
        addChild(pete)

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

    // Convert a grid cell to a scene-space coordinate (including the maze
    // root's horizontal offset that centres the maze in the scene).
    private func sceneCoord(forGrid g: CGPoint) -> CGPoint {
        let local = gridMap.point(for: g)
        return CGPoint(x: local.x + containerOriginX, y: local.y)
    }

    // MARK: - Input

    override func keyDown(_ key: Int) {
        if key == 36 {        // Escape
            let title = TitleScene(size: size)
            title.scaleMode = .aspectFit
            view?.presentScene(title, transition: .fade(withDuration: 0.4))
            return
        }
        if let dir = MoveDirection(keyCode: key) {
            queued = dir
            if heading == nil { heading = dir }
            pete?.setFacing(dir)
        }
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard let pete else { return }
        let dt: CGFloat = 1.0 / 60.0
        let stepLen = moveSpeed * tileSize * dt

        let targetCentre = sceneCoord(forGrid: peteGrid)
        let dx = targetCentre.x - pete.position.x
        let dy = targetCentre.y - pete.position.y
        let dist = (dx * dx + dy * dy).squareRoot()

        if dist < 0.5 {
            pete.position = targetCentre

            if let partner = gridMap.tunnelPartner(of: peteGrid) {
                peteGrid = partner
                pete.position = sceneCoord(forGrid: partner)
            }

            if mazeBuilder.collectDot(at: peteGrid) {
                score += dotPoints
                dotsRemaining = max(0, dotsRemaining - 1)
                refreshHUD()
                if dotsRemaining == 0 { advanceLevel() }
            }
            if mazeBuilder.collectGold(at: peteGrid) {
                score += goldPoints
                refreshHUD()
                ScorePopup.show(goldPoints, at: sceneCoord(forGrid: peteGrid), in: self)
                frightenSecondsLeft = frightenDuration
                for b in bosses { b.setFrightened(true) }
                hud.flash("FRIGHTEN!", duration: 1.2)
            }

            if let q = queued, canStep(q) {
                heading = q
                pete.setFacing(q)
            } else if let h = heading, !canStep(h) {
                heading = nil
            }

            if let h = heading {
                let next = nextGrid(in: h)
                if gridMap.isWalkable(next) && !gridMap.isHideout(next) {
                    peteGrid = next
                }
            }
        } else {
            let invDist = 1.0 / dist
            pete.position.x += dx * invDist * stepLen
            pete.position.y += dy * invDist * stepLen
        }

        for boss in bosses { boss.step(dt: TimeInterval(dt), peteGrid: peteGrid) }

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

    private func handlePeteHit() {
        lives = max(0, lives - 1)
        refreshHUD()
        hud.flash("OUCH!")
        contactCooldown = 1.2
        // Respawn Pete at the worker spawn so a stuck Pete doesn't immediately
        // retake another hit; bosses keep their position.
        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        peteGrid = spawn
        pete.position = sceneCoord(forGrid: spawn)
        heading = nil
        queued = nil
    }

    private func canStep(_ dir: MoveDirection) -> Bool {
        let n = nextGrid(in: dir)
        return gridMap.isWalkable(n) && !gridMap.isHideout(n)
    }
    private func nextGrid(in dir: MoveDirection) -> CGPoint {
        let (dx, dy) = dir.delta
        return CGPoint(x: peteGrid.x + CGFloat(dx), y: peteGrid.y + CGFloat(dy))
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

        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        peteGrid = spawn
        pete.position = sceneCoord(forGrid: spawn)
        heading = nil
        queued = nil

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

    private func refreshHUD() {
        if score > highScore {
            highScore = score
            Persistence.set(highScore, forKey: Strings.DefaultsKey.highScore)
        }
        hud.update(score: score, highScore: highScore,
                   level: levelIndex + 1, dotsLeft: dotsRemaining)
        hud.update(lives: lives)
    }
}
