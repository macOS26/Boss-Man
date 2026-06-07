import SpriteKit
import AppKit

final class VoxelScene: Scene3D {

    // MARK: - Layout / projection
    private let planeScale = 1.2              // tan(fov/2): wide ~100° FOV so a big swath of maze shows left/right
    // Overhead-ish framing so the whole maze reads: a raised camera (eyeHeight > 0.5 drops the
    // walls below the horizon = looking DOWN on the maze) plus shorter walls you can see over.
    // 0.5 / 1.0 is the flat eye-level look; raise eyeHeight and lower wallHeightScale to tilt down.
    private let eyeHeight: CGFloat = 0.7
    private let wallHeightScale: CGFloat = 0.5
    private let maxVoxelDist = 30.0          // brightness-fade reference; keeps mid-range walls bright
    private let wallFar = 40.0
    private var wallQuads: [SKShapeNode] = []   // painter's-sorted wall face + cap quads (grows lazily)

    private var travelerMirror: SKNode?             // billboard mirror; the REAL node keeps its SKAction walk (smooth) uncllobbered in the scene root
    private var travelerMirrorEmoji = ""
    private var travelerNativeH: CGFloat = 40
    private var mapTraveler: SKNode?
    private var mapTravelerEmoji = ""
    private var travPrevCol = 0.0                   // last continuous column, to derive the smooth facing each frame
    private var travFlip: CGFloat = 1               // shared by the billboard + minimap so both face the way it last moved

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
        let pathA = CGMutablePath(), pathB = CGMutablePath(), pathFar = CGMutablePath()
        var yu = radarH
        while yu < viewMidY - 0.5 {
            let distFromHorizon = Double(viewMidY - yu)
            let d = Double(viewH) * Double(eyeHeight) / distFromHorizon
            if d > 13 {   // checker cells shrink below ~1px here and alias to garbage; fill solid to the horizon
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
        node.position = CGPoint(x: size.width / 2, y: peteBaseY)   // grounded right where Pete stands, so you see the catcher
        node.zPosition = 500
        for e in bossController.entities where e.node !== node { e.node.isHidden = true }   // only the catcher shows
        for (_, l) in bossNames { l.isHidden = true }
        for s in shots { s.node.isHidden = true }
        deathFramesLeft = deathFrames
    }

    // MARK: - Per-frame
    override func render() {
        throbClock += 1.0 / 60.0
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        // Camera trails behind Pete; pull in if it would sit inside a wall.
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back; camY = py - dirY * back
        castFloor()

        // Painter's voxel walls. Per column, march the WHOLE ray and record every wall as a FULL,
        // UNCLIPPED segment: an exposed FRONT face (open->wall) + the run's flat TOP cap. Adjacent
        // columns hitting the same face merge into one straight-edged quad (inverse depth is linear in
        // screen-x for a flat face, so the interpolation is exact — DOOM-quality, no seams/jaggies).
        // Because nothing is clipped, the edges never bend; occlusion comes purely from DRAW ORDER:
        // all quads are sorted far->near and the nearer ones paint over the farther, so the whole maze
        // reads deep AND clean.
        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        struct VQuad { var p0, p1, p2, p3: CGPoint; var color: SKColor; var depth: Double; var isCap: Bool }
        var quads: [VQuad] = []
        var tops = Set<Int>()                     // wall cells in view; faces + caps both projected per-cell
        for col in 0..<columns {
            let cameraX = 2.0 * (Double(col) + 0.5) / Double(columns) - 1.0
            let rdx = dirX + planeX * cameraX, rdy = dirY + planeY * cameraX
            var mapX = Int(camX.rounded(.down)), mapY = Int(camY.rounded(.down))
            let ddx = rdx == 0 ? 1e30 : abs(1 / rdx), ddy = rdy == 0 ? 1e30 : abs(1 / rdy)
            var stepX = 0, stepY = 0, sideX = 0.0, sideY = 0.0
            if rdx < 0 { stepX = -1; sideX = (camX - Double(mapX)) * ddx } else { stepX = 1; sideX = (Double(mapX) + 1 - camX) * ddx }
            if rdy < 0 { stepY = -1; sideY = (camY - Double(mapY)) * ddy } else { stepY = 1; sideY = (Double(mapY) + 1 - camY) * ddy }
            var firstHit = true
            var guardN = 0
            while guardN < 300 {
                guardN += 1
                let dEntry: Double
                if sideX < sideY { dEntry = sideX; sideX += ddx; mapX += stepX }
                else             { dEntry = sideY; sideY += ddy; mapY += stepY }
                if mapY < 0 || mapY >= rowsCount || mapX < 0 || mapX >= colsCount { break }
                if dEntry > wallFar { break }
                if map[mapY][mapX] != Strings.Tile.wallChar { continue }
                let dN = max(0.05, dEntry)
                if firstHit { zbuf[col] = dN; firstHit = false }
                tops.insert(mapY * colsCount + mapX)
            }
            if firstHit { zbuf[col] = 1e9 }
        }
        let pTileX = Int(px.rounded(.down)), pTileY = Int(py.rounded(.down))
        for dy in -1...1 { for dx in -1...1 {
            let tx = pTileX + dx, ty = pTileY + dy
            if tx >= 0 && tx < colsCount && ty >= 0 && ty < rowsCount && map[ty][tx] == Strings.Tile.wallChar {
                tops.insert(ty * colsCount + tx)
            }
        }}
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        let wallH = Double(wallHeightScale)
        // Per-cell face rendering: project each exposed wall face from tops directly, same math as caps.
        // Covers faces that column-sweep DDA misses (nearly-parallel rays skip the face entirely).
        for key in tops {
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
                var pts = [CGPoint](), rawDs = [Double]()
                for (wx, wy, wz) in [(wx0, wy0, 0.0), (wx0, wy0, wallH), (wx1, wy1, wallH), (wx1, wy1, 0.0)] {
                    let relX = wx - camX, relY = wy - camY
                    let raw = invDet * (-planeY * relX + planeX * relY)
                    rawDs.append(raw)
                    let depth = max(0.05, raw)
                    let transX = invDet * (dirY * relX - dirX * relY)
                    pts.append(CGPoint(x: size.width / 2 * (1 + CGFloat(transX / depth)),
                                       y: viewMidY + viewH * CGFloat(wz - Double(eyeHeight)) / CGFloat(depth)))
                }
                let rawAvg = (rawDs[0] + rawDs[1] + rawDs[2] + rawDs[3]) / 4
                if rawAvg < -0.5 { continue }
                let dAvg = max(0.05, rawAvg)
                if dAvg > wallFar { continue }
                let par = side == 0 ? (faceV + ty) & 1 : (tx + faceV) & 1
                let faceF = CGFloat(side == 1 ? 0.62 : 1.0) * (par == 1 ? 1.0 : 0.82)
                let baseColor = cube.blended(withFraction: 1 - faceF, of: .black) ?? cube
                let fogT = CGFloat(min(1.0, dAvg / wallFar)) * 0.85
                let color = baseColor.blended(withFraction: fogT, of: .black) ?? baseColor
                quads.append(VQuad(p0: pts[0], p1: pts[1], p2: pts[2], p3: pts[3], color: color, depth: dAvg, isCap: false))
            }
        }
        // Wall TOPS: each cell's flat top is a real box face in 3D, so project its 4 corners with TRUE
        // 1-point perspective (corners projected independently, like the dots) — never distorts to a triangle.
        let capZ = wallHeightScale - eyeHeight
        let corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for key in tops {
            let cx = Double(key % colsCount), cy = Double(key / colsCount)
            var pp = [CGPoint](); pp.reserveCapacity(4)
            var dsum = 0.0
            for (ox, oy) in corners {
                let relX = (cx + Double(ox)) - camX, relY = (cy + Double(oy)) - camY
                let raw = invDet * (-planeY * relX + planeX * relY)
                let depth = max(0.05, raw)
                dsum += raw
                let transX = invDet * (dirY * relX - dirX * relY)
                pp.append(CGPoint(x: size.width / 2 * (1 + CGFloat(transX / depth)),
                                  y: viewMidY + viewH * CGFloat(capZ) / CGFloat(depth)))
            }
            if dsum / 4 < -0.5 { continue }
            let dAvg = max(0.05, dsum / 4)
            if dAvg > wallFar { continue }
            let par = (Int(cx) + Int(cy)) & 1
            let f = CGFloat(par == 1 ? 1.0 : 0.82)
            let base = cube.blended(withFraction: 1 - f, of: .black) ?? cube
            let capBase = base.blended(withFraction: 0.3, of: .white) ?? base
            let capFogT = CGFloat(min(1.0, dAvg / wallFar)) * 0.85
            let color = capBase.blended(withFraction: capFogT, of: .black) ?? capBase
            quads.append(VQuad(p0: pp[0], p1: pp[1], p2: pp[2], p3: pp[3], color: color, depth: dAvg, isCap: true))
        }
        quads.sort { a, b in
            if a.isCap != b.isCap { return !a.isCap }
            return a.depth > b.depth
        }
        var qi = 0
        for q in quads {
            let n: SKShapeNode
            if qi < wallQuads.count { n = wallQuads[qi] }
            else { n = SKShapeNode(); n.strokeColor = .clear; n.isAntialiased = false; addChild(n); wallQuads.append(n) }
            n.zPosition = CGFloat(qi) * 0.0002
            let p = CGMutablePath()
            p.move(to: q.p0); p.addLine(to: q.p1); p.addLine(to: q.p2); p.addLine(to: q.p3); p.closeSubpath()
            n.path = p; n.fillColor = q.color; n.isHidden = false
            qi += 1
        }
        for k in qi..<wallQuads.count { wallQuads[k].isHidden = true }
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
    }

