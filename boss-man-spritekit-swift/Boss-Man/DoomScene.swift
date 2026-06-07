import SpriteKit
import AppKit

// 3D bonus round: the office maze (level 1) rendered first/third-person with flat
// 2D graphics — a Wolfenstein-style DDA raycaster for the walls, a smooth blended
// sunset sky, and billboarded game sprites (pellets, gold discs, bosses) standing
// in the corridors. The camera trails behind Pete so you see him walking ahead of
// you. A top-down radar sits at the bottom. Common to both ports.
final class DoomScene: Scene3D {

    // MARK: - Layout / projection
    override var columns: Int { 200 }
    private let planeScale = 0.5773          // tan(fov/2), fov 60° (no tan() on wasm)
    private var bars: [SKShapeNode] = []

    private var travelerMirror: SKNode?             // billboard mirror; the REAL node keeps its SKAction walk (smooth) uncllobbered in the scene root
    private var travelerMirrorEmoji = ""
    private var travelerNativeH: CGFloat = 40
    private var mapTraveler: SKNode?
    private var mapTravelerEmoji = ""
    private var travPrevCol = 0.0                   // last continuous column, to derive the smooth facing each frame
    private var travFlip: CGFloat = 1               // shared by the billboard + minimap so both face the way it last moved

    override func buildSky() {
        // 2D office palette: a dark ceiling (maze background) blending toward the
        // horizon over the dark checker-floor colour. One thin band per device row
        // so the gradient is smooth, then baked to a single sprite (the bands are
        // static, so this is ~240 fewer draw calls per frame on Apple).
        // Ceiling + floor derive from the level's cubicle colour (dark at the ceiling,
        // a touch brighter at the horizon) so the whole 3D environment matches the level.
        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        let tree = SKNode()
        let skyBottom = viewMidY, skyTop = size.height
        let n = max(1, Int(skyTop - skyBottom))
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(max(1, n - 1))      // 0 horizon .. 1 ceiling
            let factor = 0.18 + (0.05 - 0.18) * t            // cube brightness: horizon -> ceiling
            let col = cube.blended(withFraction: 1 - factor, of: .black) ?? cube
            let band = SKShapeNode(rect: CGRect(x: 0, y: skyBottom + CGFloat(i), width: size.width, height: 2))
            band.fillColor = col; band.strokeColor = .clear
            tree.addChild(band)
        }
        let ground = SKShapeNode(rect: CGRect(x: 0, y: radarH, width: size.width, height: viewMidY - radarH))
        ground.fillColor = cube.blended(withFraction: 0.88, of: .black) ?? cube   // dark level-tinted floor base
        ground.strokeColor = .clear
        tree.addChild(ground)
        addBaked(tree, to: self, z: -3)

