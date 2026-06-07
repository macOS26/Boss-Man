import SpriteKit
import AppKit

// 3D bonus round: isometric overhead view of the office maze (level 1). Parallel
// overhead projection (no vanishing point = true top-down/isometric look, not a
// horizon). The board is tilted down with short raised blocks; depth = row. The
// camera never moves, so the maze is projected ONCE at build time; only the moving
// sprites are projected per frame. Inherits shared 3D scene logic from Scene3D.
final class IsoScene: Scene3D, WorkerControllerDelegate {

    // MARK: - WorkerController (REAL 2D physics for Pete)
    private var workerController: WorkerController!
    private let workerHost = SKNode()

    // MARK: - Isometric world
    private let isoWorld = SKNode()
    private let isoMaze = SKNode()
    private var isoDotRowCells: [Int: [Int]] = [:]
    private var isoDotFrontNode: [Int: SKShapeNode] = [:]
    private var isoDotSideNode: [Int: SKShapeNode] = [:]
    private var isoDotTopNode: [Int: SKShapeNode] = [:]
    private var isoDotCollected: Set<Int> = []
    private var isoDotsLeft = 0
    private var isoPickups: [Int: SKNode] = [:]
    private var isoTraveler: SKNode?
    private var isoTravelerEmoji = ""
    private var isoTravelerPoints: SKLabelNode?
    private var travCol = 0.0, travRow = 0.0
    private var travFromCol = 0.0, travFromRow = 0.0, travToCol = 0.0, travToRow = 0.0, travProgress = 1.0
    private var travActive = false

    // PARALLEL overhead projection (no vanishing point = a true top-down/isometric look, not a horizon).
    // The board is tilted down (TH < TW vertical squash) with short raised blocks; depth = row. Because
    // it is parallel, the whole board projects ONCE and the view simply translates to follow Pete (ZOOM 2D
    // scroll) with no re-projection, and sprites keep a constant size (no depth shrink, no jitter).
    private var isoTW: CGFloat = 0, isoTH: CGFloat = 0, isoWH: CGFloat = 0
    private func setupProjection() {
        let zoom: CGFloat = 2.4
        isoTW = size.width / CGFloat(max(1, colsCount)) * zoom
        isoTH = isoTW * 0.62
        isoWH = isoTW * 0.46 - 2
        pVpY = isoTH * 6
    }
    private let pFocal = 70.0
    private var pVpY: CGFloat = 0
    private func persp(_ rowEdge: Double) -> CGFloat { CGFloat(pFocal / (pFocal + (Double(rowsCount) - rowEdge))) }

    private func proj(_ colEdge: Double, _ rowEdge: Double, _ y: CGFloat) -> CGPoint {
        let p = persp(rowEdge)
        let x0 = (CGFloat(colEdge) - CGFloat(colsCount) / 2) * isoTW
        let y0 = -CGFloat(rowEdge) * isoTH + y * isoWH
        return CGPoint(x: x0 * p, y: pVpY + (y0 - pVpY) * p)
    }
    private func perspScale(_ row: Double) -> CGFloat { persp(row) }