    override func updateMap() {
        super.updateMap()
        if let tnode = travelerSpawner?.node, let info = travelerSpawner?.activeTraveler {
            if mapTravelerEmoji != info.emoji {
                mapTraveler?.removeFromParent()
                let n = emojiBillboard(info.emoji, mapCell) //* 1.2)
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
        // Pass 1: project, far-cull and wall-occlude every sprite; keep the survivors with their depth.
        var vis: [(node: SKNode, nativeH: CGFloat, worldH: CGFloat, maxH: CGFloat, name: String?, bottom: CGFloat, tX: Double, tY: Double)] = []
        for item in all {
            let node = item.node
            item.name.map { bossNameplate(for: node, text: $0) }?.isHidden = true
            let relX = item.x - camX, relY = item.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)   // depth
            guard tY > 0.15 else { node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            // Occlude against the NEAREST wall across the sprite's whole screen footprint, so a dot whose
            // body overlaps a wall a few columns from its centre is still hidden behind it. Clamp the column
            // so a sprite whose centre sits just past the screen edge still occludes against the edge wall —
            // skipping it leaked dots/pickups onto the left/right borders.
            let colC = max(0, min(columns - 1, col))
            let footHalf = max(1, min(5, Int((viewH / CGFloat(tY) * item.worldH) / (size.width / CGFloat(columns)) * 0.5)))
            var wallZ = zbuf[colC]
            for c in max(0, colC - footHalf)...min(columns - 1, colC + footHalf) { wallZ = min(wallZ, zbuf[c]) }
            if tY > wallZ + 0.3 { node.isHidden = true; continue }
            if tY > 18 { node.isHidden = true; continue }       // far cull
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { node.isHidden = true; continue }
            vis.append((node, item.nativeH, item.worldH, item.maxH, item.name, item.bottom, tX, tY))
        }
        // Pass 2: draw strictly far -> near (assign rising zPositions) so a nearer sprite always paints
        // over a farther one — a dot and a machine at similar depth no longer tie and flip.
        vis.sort { $0.tY > $1.tY }
        let zStep = vis.count > 1 ? 80.0 / Double(vis.count - 1) : 0
        for (i, v) in vis.enumerated() {
            let node = v.node, tY = v.tY
            // TRUE 1-point perspective, identical to the dots: size = viewH/depth, feet planted on the
            // floor row at THIS depth. maxH only clamps the size at point-blank range; it never moves the floor.
            let targetH = min(viewH / CGFloat(tY) * v.worldH, v.maxH)
            var s = targetH / v.nativeH
            if v.name != nil, let boss = node as? PixelPerson, bossController.isImmobilized(boss: boss) {
                s *= 1 + 0.18 * abs(sin(throbClock * .pi * 3))   // post-spawn throb, feet planted (position uses s)
            }
            node.isHidden = false
            node.setScale(s)
            let screenX = (size.width / 2) * CGFloat(1 + v.tX / tY)
            let floorY = viewMidY - (viewH / CGFloat(tY)) * eyeHeight
            node.position = CGPoint(x: screenX, y: floorY - v.bottom * s)
            node.zPosition = 2 + CGFloat(Double(i) * zStep)     // 2..82, far->near; always below Pete (90)
            if let name = v.name {
                let label = bossNameplate(for: node, text: name)
                label.isHidden = false
                label.fontSize = max(13, min(24, targetH * 0.16))
                label.position = CGPoint(x: screenX, y: floorY + targetH + label.fontSize * 0.7)
            }
        }
    }

    override func restartDoom() {
        gameOverScreen?.removeFromParent(); gameOverScreen = nil
        let bonus = VoxelScene(size: size)
        bonus.scaleMode = scaleMode
        bonus.practiceMode = practiceMode
        bonus.startingLevel = startingLevel
        view?.presentScene(bonus, transition: .fade(withDuration: 0.5))
    }
}