        // Alternating floor-tile checker (cast per frame in castFloor), drawn above the
        // baked ground (z -3) and below the walls (z 0). Two nodes, one per shade.
        floorA.fillColor = cube.blended(withFraction: 0.87, of: .black) ?? cube   // ~cube * 0.13
        floorB.fillColor = cube.blended(withFraction: 0.76, of: .black) ?? cube   // ~cube * 0.24
        floorA.strokeColor = .clear; floorB.strokeColor = .clear
        floorA.zPosition = -2; floorB.zPosition = -2
        floorA.isAntialiased = false; floorB.isAntialiased = false
        addChild(floorA); addChild(floorB)
    }

    // Floor-cast the maze floor as an alternating checker so the tile grid reads in 3D
    // (matches the C++ DoomScene::drawFloor). Each scene row below the horizon maps to a
    // perpendicular distance; the world position sweeps left-ray -> right-ray across the
    // row; cell parity picks the shade. Coalesced into per-row run rects in two paths.
    private func castFloor() {
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        let rdx0 = dirX - planeX, rdy0 = dirY - planeY
        let rdx1 = dirX + planeX, rdy1 = dirY + planeY
        let W = size.width, rowH: CGFloat = 0.25
        let pathA = CGMutablePath(), pathB = CGMutablePath()
        var yu = radarH
        while yu < viewMidY - 0.5 {
            let distFromHorizon = Double(viewMidY - yu)
            let d = Double(viewH) / (2.0 * distFromHorizon)
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
        floorA.path = pathA; floorB.path = pathB
    }

    override func buildColumns() {
        for _ in 0..<columns {
            let bar = SKShapeNode()
            bar.strokeColor = .clear; bar.isAntialiased = false; bar.zPosition = 0
            addChild(bar); bars.append(bar)
        }
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
        pete.alpha = 0.2                                      // Pete fades as Bill (z 500, in front) takes him
        node.stopWalking()
        let nh = bossNativeH[ObjectIdentifier(node)] ?? max(1, node.calculateAccumulatedFrame().height)
        node.isHidden = false
        node.setScale(viewH * 0.42 / nh)                     // Pete's size, never larger
        node.position = CGPoint(x: size.width / 2, y: radarH + viewH * 0.5)
        node.zPosition = 500
        for e in bossController.entities where e.node !== node { e.node.isHidden = true }   // only the catcher shows
        for (_, l) in bossNames { l.isHidden = true }
        for s in shots { s.node.isHidden = true }
        deathFramesLeft = deathFrames
    }

    // MARK: - Per-frame
    override func update(_ currentTime: TimeInterval) {
        if isUserPaused || gameOver { return }
        if dying { updateDeath(); return }
        step(); render()
    }

    override func render() {
        throbClock += 1.0 / 60.0
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        // Camera trails behind Pete; pull in if it would sit inside a wall.
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back; camY = py - dirY * back
        castFloor()

        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        let w = size.width / CGFloat(columns)

        // Phase 1: DDA — zbuf (first hit) + wallCells (all hits, for per-cell face pass).
        var wallCells = Set<Int>()
        for i in 0..<columns {
            let cameraX = 2.0 * (Double(i) + 0.5) / Double(columns) - 1.0
            let rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX
            var mapX = Int(camX.rounded(.down)), mapY = Int(camY.rounded(.down))
            let ddx = rdx == 0 ? 1e30 : abs(1 / rdx), ddy = rdy == 0 ? 1e30 : abs(1 / rdy)
            var stepX = 0, stepY = 0, sideX = 0.0, sideY = 0.0
            if rdx < 0 { stepX = -1; sideX = (camX - Double(mapX)) * ddx } else { stepX = 1; sideX = (Double(mapX) + 1 - camX) * ddx }
            if rdy < 0 { stepY = -1; sideY = (camY - Double(mapY)) * ddy } else { stepY = 1; sideY = (Double(mapY) + 1 - camY) * ddy }
            var firstHit = true, guardN = 0
            while guardN < 300 {
                guardN += 1
                let dEntry: Double
                if sideX < sideY { dEntry = sideX; sideX += ddx; mapX += stepX }
                else             { dEntry = sideY; sideY += ddy; mapY += stepY }
                if mapY < 0 || mapY >= rowsCount || mapX < 0 || mapX >= colsCount { break }
                if map[mapY][mapX] != Strings.Tile.wallChar { continue }
                let perp = max(0.05, dEntry)
                if firstHit { zbuf[i] = perp; firstHit = false }
                wallCells.insert(mapY * colsCount + mapX)
            }
            if firstHit { zbuf[i] = 1e9 }
        }
        let pTileX = Int(px.rounded(.down)), pTileY = Int(py.rounded(.down))
        for dy in -1...1 { for dx in -1...1 {
            let tx = pTileX + dx, ty = pTileY + dy
            if tx >= 0 && tx < colsCount && ty >= 0 && ty < rowsCount && map[ty][tx] == Strings.Tile.wallChar {
                wallCells.insert(ty * colsCount + tx)
            }
        }}

        // Phase 2: per-cell face → per-column arrays.
        // Each exposed wall face is projected directly onto screen columns using the same
        // 4-corner invDet math as VoxelScene, then the perp distance at each column is
        // computed analytically. Only columns where this face is the closest win.
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        var cTop  = [CGFloat](repeating: 0,   count: columns)
        var cBot  = [CGFloat](repeating: 0,   count: columns)
        var cDist = [Double] (repeating: 1e9, count: columns)
        var cSide = [Int]    (repeating: 0,   count: columns)
        var cFace = [Int]    (repeating: -1,  count: columns)
        var cPar  = [Int]    (repeating: 0,   count: columns)
        let lCamX = camX, lCamY = camY, lCols = columns
        let screenCol = { (wx: Double, wy: Double) -> Int in
            let rX = wx - lCamX, rY = wy - lCamY
            let d = invDet * (-planeY * rX + planeX * rY)
            if d < 0.05 { return d < 0 ? -1 : lCols }
            let sX = invDet * (dirY * rX - dirX * rY)
            return Int(Double(lCols) * 0.5 * (1.0 + sX / d))
        }
        for key in wallCells {
            let tx = key % colsCount, ty = key / colsCount
            for (side, faceV, adx, ady) in [(0, tx, -1, 0), (0, tx + 1, 1, 0), (1, ty, 0, -1), (1, ty + 1, 0, 1)] {
                let adjX = tx + adx, adjY = ty + ady
                let exposed = adjX < 0 || adjX >= colsCount || adjY < 0 || adjY >= rowsCount
                           || map[adjY][adjX] != Strings.Tile.wallChar
                if !exposed { continue }
                let onOpen = side == 0 ? (adx < 0 ? camX <= Double(faceV) : camX >= Double(faceV))
                                       : (ady < 0 ? camY <= Double(faceV) : camY >= Double(faceV))
                if !onOpen { continue }
                let wx0 = side == 0 ? Double(faceV) : Double(tx),     wy0 = side == 0 ? Double(ty)     : Double(faceV)
                let wx1 = side == 0 ? Double(faceV) : Double(tx + 1), wy1 = side == 0 ? Double(ty + 1) : Double(faceV)
                let colL = max(0, min(screenCol(wx0, wy0), screenCol(wx1, wy1)))
                let colR = min(columns - 1, max(screenCol(wx0, wy0), screenCol(wx1, wy1)))
                if colL > colR { continue }
                let fid = side == 0 ? faceV * 2 : faceV * 2 + 1
                let par = side == 0 ? (faceV + ty) & 1 : (tx + faceV) & 1
                for c in colL...colR {
                    let cX = 2.0 * (Double(c) + 0.5) / Double(columns) - 1.0
                    let perp: Double
                    if side == 0 {
                        let rdx = dirX + planeX * cX; guard abs(rdx) > 1e-10 else { continue }
                        let p = (Double(faceV) - camX) / rdx; if p < 0.05 { continue }; perp = p
                    } else {
                        let rdy = dirY + planeY * cX; guard abs(rdy) > 1e-10 else { continue }
                        let p = (Double(faceV) - camY) / rdy; if p < 0.05 { continue }; perp = p
                    }
                    if perp >= cDist[c] { continue }
                    let lineH = min(viewH * 4, viewH / CGFloat(perp))
                    cTop[c] = viewMidY + lineH / 2; cBot[c] = viewMidY - lineH / 2
                    cDist[c] = perp; cSide[c] = side; cFace[c] = fid; cPar[c] = par
                }
            }
        }
        for i in 0..<columns { if cDist[i] < zbuf[i] { zbuf[i] = cDist[i] } }

        // Phase 3: merge adjacent same-face columns into one straight-edged quad.
        var bar = 0
        var i = 0
        while i < columns {
            if cFace[i] < 0 { i += 1; continue }
            var j = i
            while j + 1 < columns && cFace[j + 1] == cFace[i] && cPar[j + 1] == cPar[i] { j += 1 }
            let xL = CGFloat(i) * w, xR = CGFloat(j + 1) * w + 1
            var topL = cTop[i], topR = cTop[j], botL = cBot[i], botR = cBot[j]
            if j > i {
                let cxL = (CGFloat(i) + 0.5) * w, cxR = (CGFloat(j) + 0.5) * w
                let mT = (cTop[j] - cTop[i]) / (cxR - cxL), mB = (cBot[j] - cBot[i]) / (cxR - cxL)
                topL = cTop[i] + mT * (xL - cxL); topR = cTop[i] + mT * (xR - cxL)
                botL = cBot[i] + mB * (xL - cxL); botR = cBot[i] + mB * (xR - cxL)
            }
            let p = CGMutablePath()
            p.move(to: CGPoint(x: xL, y: botL)); p.addLine(to: CGPoint(x: xL, y: topL))
            p.addLine(to: CGPoint(x: xR, y: topR)); p.addLine(to: CGPoint(x: xR, y: botR))
            p.closeSubpath()
            let n = bars[bar]; bar += 1
            n.path = p; n.isHidden = false
            let f = CGFloat(cSide[i] == 1 ? 0.62 : 1.0) * (cPar[i] == 1 ? 1.0 : 0.82)
            n.fillColor = cube.blended(withFraction: 1 - f, of: .black) ?? cube
            i = j + 1
        }
        for k in bar..<bars.count { bars[k].isHidden = true }
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
    }

    override func updateMap() {
        super.updateMap()
        if let tnode = travelerSpawner?.node, let info = travelerSpawner?.activeTraveler {
            if mapTravelerEmoji != info.emoji {
                mapTraveler?.removeFromParent()
                let n = emojiBillboard(info.emoji, mapCell * 1.2)
                n.zPosition = 6; mapLayer.addChild(n)
                mapTraveler = n; mapTravelerEmoji = info.emoji
            }
            mapTraveler?.isHidden = false
            mapTraveler?.position = mapLocal(Double(tnode.position.x) / 32.0, Double(rowsCount) - Double(tnode.position.y) / 32.0)
            if let mt = mapTraveler { mt.xScale = abs(mt.xScale) * travFlip }   // face travel direction (projectSprites set travFlip this frame)
        } else {
            mapTraveler?.isHidden = true
        }
    }

    private func projectSprites(dirX: Double, dirY: Double, planeX: Double, planeY: Double) {
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        // `bottom` = the sprite's LOCAL frame.minY (feet offset from origin); centred sprites pass -nativeH/2.
        var all: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, x: Double, y: Double, maxH: CGFloat, name: String?, bottom: CGFloat)] = []
        for b in billboards where b.alive {
            all.append((b.node, b.nativeH, b.worldH, b.x, b.y, .greatestFiniteMagnitude, nil, -b.nativeH / 2))
        }
        for e in bossController.entities {
            guard let g = bossGrid[ObjectIdentifier(e.node)] else { continue }
            let id = ObjectIdentifier(e.node)
            let bx = g.0 + 0.5, by = Double(rowsCount) - 0.5 - g.1   // gridMap bottom-up -> raster top-down (smooth)
            let nh = bossNativeH[id] ?? 36
            all.append((e.node, nh, 0.3, bx, by, .greatestFiniteMagnitude, e.name, bossFeet[id] ?? -nh / 2))   // no size cap (cap made him sink); worldH 0.3 keeps him ~Pete-size at the catch
        }
        for s in shots where s.alive {
            all.append((s.node, s.nativeH, 0.32, s.x, s.y, .greatestFiniteMagnitude, nil, -s.nativeH / 2))
        }
        // The traveler walks in 2D scene coords; pull its node into the sprite layer and project it as a
        // billboard at its current grid tile (gridMap bottom-up -> raster top-down, same flip as bosses).
        // Smooth traveler (matches ISO): keep the real node's SKAction walk UNCLOBBERED in the scene root
        // (hidden) and project a SEPARATE mirror from its CONTINUOUS position, so it glides in-lane instead of
        // hopping the discrete grid. projectSprites overwrites node.position, so the real node never enters `all`.
        if let tnode = travelerSpawner?.node, let info = travelerSpawner?.activeTraveler {
            tnode.isHidden = true
            let nc = Double(tnode.position.x) / 32.0           // smooth facing from the CONTINUOUS column (matches ISO); realE.xScale only flips on a discrete grid step and read stale here
            let dCol = nc - travPrevCol
            if abs(dCol) > 0.001, abs(dCol) < 2 { travFlip = info.facesRight ? (dCol < 0 ? -1 : 1) : (dCol < 0 ? 1 : -1) }
            travPrevCol = nc
            if travelerMirror == nil || travelerMirrorEmoji != info.emoji {
                travelerMirror?.removeFromParent()
                let wrap = SKNode(); let e = emojiBillboard(info.emoji, 40); e.name = Strings.NodeName.travelerEmoji
                wrap.addChild(e); spriteLayer.addChild(wrap)
                travelerMirror = wrap; travelerMirrorEmoji = info.emoji
                travelerNativeH = 40
            }
            if let m = travelerMirror {
                if let mE = m.childNode(withName: Strings.NodeName.travelerEmoji) {
                    mE.xScale = abs(mE.xScale) * travFlip   // flip the CHILD so it survives the wrapper's projection setScale
                }
                all.append((m, travelerNativeH, 0.42, Double(tnode.position.x) / 32.0, Double(rowsCount) - Double(tnode.position.y) / 32.0, .greatestFiniteMagnitude, nil, -travelerNativeH / 2))
            }
        } else {
            travelerMirror?.isHidden = true
        }
        for item in all {
            let node = item.node
            let label = item.name.map { bossNameplate(for: node, text: $0) }
            label?.isHidden = true
            let relX = item.x - camX, relY = item.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)   // depth
            guard tY > 0.15 else { node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            // Occlude only when walls are nearer than the sprite across its whole footprint.
            // Sampling a window (not one column) stops the per-step blink when the centre
            // column straddles a side-opening edge as a boss walks. Clamp the column so a sprite
            // whose centre sits just past the screen edge still occludes against the edge wall —
            // skipping it leaked dots/pickups onto the left/right borders.
            let colC = max(0, min(columns - 1, col))
            var wallZ = zbuf[colC]
            for c in max(0, colC - 4)...min(columns - 1, colC + 4) { wallZ = max(wallZ, zbuf[c]) }
            if tY > wallZ + 0.3 { node.isHidden = true; continue }
            if tY > 18 { node.isHidden = true; continue }       // far cull
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { node.isHidden = true; continue }
            // TRUE 1-point perspective, identical to the dots: size = viewH/depth, feet planted on
            // the floor row at THIS depth. maxH only clamps the size at point-blank range so the
            // catch close-up isn't a full-screen sprite; it never moves the floor.
            let targetH = min(viewH / CGFloat(tY) * item.worldH, item.maxH)
            var s = targetH / item.nativeH
            // Post-spawn pulse: a respawned boss throbs while it can't yet catch Pete
            // (spawn grace / immobilized), then settles to full size. Feet stay planted
            // because position uses s below. Matches the C++ DoomScene throb.
            if item.name != nil, let boss = item.node as? PixelPerson, bossController.isImmobilized(boss: boss) {
                s *= 1 + 0.18 * abs(sin(throbClock * .pi * 3))
            }
            node.isHidden = false
            node.setScale(s)
            let floorY = viewMidY - (viewH / CGFloat(tY)) / 2
            node.position = CGPoint(x: screenX, y: floorY - item.bottom * s)
            node.zPosition = min(40, CGFloat(2 + 30 / tY))      // nearer over farther, but always behind Pete
            if let label = label {
                label.isHidden = false
                label.fontSize = max(13, min(24, targetH * 0.16))
                label.position = CGPoint(x: screenX, y: floorY + targetH + label.fontSize * 0.7)
            }
        }
    }

    override func restartDoom() {
        gameOverScreen?.removeFromParent(); gameOverScreen = nil
        let bonus = DoomScene(size: size)
        bonus.scaleMode = scaleMode
        bonus.practiceMode = practiceMode
        bonus.startingLevel = startingLevel
        view?.presentScene(bonus, transition: .fade(withDuration: 0.5))
    }
}