    private func quadPath(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPath {
        let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d); p.closeSubpath(); return p
    }
    @discardableResult private func addQuad(_ path: CGPath, _ fill: SKColor, _ stroke: SKColor, _ z: CGFloat) -> SKShapeNode {
        let n = SKShapeNode(path: path); n.fillColor = fill; n.strokeColor = .clear; n.lineWidth = 0; n.isAntialiased = false; n.zPosition = z
        isoMaze.addChild(n); return n
    }
    private func addSub(_ p: CGMutablePath, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) {
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d); p.closeSubpath()
    }
    private func appendDotFaces(_ front: CGMutablePath, _ side: CGMutablePath, _ top: CGMutablePath, _ c: Int, _ r: Int, _ gold: Bool) {
        let h = (gold ? 0.28 : 0.20) * 0.7225
        let cx0 = Double(c) + 0.5, ry0 = Double(r) + 0.5, mid = Double(colsCount) / 2
        let yT = ((gold ? 1.2 : 0.95) * 0.7225 * isoWH - 9) / max(1, isoWH)
        let bNW = proj(cx0 - h, ry0 - h, 0), bNE = proj(cx0 + h, ry0 - h, 0)
        let bSE = proj(cx0 + h, ry0 + h, 0), bSW = proj(cx0 - h, ry0 + h, 0)
        let uNW = proj(cx0 - h, ry0 - h, yT), uNE = proj(cx0 + h, ry0 - h, yT)
        let uSE = proj(cx0 + h, ry0 + h, yT), uSW = proj(cx0 - h, ry0 + h, yT)
        addSub(front, bSW, bSE, uSE, uSW)
        if cx0 < mid { addSub(side, bNE, bSE, uSE, uNE) }
        else if cx0 > mid { addSub(side, bNW, bSW, uSW, uNW) }
        addSub(top, uNW, uNE, uSE, uSW)
    }
    private func isDotTile(_ ch: UInt8) -> Bool {
        ch == Strings.Tile.dotChar || ch == Strings.Tile.hideoutChar
    }

    private func appendCubicleTrim(_ bl: CGPoint, _ br: CGPoint, _ tr: CGPoint, _ tl: CGPoint, _ trim: CGMutablePath) {
        func L(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            let bx = bl.x + (br.x - bl.x) * u, by = bl.y + (br.y - bl.y) * u
            let tx = tl.x + (tr.x - tl.x) * u, ty = tl.y + (tr.y - tl.y) * u
            return CGPoint(x: bx + (tx - bx) * v, y: by + (ty - by) * v)
        }
        addSub(trim, L(0.18, 0.64), L(0.82, 0.64), L(0.82, 0.78), L(0.18, 0.78))
    }

    private func buildIso() {
        setupProjection()
        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        let cubeP = [cube.blended(withFraction: 0.18, of: .black) ?? cube, cube]
        var topP = [SKColor](), frontP = [SKColor](), sideP = [SKColor](), edgeP = [SKColor]()
        for base in cubeP {
            topP.append(base)
            frontP.append(base.blended(withFraction: 0.30, of: .black) ?? base)
            sideP.append(base.blended(withFraction: 0.50, of: .black) ?? base)
            edgeP.append(base.blended(withFraction: 0.22, of: .white) ?? base)
        }
        let floorP = [SKColor(white: 0.07, alpha: 1), SKColor(white: 0.14, alpha: 1)]
        let floorEdge = SKColor(white: 0.16, alpha: 1)
        let dotFront = SKColor.systemYellow.blended(withFraction: 0.30, of: .black) ?? .systemYellow
        let dotSide  = SKColor.systemYellow.blended(withFraction: 0.50, of: .black) ?? .systemYellow
        let mid = Double(colsCount) / 2
        for r in 0..<rowsCount {
            let row = map[r]
            let z = CGFloat(r) * 4
            let pFloor = [CGMutablePath(), CGMutablePath()], pFront = [CGMutablePath(), CGMutablePath()]
            let pSide = [CGMutablePath(), CGMutablePath()], pTop = [CGMutablePath(), CGMutablePath()]
            let pTrim = CGMutablePath()
            var hasFloor = [false, false], hasFront = [false, false], hasSide = [false, false], hasTop = [false, false]
            var hasWall = false
            var dotCols: [Int] = []
            for c in 0..<min(colsCount, row.count) {
                let ch = row[c]; let dc = Double(c); let par = (c + r) & 1
                let fNW = proj(dc, Double(r), 0), fNE = proj(dc + 1, Double(r), 0)
                let fSE = proj(dc + 1, Double(r + 1), 0), fSW = proj(dc, Double(r + 1), 0)
                if ch == Strings.Tile.wallChar {
                    let tNW = proj(dc, Double(r), 1), tNE = proj(dc + 1, Double(r), 1)
                    let tSE = proj(dc + 1, Double(r + 1), 1), tSW = proj(dc, Double(r + 1), 1)
                    addSub(pFront[par], fSW, fSE, tSE, tSW); hasFront[par] = true
                    if dc + 0.5 < mid { addSub(pSide[par], fNE, fSE, tSE, tNE); hasSide[par] = true }
                    else if dc + 0.5 > mid { addSub(pSide[par], fNW, fSW, tSW, tNW); hasSide[par] = true }
                    addSub(pTop[par], tNW, tNE, tSE, tSW); hasTop[par] = true
                    appendCubicleTrim(tSW, tSE, tNE, tNW, pTrim)
                    hasWall = true
                } else {
                    addSub(pFloor[par], fNW, fNE, fSE, fSW); hasFloor[par] = true
                    if isDotTile(ch) { dotCols.append(c) }
                }
            }
            for par in 0...1 {
                if hasFloor[par] { addQuad(pFloor[par], floorP[par], floorEdge, z - 1) }
                if hasSide[par]  { addQuad(pSide[par], sideP[par], sideP[par], z + 0.1) }
                if hasFront[par] { addQuad(pFront[par], frontP[par], frontP[par], z + 0.2) }
                if hasTop[par]   { addQuad(pTop[par], topP[par], edgeP[par], z + 0.3) }
            }
            if hasWall {
                let t = SKShapeNode(path: pTrim); t.fillColor = SpriteFactory.wallTrimColor; t.strokeColor = .clear; t.lineWidth = 0; t.isAntialiased = false; t.zPosition = z + 0.40; isoMaze.addChild(t)
            }
            if !dotCols.isEmpty {
                isoDotRowCells[r] = dotCols
                let pF = CGMutablePath(), pS = CGMutablePath(), pT = CGMutablePath()
                for c in dotCols { appendDotFaces(pF, pS, pT, c, r, map[r][c] == Strings.Tile.goldDiscChar) }
                isoDotSideNode[r]  = addQuad(pS, dotSide, dotSide, z + 0.55)
                isoDotFrontNode[r] = addQuad(pF, dotFront, dotFront, z + 0.6)
                isoDotTopNode[r]   = addQuad(pT, .systemYellow, .systemYellow, z + 0.7)
                for n in [isoDotSideNode[r], isoDotFrontNode[r], isoDotTopNode[r]] { n?.position.y += 10 }
                isoDotsLeft += dotCols.count
            }
        }
    }

    private func rebuildDotRow(_ r: Int) {
        guard let cols = isoDotRowCells[r] else { return }
        let pF = CGMutablePath(), pS = CGMutablePath(), pT = CGMutablePath()
        for c in cols where !isoDotCollected.contains(mapKey(c, r)) { appendDotFaces(pF, pS, pT, c, r, map[r][c] == Strings.Tile.goldDiscChar) }
        isoDotFrontNode[r]?.path = pF
        isoDotSideNode[r]?.path = pS
        isoDotTopNode[r]?.path = pT
    }

    private func buildIsoPickups() {
        let s = isoTW * 0.7
        for r in 0..<rowsCount {
            let row = map[r]
            for c in 0..<min(colsCount, row.count) {
                let node: SKNode
                switch row[c] {
                case Strings.Tile.waterGunChar:    node = throbbing(emojiBillboard(Strings.Emoji.waterGun, s), 1.18, 0.5)
                case Strings.Tile.printerChar:     node = emojiBillboard(Strings.Emoji.printer, s)
                case Strings.Tile.faxChar:         node = emojiBillboard(Strings.Emoji.fax, s)
                case Strings.Tile.coverSheetChar:  node = emojiBillboard(Strings.Emoji.coverSheet, s)
                case Strings.Tile.bookBinderChar:  node = emojiBillboard(Strings.Emoji.bookBinder, s)
                case Strings.Tile.brownBoxChar:    node = emojiBillboard(Strings.Emoji.brownBox, s)
                case Strings.Tile.waterPelletChar: node = throbbing(SpriteFactory.waterPelletVisual(radius: isoTW * 0.3), 1.25, 0.5)
                case Strings.Tile.goldDiscChar:    node = throbbing(SpriteFactory.goldDiscVisual(radius: isoTW * 0.34), 1.18, 0.5)
                default: continue
                }
                spriteLayer.addChild(node)
                placeIsoSprite(node, CGFloat(c) + 0.5, CGFloat(r) + 0.5, s)
                node.position.y += 6
                node.zPosition = CGFloat(r) * 4 + 0.55
                isoPickups[mapKey(c, r)] = node
            }
        }
    }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        anchorPoint = .zero
        backgroundColor = .black
        placeStart()
        isoWorld.zPosition = 0
        addChild(isoWorld)
        isoWorld.addChild(isoMaze)
        spriteLayer.zPosition = 0
        isoWorld.addChild(spriteLayer)
        nameLayer.zPosition = 150
        isoWorld.addChild(nameLayer)
        workerHost.alpha = 0
        addChild(workerHost)
        buildIso()
        buildIsoPickups()
        buildPete()
        buildMap()
        setupBossController()
        buildHUD()
        buildControls()
        render()
        sound.startBackgroundMusic()
    }

    override func castFloor() {
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        let rdx0 = dirX - planeX, rdy0 = dirY - planeY
        let rdx1 = dirX + planeX, rdy1 = dirY + planeY
        let W = size.width, rowH: CGFloat = 2
        let pathA = CGMutablePath(), pathB = CGMutablePath(), pathFar = CGMutablePath()
        var yu = radarH
        while yu < viewMidY - 0.5 {
            let distFromHorizon = Double(viewMidY - yu)
            let d = Double(viewH) * Double(eyeHeight) / distFromHorizon
            if d > 13 {
                pathFar.addRect(CGRect(x: 0, y: yu, width: W, height: rowH))
                yu += rowH
                continue
            }
            let fx0 = camX + d * rdx0, fy0 = camY + d * rdy0
            let stepX = d * (rdx1 - rdx0) / Double(W), stepY = d * (rdy1 - rdy0) / Double(W)
            var runStart: CGFloat = 0
            var runParity = (Int(fx0.rounded(.down)) + Int(fy0.rounded(.down))) & 1
            var x: CGFloat = 1
            while x <= W {
                var parity = -1
                if x < W {
                    let wx = fx0 + stepX * Double(x), wy = fy0 + stepY * Double(x)
                    parity = (Int(wx.rounded(.down)) + Int(wy.rounded(.down))) & 1
                }
                if parity != runParity {
                    let r = CGRect(x: runStart, y: yu, width: x - runStart, height: rowH)
                    if runParity == 1 { pathA.addRect(r) } else { pathB.addRect(r) }
                    runStart = x; runParity = parity
                }
                x += 1
            }
            yu += rowH
        }
        floorA.path = pathA; floorB.path = pathB; floorFar.path = pathFar
    }

    // IsoScene uses petePerson (front-facing), not petePersonBack
    override func makePete() -> PixelPerson {
        SpriteFactory.petePerson(walkExaggeration: 1)
    }

    // Caught: hold the REAL catching boss still in front of Pete for ~1.5s (no fake sprite),
    // then dock a life and respawn. update() skips step()/render() while dying, so the boss
    // stays frozen exactly where we place it here.
    override func startDeath(node: PixelPerson) {
        if dying { return }
        dying = true
        _ = sound.playCaughtByBoss()
        if goldDisc.isActive { endGoldDiscMode() }
        pete.stopWalking()
        node.stopWalking()
        pete.run(.fadeOut(withDuration: TimeInterval(deathFrames) / 60.0))
        deathFramesLeft = deathFrames
    }

    override func finishDeath() {
        dying = false
        for (_, l) in bossNames { l.isHidden = false }
        state.lives -= 1
        refreshHUD()
        if state.lives <= 0 { gameOver = true; showGameOver(); return }
        let spawnGrid = CGPoint(x: Int(spawnPx), y: rowsCount - 1 - Int(spawnPy))
        workerController.teleport(to: spawnGrid)
        workerController.resetMotion()
        workerController.applySpawnShield()
        pressed.removeAll()
        px = spawnPx; py = spawnPy
        bossController.teleportAllToSpawn()
        pete.alpha = 1
        pete.startWalking()
        pete.removeAction(forKey: "shield")
        pete.run(.sequence([.repeat(.sequence([.fadeAlpha(to: 0.35, duration: 0.6), .fadeAlpha(to: 1.0, duration: 0.6)]), count: 3),
                            .run { [weak self] in self?.pete.alpha = 1 }]), withKey: "shield")
    }

    override func togglePause() {
        super.togglePause()
        isoWorld.isPaused = isUserPaused
    }

    override func updateMap() {
        if let d = workerController?.direction {
            switch d {
            case .right: moveDir = (x: 1,  y: 0)
            case .left:  moveDir = (x: -1, y: 0)
            case .up:    moveDir = (x: 0,  y: -1)
            case .down:  moveDir = (x: 0,  y: 1)
            }
        }
        super.updateMap()
        if travActive, let _ = travelerSpawner?.activeTraveler {
            mapTraveler?.isHidden = false
            mapTraveler?.position = mapLocal(travCol, travRow)
        } else {
            mapTraveler?.isHidden = true
        }
    }

    override func setupBossController() {
        let rows = LevelStore.loadLevel(index: max(0, min(state.level - 1, Levels.levelNames.count - 1)))
        gridMap = GridMap(tileSize: 32, rows: rows)
        gridMap.xOffset = 0; gridMap.yOffset = 0
        pathfinder = Pathfinder(map: gridMap)
        let spawnGrid = CGPoint(x: Int(spawnPx), y: rowsCount - 1 - Int(spawnPy))
        workerController = WorkerController(spawnGrid: spawnGrid, gridMap: gridMap, sound: sound)
        workerController.delegate = self
        workerHost.addChild(workerController.node)
        workerController.applySpawnShield()
        bossController = BossController(scene: self, gridMap: gridMap, pathfinder: pathfinder, sound: sound, containerOriginX: 0)
        bossController.delegate = self
        var overrides: [(blueprintIndex: Int, position: CGPoint)] = []
        for (ri, row) in rows.reversed().enumerated() {
            for (ci, ch) in row.utf8.enumerated() {
                switch ch {
                case Strings.Tile.boss1Char: overrides.append((0, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss2Char: overrides.append((1, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss3Char: overrides.append((2, CGPoint(x: ci, y: ri)))
                case Strings.Tile.boss4Char: overrides.append((3, CGPoint(x: ci, y: ri)))
                default: break
                }
            }
        }
        bossController.spawn(forLevel: 1, spawnOverrides: overrides)
        syncBossNodes()
        travelerSpawner = TravelerSpawner(scene: self, gridMap: gridMap, sound: sound, containerOriginX: 0)
        travelerSpawner.scheduleVisits(of: levelTravelers[(state.level - 1) % levelTravelers.count]) { [weak self] in
            guard let self else { return false }
            return !self.gameOver && !self.isUserPaused && !self.dying
        }
    }

    // MARK: - Per-frame
    override func render() { renderIso() }

    private var isoNativeH: [ObjectIdentifier: CGFloat] = [:]
    private var isoFeet: [ObjectIdentifier: CGFloat] = [:]
    private func placeIsoSprite(_ node: SKNode, _ col: CGFloat, _ row: CGFloat, _ targetH: CGFloat, _ lift: CGFloat = 0) {
        let id = ObjectIdentifier(node)
        let nh: CGFloat, bottom: CGFloat
        if let n = isoNativeH[id], let b = isoFeet[id] { nh = n; bottom = b }
        else {
            let prev = node.xScale
            node.setScale(1)
            let f = node.calculateAccumulatedFrame()
            nh = max(1, f.height); bottom = f.minY - node.position.y
            isoNativeH[id] = nh; isoFeet[id] = bottom
            node.setScale(prev)
        }
        let s = targetH * perspScale(Double(row)) / nh
        node.setScale(s)
        let pt = proj(Double(col), Double(row), lift)
        node.position = CGPoint(x: pt.x, y: pt.y - bottom * s)
    }

    private func renderIso() {
        throbClock += 1.0 / 60.0
        let anchorY = radarH + (size.height - radarH) * 0.50
        let foot = proj(Double(px), Double(py), 0)
        isoWorld.position = CGPoint(x: size.width / 2 - foot.x, y: anchorY - foot.y)

        let spriteH = isoTW * 0.95
        placeIsoSprite(pete, CGFloat(px), CGFloat(py), spriteH)
        pete.position.y += 3
        pete.zPosition = CGFloat(py) * 4 + 0.6
        if !dying, let d = workerController.direction { pete.setFacing(d) }
        peteName.position = CGPoint(x: pete.position.x, y: pete.position.y + spriteH * perspScale(py) * 0.5 + 10)
        peteName.zPosition = pete.zPosition + 0.1

        for e in bossController.entities {
            guard let g = bossGrid[ObjectIdentifier(e.node)] else { e.node.isHidden = true; continue }
            let bcol = g.0 + 0.5, brow = Double(rowsCount) - 0.5 - g.1
            e.node.isHidden = false
            placeIsoSprite(e.node, CGFloat(bcol), CGFloat(brow), spriteH)
            e.node.position.y += 3
            e.node.zPosition = CGFloat(brow) * 4 + 0.6
            if let d = e.mover?.dir { e.node.unfreezeLook(); e.node.setFacing(d) }
            if !e.name.isEmpty {
                let label = bossNameplate(for: e.node, text: e.name); label.isHidden = false
                let fleeing = goldDisc.isActive && bossController.isInFleeMode(boss: e.node)
                label.text = fleeing ? "\(bossController.nextCapturePoints)" : e.name
                label.fontColor = .white
                label.position = CGPoint(x: e.node.position.x, y: e.node.position.y + spriteH * perspScale(brow) * 0.5 + 10)
                label.zPosition = e.node.zPosition + 0.1
            }
        }

        if travActive, let info = travelerSpawner?.activeTraveler {
            travelerSpawner?.node?.isHidden = true
            if isoTraveler == nil || isoTravelerEmoji != info.emoji {
                isoTraveler?.removeFromParent()
                let m = emojiBillboard(info.emoji, isoTW * 0.9); spriteLayer.addChild(m)
                isoTraveler = m; isoTravelerEmoji = info.emoji
                isoTravelerPoints?.removeFromParent()
                let p = SKLabelNode(fontNamed: Strings.Font.menloBold)
                p.text = "\(info.points)"; p.fontColor = .white
                p.verticalAlignmentMode = .baseline; p.horizontalAlignmentMode = .center
                spriteLayer.addChild(p); isoTravelerPoints = p
            }
            if let m = isoTraveler {
                m.isHidden = false
                placeIsoSprite(m, CGFloat(travCol), CGFloat(travRow), isoTW * 0.9)
                m.position.y += 3
                m.xScale = abs(m.xScale) * travFlip
                m.zPosition = CGFloat(travRow) * 4 + 0.6
                if let p = isoTravelerPoints {
                    p.isHidden = false
                    p.fontSize = max(9, isoTW * 0.34)
                    p.position = CGPoint(x: m.position.x, y: m.position.y + isoTW * 0.9 - 32)
                    p.zPosition = m.zPosition + 0.1
                }
            }
        } else {
            isoTraveler?.isHidden = true
            isoTravelerPoints?.isHidden = true
        }

        let shotH = isoTW * 0.34
        for s in shots where s.alive {
            if s.node.parent !== spriteLayer { s.node.removeFromParent(); spriteLayer.addChild(s.node) }
            s.node.isHidden = false
            placeIsoSprite(s.node, CGFloat(s.x), CGFloat(s.y), shotH, 0.55)
            s.node.zPosition = CGFloat(s.y) * 4 + 0.65
        }
    }

    private func render_unused_firstperson() {
        throbClock += 1.0 / 60.0
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back; camY = py - dirY * back
        castFloor()

        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        let w = size.width / CGFloat(columns)
        let half = wallHeightScale - eyeHeight
        let floorClamp = radarH - viewH
        var quads: [Scene3D.VQuad] = []
        var openF: [Int: WallRun] = [:]
        var tops = Set<Int>()
        func emitFront(_ r: WallRun) {
            let xL = CGFloat(r.firstCol) * w, xR = CGFloat(r.lastCol + 1) * w + 0.6
            let cxA = (CGFloat(r.firstCol) + 0.5) * w, cxB = (CGFloat(r.lastCol) + 0.5) * w
            var yLoL = r.yLoA, yLoR = r.yLoB, yHiL = r.yHiA, yHiR = r.yHiB
            if r.lastCol > r.firstCol {
                let dx = cxB - cxA
                let sLo = (r.yLoB - r.yLoA) / dx, sHi = (r.yHiB - r.yHiA) / dx
                yLoL = r.yLoA + sLo * (xL - cxA); yLoR = r.yLoA + sLo * (xR - cxA)
                yHiL = r.yHiA + sHi * (xL - cxA); yHiR = r.yHiA + sHi * (xR - cxA)
            }
            let dAvg = r.depthSum / Double(r.n)
            let f = CGFloat(max(0.10, min(1.0, 1.0 - dAvg / maxVoxelDist)))
                    * (r.side == 1 ? 0.62 : 1.0) * (r.par == 1 ? 1.0 : 0.82)
            let color = cube.blended(withFraction: 1 - f, of: .black) ?? cube
            quads.append(VQuad(p0: CGPoint(x: xL, y: yLoL), p1: CGPoint(x: xL, y: yHiL),
                               p2: CGPoint(x: xR, y: yHiR), p3: CGPoint(x: xR, y: yLoR), color: color, depth: dAvg))
        }
        func addFront(_ key: Int, _ col: Int, _ yLo: CGFloat, _ yHi: CGFloat, _ d: Double, _ side: Int, _ par: Int) {
            if var r = openF[key], r.lastCol == col - 1 {
                r.lastCol = col; r.yLoB = yLo; r.yHiB = yHi; r.depthSum += d; r.n += 1; openF[key] = r
            } else {
                if let r = openF[key] { emitFront(r) }
                openF[key] = WallRun(firstCol: col, lastCol: col, yLoA: yLo, yHiA: yHi, yLoB: yLo, yHiB: yHi, depthSum: d, n: 1, side: side, par: par)
            }
        }
        for col in 0..<columns {
            let cameraX = 2.0 * (Double(col) + 0.5) / Double(columns) - 1.0
            let rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX
            var mapX = Int(camX.rounded(.down)), mapY = Int(camY.rounded(.down))
            let ddx = rdx == 0 ? 1e30 : abs(1 / rdx), ddy = rdy == 0 ? 1e30 : abs(1 / rdy)
            var stepX = 0, stepY = 0, sideX = 0.0, sideY = 0.0
            if rdx < 0 { stepX = -1; sideX = (camX - Double(mapX)) * ddx } else { stepX = 1; sideX = (Double(mapX) + 1 - camX) * ddx }
            if rdy < 0 { stepY = -1; sideY = (camY - Double(mapY)) * ddy } else { stepY = 1; sideY = (Double(mapY) + 1 - camY) * ddy }
            var firstHit = true
            var prevWall = false
            var guardN = 0
            while guardN < 160 {
                guardN += 1
                let dEntry: Double, side: Int
                if sideX < sideY { dEntry = sideX; sideX += ddx; mapX += stepX; side = 0 }
                else             { dEntry = sideY; sideY += ddy; mapY += stepY; side = 1 }
                if mapY < 0 || mapY >= rowsCount || mapX < 0 || mapX >= colsCount { break }
                if dEntry > maxVoxelDist { break }
                if map[mapY][mapX] != Strings.Tile.wallChar { prevWall = false; continue }
                let dN = max(0.05, dEntry)
                if firstHit { zbuf[col] = dN; firstHit = false }
                tops.insert(mapY * colsCount + mapX)
                if !prevWall {
                    let fid = side == 0 ? (stepX > 0 ? mapX : mapX + 1) * 2 : (stepY > 0 ? mapY : mapY + 1) * 2 + 1
                    let par = (mapX + mapY) & 1
                    let baseY = max(floorClamp, viewMidY - viewH * eyeHeight / CGFloat(dN))
                    let frontTopY = viewMidY + viewH * half / CGFloat(dN)
                    addFront(fid * 2 + par, col, baseY, frontTopY, dN, side, par)
                }
                prevWall = true
            }
            if firstHit { zbuf[col] = 1e9 }
            for fid in Array(openF.keys) where openF[fid]!.lastCol < col { emitFront(openF[fid]!); openF.removeValue(forKey: fid) }
        }
        for (_, r) in openF { emitFront(r) }
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        let capZ = wallHeightScale - eyeHeight
        let corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for key in tops {
            let cx = Double(key % colsCount), cy = Double(key / colsCount)
            var pp = [CGPoint](); pp.reserveCapacity(4)
            var dsum = 0.0, ok = true
            for (ox, oy) in corners {
                let relX = (cx + Double(ox)) - camX, relY = (cy + Double(oy)) - camY
                let depth = invDet * (-planeY * relX + planeX * relY)
                if depth < 0.12 { ok = false; break }
                let transX = invDet * (dirY * relX - dirX * relY)
                pp.append(CGPoint(x: size.width / 2 * (1 + CGFloat(transX / depth)),
                                  y: viewMidY + viewH * CGFloat(capZ) / CGFloat(depth)))
                dsum += depth
            }
            if !ok { continue }
            let dAvg = dsum / 4
            if dAvg > maxVoxelDist { continue }
            let par = (Int(cx) + Int(cy)) & 1
            let f = CGFloat(max(0.10, min(1.0, 1.0 - dAvg / maxVoxelDist))) * (par == 1 ? 1.0 : 0.82)
            let base = cube.blended(withFraction: 1 - f, of: .black) ?? cube
            let color = base.blended(withFraction: 0.3, of: .white) ?? base
            quads.append(VQuad(p0: pp[0], p1: pp[1], p2: pp[2], p3: pp[3], color: color, depth: dAvg))
        }
        quads.sort { $0.depth > $1.depth }
        paintQuads(quads)
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
        updateMapTravelerMirror()
    }

    override func projectSprites(dirX: Double, dirY: Double, planeX: Double, planeY: Double) {
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        var all: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, x: Double, y: Double, maxH: CGFloat, name: String?, bottom: CGFloat)] = []
        for b in billboards where b.alive {
            all.append((b.node, b.nativeH, b.worldH, b.x, b.y, .greatestFiniteMagnitude, nil, -b.nativeH / 2))
        }
        for e in bossController.entities {
            guard let g = bossGrid[ObjectIdentifier(e.node)] else { continue }
            let id = ObjectIdentifier(e.node)
            let bx = g.0 + 0.5, by = Double(rowsCount) - 0.5 - g.1
            let nh = bossNativeH[id] ?? 36
            all.append((e.node, nh, 0.3, bx, by, .greatestFiniteMagnitude, e.name, bossFeet[id] ?? -nh / 2))
        }
        for s in shots where s.alive {
            all.append((s.node, s.nativeH, 0.32, s.x, s.y, .greatestFiniteMagnitude, nil, -s.nativeH / 2))
        }
        if let tnode = travelerSpawner?.node, travelerSpawner?.activeTraveler != nil {
            if tnode.parent !== spriteLayer { tnode.removeFromParent(); spriteLayer.addChild(tnode) }
            let g = travelerSpawner.grid
            let nh = max(1, tnode.calculateAccumulatedFrame().height)
            all.append((tnode, nh, 0.42, Double(g.x) + 0.5, Double(rowsCount) - 0.5 - Double(g.y), .greatestFiniteMagnitude, nil, -nh / 2))
        }
        var vis: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, maxH: CGFloat, name: String?, bottom: CGFloat, tX: Double, tY: Double)] = []
        for item in all {
            let node = item.node
            item.name.map { bossNameplate(for: node, text: $0) }?.isHidden = true
            let relX = item.x - camX, relY = item.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)
            guard tY > 0.15 else { node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            if col >= 0, col < columns {
                let footHalf = max(1, min(5, Int((viewH / CGFloat(tY) * item.worldH) / (size.width / CGFloat(columns)) * 0.5)))
                var wallZ = zbuf[col]
                for c in max(0, col - footHalf)...min(columns - 1, col + footHalf) { wallZ = min(wallZ, zbuf[c]) }
                if tY > wallZ + 0.3 { node.isHidden = true; continue }
            }
            if tY > 18 { node.isHidden = true; continue }
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { node.isHidden = true; continue }
            vis.append((node, item.nativeH, item.worldH, item.maxH, item.name, item.bottom, tX, tY))
        }
        vis.sort { $0.tY > $1.tY }
        let zStep = vis.count > 1 ? 80.0 / Double(vis.count - 1) : 0
        for (i, v) in vis.enumerated() {
            let node = v.node, tY = v.tY
            let targetH = min(viewH / CGFloat(tY) * v.worldH, v.maxH)
            var s = targetH / v.nativeH
            if v.name != nil, let boss = node as? PixelPerson, bossController.isImmobilized(boss: boss) {
                s *= 1 + 0.18 * abs(sin(throbClock * .pi * 3))
            }
            node.isHidden = false
            node.setScale(s)
            let screenX = (size.width / 2) * CGFloat(1 + v.tX / tY)
            let floorY = viewMidY - (viewH / CGFloat(tY)) * eyeHeight
            node.position = CGPoint(x: screenX, y: floorY - v.bottom * s)
            node.zPosition = 2 + CGFloat(Double(i) * zStep)
            if let name = v.name {
                let label = bossNameplate(for: node, text: name)
                label.isHidden = false
                label.fontSize = max(13, min(24, targetH * 0.16))
                label.position = CGPoint(x: screenX, y: floorY + targetH + label.fontSize * 0.7)
            }
        }
    }

    // MARK: - Lane movement (Pac-Man style: auto-forward, turn at junctions)
    override func step() {
        workerController.advance(1.0 / 60.0)
        let wp = workerController.worldPosition
        px = Double(wp.x) / 32.0
        py = Double(rowsCount) - Double(wp.y) / 32.0
        if let info = travelerSpawner?.activeTraveler, let tn = travelerSpawner?.node {
            let nc = Double(tn.position.x) / 32.0
            let nr = Double(rowsCount) - Double(tn.position.y) / 32.0
            let dx = nc - travCol
            if travActive, abs(dx) > 0.001, abs(dx) < 2 { travFlip = info.facesRight ? (dx < 0 ? -1 : 1) : (dx < 0 ? 1 : -1) }
            travCol = nc; travRow = nr
            travActive = true
        } else { travActive = false }
        bossController.advance(1.0 / 60.0)
        syncBossNodes()
        bossGrid.removeAll(keepingCapacity: true)
        for e in bossController.entities {
            let p = e.mover?.worldPosition ?? e.node.position
            bossGrid[ObjectIdentifier(e.node)] = (Double(p.x) / 32.0 - 0.5, Double(p.y) / 32.0 - 0.5)
        }
        peteShielded = bossController.isAnyBossSpawning
        workerController.setShielded(peteShielded)
        checkBossCatch()
        if let caught = travelerSpawner?.tryCatch(at: workerGrid) {
            state.bumpScore(by: caught.traveler.points)
            sound.playFishOrTreat()
            popPoints(caught.traveler.points)
            captureFade(isoTraveler); isoTraveler = nil; isoTravelerEmoji = ""
            captureFade(isoTravelerPoints); isoTravelerPoints = nil
            captureFade(mapTraveler); mapTraveler = nil; mapTravelerEmoji = ""
            refreshHUD()
            hud.showMessage(Strings.Message.travelerCaught(emoji: caught.traveler.emoji, points: caught.traveler.points), duration: 2)
        }
        if frightenSecondsLeft > 0 {
            frightenSecondsLeft -= 1.0 / 60.0
            if frightenSecondsLeft <= 0 { endGoldDiscMode() }
        }
        if workerController.direction != nil { pete.startWalking() } else { pete.stopWalking() }
        moveShots()
        updateMap()
    }

    // MARK: - WorkerControllerDelegate (real engine drives Pete; pickups fire here, not a per-frame scan)
    var isGameOver: Bool { gameOver }
    func workerDidEnterTile(_ grid: CGPoint) {
        let c = Int(grid.x), r = rowsCount - 1 - Int(grid.y)
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return }
        let key = mapKey(c, r), ch = map[r][c]
        if isDotTile(ch) {
            guard !isoDotCollected.contains(key) else { return }
            isoDotCollected.insert(key); isoDotsLeft -= 1
            rebuildDotRow(r); mapPickups[key]?.isHidden = true
            sound.playDotBlip(); state.collectedDots += 1; state.bumpScore(by: 1)
            refreshHUD(); checkLevelComplete3D(); return
        }
        switch ch {
        case Strings.Tile.goldDiscChar:
            guard !collected.contains(key) else { return }
            collected.insert(key); sound.playGoldDisc(); state.collectedGoldDiscs += 1
            state.bumpScore(by: 5); popPoints(5); hidePickup(c, r); startGoldDiscMode(); refreshHUD()
            checkLevelComplete3D()
        case Strings.Tile.waterGunChar:
            guard !collected.contains(key) else { return }
            collected.insert(key); waterGun.activate(); waterGunPickedUp = true
            sound.playWaterGunPickup(); state.bumpScore(by: 75); popPoints(75); hidePickup(c, r); refreshHUD()
            checkLevelComplete3D()
        case Strings.Tile.waterPelletChar:
            guard !collected.contains(key) else { return }
            collected.insert(key); state.bumpScore(by: 50); sound.playWaterGunPickup(); popPoints(50)
            if waterGunPickedUp { waterGun.reloadPellets(8) }
            hidePickup(c, r); refreshHUD()
            checkLevelComplete3D()
        case Strings.Tile.printerChar:    collectMachine(Strings.Machine.printer, key, c, r)
        case Strings.Tile.faxChar:        collectMachine(Strings.Machine.fax, key, c, r)
        case Strings.Tile.coverSheetChar: collectMachine(Strings.Machine.coverSheet, key, c, r)
        case Strings.Tile.bookBinderChar: collectMachine(Strings.Machine.bookBinder, key, c, r)
        case Strings.Tile.brownBoxChar:   collectTPSReport(c, r)
        default: break
        }
    }

    private func collectIsoDot() {
        let c = Int(px.rounded(.down)), r = Int(py.rounded(.down))
        guard r >= 0, r < rowsCount, c >= 0, c < map[r].count else { return }
        let key = mapKey(c, r)
        guard isDotTile(map[r][c]), !isoDotCollected.contains(key) else { return }
        guard abs(px - (Double(c) + 0.5)) < 0.45, abs(py - (Double(r) + 0.5)) < 0.45 else { return }
        isoDotCollected.insert(key); isoDotsLeft -= 1; rebuildDotRow(r)
        switch map[r][c] {
        case Strings.Tile.goldDiscChar: sound.playGoldDisc(); state.collectedGoldDiscs += 1; state.bumpScore(by: 5); popPoints(5); startGoldDiscMode()
        default:                        sound.playDotBlip(); state.collectedDots += 1; state.bumpScore(by: 1)
        }
        refreshHUD(); checkLevelComplete3D()
    }

    override func fire() {
        guard let faceDir = workerController.direction else { return }
        guard waterGun.consumePellet() else { return }
        sound.playWaterGunShoot()
        refreshHUD()
        let dir = (x: faceDir == .left ? -1 : faceDir == .right ? 1 : 0,
                   y: faceDir == .up ? -1 : faceDir == .down ? 1 : 0)
        let pellet = SpriteFactory.waterPelletVisual(radius: 12)
        pellet.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.5)))
        pellet.isHidden = true
        spriteLayer.addChild(pellet)
        let mapNode = SpriteFactory.waterPelletVisual(radius: mapCell * 0.22)
        mapNode.position = mapLocal(px, py); mapNode.zPosition = 3; mapLayer.addChild(mapNode)
        shots.append(Shot(x: px, y: py, dir: dir, node: pellet,
                          nativeH: max(1, pellet.calculateAccumulatedFrame().height), mapNode: mapNode, alive: true))
    }

    // Pickup hooks (iso has its own pickup rendering via isoPickups, not billboards)
    override func hidePickupInWorld(col: Int, row: Int) {
        let key = mapKey(col, row)
        isoPickups[key]?.isHidden = true
        mapPickups[key]?.isHidden = true
    }
    override func grayPickupInWorld(col: Int, row: Int) {
        let key = mapKey(col, row)
        isoPickups[key]?.alpha = 0.55
        mapPickups[key]?.alpha = 0.55
    }
    override func ungrayPickupInWorld(col: Int, row: Int) {
        let key = mapKey(col, row)
        collected.remove(key)
        isoPickups[key]?.alpha = 1
        mapPickups[key]?.alpha = 1
    }
    override func findBrownBoxNode(col: Int, row: Int) -> SKNode? {
        isoPickups[mapKey(col, row)]
    }

    override func moveShots() {
        let speed = 0.22
        for i in shots.indices where shots[i].alive {
            shots[i].x += Double(shots[i].dir.x) * speed
            shots[i].y += Double(shots[i].dir.y) * speed
            if isWall(shots[i].x, shots[i].y) { shots[i].alive = false; continue }
            let sgx = Int(shots[i].x.rounded(.down)), sgy = rowsCount - 1 - Int(shots[i].y.rounded(.down))
            for e in bossController.entities {
                let bg = e.mover?.grid ?? e.ai.grid
                guard Int(bg.x) == sgx, Int(bg.y) == sgy else { continue }
                let hitCol = shots[i].x, hitRow = shots[i].y
                let hitPt = proj(hitCol, hitRow, 0)
                let splash = SpriteFactory.waterSplash(spread: 1.0)
                bossController.splash(boss: e.node)
                shots[i].alive = false
                sound.playWaterGunSplash(); state.bumpScore(by: 50); popPoints(50); refreshHUD()
                splash.position = CGPoint(x: hitPt.x, y: hitPt.y + 15)
                splash.zPosition = CGFloat(hitRow) * 4 + 2
                spriteLayer.addChild(splash)
                break
            }
        }
        for s in shots where !s.alive { s.node.removeFromParent(); s.mapNode.removeFromParent() }
        shots.removeAll { !$0.alive }
    }

    // Point popup in iso world (overhead projection at Pete's iso position)
    override func popPointsInWorld(_ n: Int) {
        let world = proj(Double(px), Double(py), 0)
        let big = SKLabelNode(fontNamed: Strings.Font.menloBold)
        big.text = Strings.Score.popup(n)
        big.fontSize = max(30, isoTW * 0.45); big.fontColor = .systemYellow
        big.position = CGPoint(x: world.x + isoWorld.position.x, y: world.y + isoWorld.position.y + isoTW - 37)
        big.zPosition = 600
        addChild(big)
        big.run(.sequence([.group([.moveBy(x: 0, y: 55, duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
    }

    override func bossDidGetCaptured(name: String, points: Int, at position: CGPoint) {
        state.bumpScore(by: points); sound.playCaptureBoss(streak: max(1, points / 100)); refreshHUD()
        popPoints(points)
    }

    private func captureFade(_ node: SKNode?) {
        guard let node else { return }
        node.removeAllActions()
        node.run(.sequence([.group([.scale(by: 1.5, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
    }

    override func makeNextLevelScene() -> Scene3D { IsoScene(size: size) }
    override func makeRestartScene()   -> Scene3D { IsoScene(size: size) }

    // MARK: - Input (steer at junctions, relative to facing)
    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        if let s = gameOverScreen {
            #if os(macOS)
            s.handleKey(usernameKeyCode(for: event), shift: event.modifierFlags.contains(.shift))
            #else
            s.handleKey(code, shift: false)
            #endif
            return
        }
        switch code {
        case KeyCode.esc:                       exit()
        case KeyCode.keyP:                      togglePause()
        case KeyCode.space:                     if !event.isARepeat { fire() }
        case KeyCode.arrowUp,    KeyCode.keyW:  workerController.queueDirection(.up)
        case KeyCode.arrowRight, KeyCode.keyD:  workerController.queueDirection(.right)
        case KeyCode.arrowDown,  KeyCode.keyS:  workerController.queueDirection(.down)
        case KeyCode.arrowLeft,  KeyCode.keyA:  workerController.queueDirection(.left)
        default:                                break
        }
    }
    override func keyUp(with event: NSEvent) { pressed.remove(Int(event.keyCode)) }

    // MARK: - On-screen joystick + fire button (drive the same tank input)
    override func buildControls() {
        if !ControlMode.current.showsControl { return }
        controlsShown = true
        let fireOnLeft = !ControlMode.current.onLeft
        fireButtonCenter = CGPoint(x: fireOnLeft ? fireButtonRadius : size.width - fireButtonRadius, y: fireButtonRadius + 15)
        let ring = SKShapeNode(circleOfRadius: fireButtonRadius)
        ring.position = fireButtonCenter
        ring.fillColor = SKColor(white: 1, alpha: 0.14); ring.strokeColor = SKColor(white: 1, alpha: 0.5)
        ring.lineWidth = 2; ring.zPosition = 300
        addChild(ring)

        joystickCenter = CGPoint(x: fireOnLeft ? size.width - joystickRadius : joystickRadius, y: joystickRadius + 15)
        let base = SKShapeNode(circleOfRadius: joystickRadius)
        base.position = joystickCenter
        base.fillColor = SKColor(white: 1, alpha: 0.06); base.strokeColor = SKColor(white: 1, alpha: 0.5)
        base.lineWidth = 2; base.zPosition = 300
        addChild(base)
        if ControlMode.current.showsStick { addStickThumb(); return }
        let dirs: [(String, CGFloat, String)] = [("up", .pi / 2, "\u{25B2}"), ("left", .pi, "\u{25C0}"),
                                                 ("down", -.pi / 2, "\u{25BC}"), ("right", 0, "\u{25B6}")]
        for (name, ang, glyph) in dirs {
            let w = SKShapeNode(path: dpadWedgePath(centerAngle: ang, inner: joystickDeadzone, outer: joystickRadius))
            w.position = joystickCenter
            w.fillColor = SKColor(white: 1, alpha: 0.12); w.strokeColor = .clear
            w.lineWidth = 0; w.zPosition = 301
            addChild(w); dpadWedges[name] = w
            let arrow = SKLabelNode(text: glyph)
            arrow.fontSize = 24; arrow.fontColor = SKColor(white: 1, alpha: 0.7)
            arrow.verticalAlignmentMode = .center; arrow.horizontalAlignmentMode = .center
            let r = (joystickDeadzone + joystickRadius) / 2
            arrow.position = CGPoint(x: joystickCenter.x + cos(ang) * r, y: joystickCenter.y + sin(ang) * r)
            arrow.zPosition = 302
            addChild(arrow)
        }
        let xPath = CGMutablePath()
        for k in 0..<4 {
            let t = CGFloat.pi / 4 + CGFloat(k) * CGFloat.pi / 2
            xPath.move(to: CGPoint(x: cos(t) * joystickDeadzone, y: sin(t) * joystickDeadzone))
            xPath.addLine(to: CGPoint(x: cos(t) * joystickRadius, y: sin(t) * joystickRadius))
        }
        let xlines = SKShapeNode(path: xPath)
        xlines.position = joystickCenter
        xlines.strokeColor = SKColor(white: 1, alpha: 0.5); xlines.lineWidth = 2
        xlines.zPosition = 301
        addChild(xlines)
    }

    // Iso steers the REAL WorkerController, so its joystick is the continuous-steer
    // pointer of the 2D modes, not the 3D wedge/hold dpad: press anywhere in the ring
    // and steer toward the pointer (deadzone-gated, no radius cap so dragging out or
    // through the centre never strands the press), release just recenters the thumb.
    private var joyActive = false
    private var joyFinger: Int?

    private func joystickDirection(_ p: CGPoint) -> MoveDirection? {
        let dx = p.x - joystickCenter.x, dy = p.y - joystickCenter.y
        guard (dx * dx + dy * dy).squareRoot() >= joystickDeadzone else { return nil }
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .up : .down
    }
    @discardableResult private func joyBegin(_ p: CGPoint) -> Bool {
        guard !isUserPaused, !dying else { return false }
        if !controlsShown { fire(); return false }
        if radius(p, joystickCenter) <= joystickRadius {
            joyActive = true
            moveStickThumb(to: p, release: false)
            if let d = joystickDirection(p) { workerController.queueDirection(d) }
            return true
        }
        if radius(p, fireButtonCenter) <= fireButtonRadius { fire() }
        return false
    }
    private func joyMove(_ p: CGPoint) {
        guard joyActive else { return }
        moveStickThumb(to: p, release: false)
        if let d = joystickDirection(p) { workerController.queueDirection(d) }
    }
    private func joyEnd() {
        guard joyActive else { return }
        joyActive = false
        moveStickThumb(to: joystickCenter, release: true)
    }

    override func mouseDown(with event: NSEvent) {
        if let s = gameOverScreen { s.handleTap(at: s.convert(event.location(in: self), from: self)); return }
        if usingTouch { return }
        joyBegin(event.location(in: self))
    }
    override func mouseDragged(with event: NSEvent) {
        if usingTouch { return }
        joyMove(event.location(in: self))
    }
    override func mouseUp(with event: NSEvent) {
        if usingTouch { return }
        joyEnd()
    }

    override func touchBegan(finger: Int, at p: CGPoint) {
        if gameOverScreen != nil { return }
        usingTouch = true
        if joyBegin(p), joyFinger == nil { joyFinger = finger }
    }
    override func touchMoved(finger: Int, at p: CGPoint) {
        if finger == joyFinger { joyMove(p) }
    }
    override func touchEnded(finger: Int, at p: CGPoint) {
        if finger == joyFinger { joyFinger = nil; joyEnd() }
    }

    // MARK: - Layout / projection (IsoScene-specific)
    private let maxVoxelDist = 30.0
    override var eyeHeight: CGFloat { 0.7 }
    override var wallHeightScale: CGFloat { 0.5 }
    private struct WallRun {
        var firstCol: Int, lastCol: Int
        var yLoA: CGFloat, yHiA: CGFloat
        var yLoB: CGFloat, yHiB: CGFloat
        var depthSum: Double, n: Int, side: Int, par: Int
    }

    required init?(coder: NSCoder) { fatalError(Strings.System.initCoderUnsupported) }
    override init(size: CGSize) { super.init(size: size) }
}
