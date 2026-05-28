import SpriteKit

// Game scene, wasm port — first playable iteration.
//
// What's here:
//   - Load Level 1 from Levels.officeMaps (JSON loaded via SKSceneLoader's
//     asset_text bridge); fall back to the empty-room template if the file
//     isn't reachable.
//   - GridMap + MazeBuilder lay walls, dots, gold discs, water pellets,
//     and record spawn positions for Pete (worker) and the four bosses.
//   - Pete (PixelPerson) drops at the workerSpawn tile and moves tile-by-tile,
//     queue-on-press style: pressing a direction at any moment sets the
//     pending heading, which Pete adopts the next time he reaches a tile
//     centre and the new direction is walkable.
//   - Tunnel wrap: when Pete arrives at a tile with a tunnel partner, he
//     teleports across.
//   - Dot collection is purely visual right now (score/lives HUD lands in
//     task #74); the dot disappears the instant Pete's grid coord matches.
//   - Bosses, boss AI, contact dispatch, water pistol, gold-disc shielding
//     all queued for the next pass.
//
// Escape returns to the title screen.
final class GameScene: SKScene {
    private var gridMap: GridMap!
    private var mazeBuilder: MazeBuilder!
    private var pete: PixelPerson!

    private var peteGrid = CGPoint.zero
    private var heading: MoveDirection? = nil
    private var queued:  MoveDirection? = nil
    private var moveSpeed: CGFloat = 8.0     // tiles per second

    private let tileSize: CGFloat = 32

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        anchorPoint = .zero

        let rows = Levels.officeMaps.first ?? []
        gridMap = GridMap(tileSize: tileSize, rows: rows)
        let mazeHeight = CGFloat(gridMap.rowCount) * tileSize
        let mazeWidth  = CGFloat(gridMap.columnCount) * tileSize
        // Centre the maze vertically; leave the bottom strip for the HUD.
        gridMap.yOffset = max(40, (size.height - mazeHeight) / 2)
        let xOffset = max(0, (size.width - mazeWidth) / 2)

        // MazeBuilder paints the cells; wrap it in a container node so the
        // single xOffset translate centers the whole field horizontally.
        let mazeContainer = SKNode()
        mazeContainer.position = CGPoint(x: xOffset, y: 0)
        addChild(mazeContainer)
        mazeBuilder = MazeBuilder(map: gridMap)
        mazeBuilder.build(in: mazeContainer)

        // Pete drops at the worker-spawn tile (or the first walkable cell if
        // the level didn't mark one).
        let spawn = mazeBuilder.workerSpawn ?? firstWalkableCell()
        peteGrid = spawn
        pete = SpriteFactory.petePerson()
        pete.position = mazeContainer.convert(gridMap.point(for: spawn), to: self)
        pete.zPosition = 5
        addChild(pete)
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

    // MARK: - Input

    override func keyDown(_ key: Int) {
        if key == 36 {
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
        let dt: CGFloat = 1.0 / 60.0   // simple fixed step; SKView drives at 60 fps
        let step = moveSpeed * tileSize * dt

        // Aim toward the current tile centre based on heading. If Pete is
        // exactly on a centre, decide the next tile.
        let centre = pete.parent === self
            ? gridMap.point(for: peteGrid).offsetBy(xOffset: -(mazeBuilder.workerSpawn == nil ? 0 : 0), yOffset: 0)
            : pete.position
        _ = centre   // currently unused; kept so the layout doc above reads cleanly

        let myCentre = gridMap.point(for: peteGrid)
        let containerX = (size.width - CGFloat(gridMap.columnCount) * tileSize) / 2
        let myCentreInScene = CGPoint(x: myCentre.x + max(0, containerX), y: myCentre.y)

        // Distance to my current tile centre — if we're "on" it, evaluate
        // direction queue and pick the next neighbour.
        let dx = myCentreInScene.x - pete.position.x
        let dy = myCentreInScene.y - pete.position.y
        let dist = (dx*dx + dy*dy).squareRoot()

        if dist < 0.5 {
            // Snap to centre.
            pete.position = myCentreInScene

            // Tunnel wrap.
            if let partner = gridMap.tunnelPartner(of: peteGrid) {
                peteGrid = partner
                let warp = gridMap.point(for: partner)
                pete.position = CGPoint(x: warp.x + max(0, containerX), y: warp.y)
            }

            // Eat the dot here.
            mazeBuilder.collectDot(at: peteGrid)
            mazeBuilder.collectGold(at: peteGrid)

            // Decide next heading.
            if let q = queued, canStep(q) {
                heading = q
                pete.setFacing(q)
            } else if let h = heading, !canStep(h) {
                heading = nil
            }

            // If we have a heading, advance the grid coord (Pete will then
            // chase the new centre on subsequent frames).
            if let h = heading {
                let next = step(in: h)
                if gridMap.isWalkable(next) && !gridMap.isHideout(next) {
                    peteGrid = next
                }
            }
        } else {
            // Glide toward the centre.
            let invDist = 1.0 / dist
            pete.position.x += dx * invDist * step
            pete.position.y += dy * invDist * step
        }
    }

    private func canStep(_ dir: MoveDirection) -> Bool {
        let next = step(in: dir)
        return gridMap.isWalkable(next) && !gridMap.isHideout(next)
    }
    private func step(in dir: MoveDirection) -> CGPoint {
        let (dx, dy) = dir.delta
        return CGPoint(x: peteGrid.x + CGFloat(dx), y: peteGrid.y + CGFloat(dy))
    }
}

private extension CGPoint {
    func offsetBy(xOffset: CGFloat, yOffset: CGFloat) -> CGPoint {
        CGPoint(x: x + xOffset, y: y + yOffset)
    }
}
