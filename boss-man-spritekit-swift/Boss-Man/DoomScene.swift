import SpriteKit
import AppKit

final class DoomScene: Scene3D {

    override var eyeHeight: CGFloat { 0.333 }
    override var wallHeightScale: CGFloat { 1.0 }

    private class VisItem {
        var node: SKNode!
        var nativeH: CGFloat = 0
        var worldH: CGFloat = 0
        var maxH: CGFloat = 0
        var name: String?
        var bottom: CGFloat = 0
        var tX: Double = 0
        var tY: Double = 0
    }
    private var visPool: [VisItem] = []
    private var visPoolCount = 0

    private func getVisItem() -> VisItem {
        if visPoolCount >= visPool.count {
            visPool.append(VisItem())
        }
        visPoolCount += 1
        return visPool[visPoolCount - 1]
    }

    private func resetVisPool() {
        visPoolCount = 0
    }

    private func isMachineEmoji(_ ch: UInt8) -> Bool {
        ch == Strings.Tile.printerChar || ch == Strings.Tile.faxChar ||
        ch == Strings.Tile.coverSheetChar || ch == Strings.Tile.bookBinderChar
    }

    override func hidePickupInWorld(col: Int, row: Int) {
        let key = mapKey(col, row)
        guard row >= 0, row < rowsCount, col >= 0, col < map[row].count else { return }
        let ch = map[row][col]
        if isMachineEmoji(ch) {
            for i in billboards.indices where billboards[i].alive && Int(billboards[i].x) == col && Int(billboards[i].y) == row {
                billboards[i].alive = false
                billboards[i].node.run(.fadeOut(withDuration: 0.3))
            }
            mapPickups[key]?.run(.fadeOut(withDuration: 0.3))
        } else {
            super.hidePickupInWorld(col: col, row: row)
        }
    }

    override func projectSprites(dirX: Double, dirY: Double, planeX: Double, planeY: Double) {
        resetVisPool()
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        var billboardCount = 0, bossCount = 0, shotCount = 0, travelerCount = 0
        for b in billboards where b.alive { billboardCount += 1 }
        for _ in bossController.entities { bossCount += 1 }
        for s in shots where s.alive { shotCount += 1 }
        if let _ = travelerSpawner?.activeTraveler { travelerCount = 1 }

        for b in billboards where b.alive {
            let relX = b.x - camX, relY = b.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)
            guard tY > 0.15 else { b.node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            let colC = max(0, min(columns - 1, col))
            let footHalf = max(1, min(5, Int((viewH / CGFloat(tY) * b.worldH) / (size.width / CGFloat(columns)) * 0.5)))
            var wallZ = zbuf[colC]
            for c in max(0, colC - footHalf)...min(columns - 1, colC + footHalf) { wallZ = min(wallZ, zbuf[c]) }
            if tY > wallZ + 0.3 { b.node.isHidden = true; continue }
            if tY > 18 { b.node.isHidden = true; continue }
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { b.node.isHidden = true; continue }
            let v = getVisItem()
            v.node = b.node
            v.nativeH = b.nativeH
            v.worldH = b.worldH
            v.maxH = .greatestFiniteMagnitude
            v.name = nil
            v.bottom = b.bottom
            v.tX = tX
            v.tY = tY
        }
        for e in bossController.entities {
            guard let g = bossGrid[ObjectIdentifier(e.node)] else { continue }
            let relX = g.0 + 0.5 - camX, relY = Double(rowsCount) - 0.5 - g.1 - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)
            guard tY > 0.15 else { e.node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            let colC = max(0, min(columns - 1, col))
            let footHalf = max(1, min(5, Int((viewH / CGFloat(tY) * 0.42) / (size.width / CGFloat(columns)) * 0.5)))
            var wallZ = zbuf[colC]
            for c in max(0, colC - footHalf)...min(columns - 1, colC + footHalf) { wallZ = min(wallZ, zbuf[c]) }
            if tY > wallZ + 0.3 { e.node.isHidden = true; continue }
            if tY > 18 { e.node.isHidden = true; continue }
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { e.node.isHidden = true; continue }
            let v = getVisItem()
            v.node = e.node
            v.nativeH = bossNativeH[ObjectIdentifier(e.node)] ?? 36
            v.worldH = 0.42
            v.maxH = .greatestFiniteMagnitude
            v.name = e.name
            v.bottom = bossFeet[ObjectIdentifier(e.node)] ?? -v.nativeH / 2
            v.tX = tX
            v.tY = tY
        }
        for s in shots where s.alive {
            let relX = s.x - camX, relY = s.y - camY
            let tX = invDet * (dirY * relX - dirX * relY)
            let tY = invDet * (-planeY * relX + planeX * relY)
            guard tY > 0.15 else { s.node.isHidden = true; continue }
            let col = Int((size.width / 2) * CGFloat(1 + tX / tY) / (size.width / CGFloat(columns)))
            let colC = max(0, min(columns - 1, col))
            let footHalf = max(1, min(5, Int((viewH / CGFloat(tY) * 0.32) / (size.width / CGFloat(columns)) * 0.5)))
            var wallZ = zbuf[colC]
            for c in max(0, colC - footHalf)...min(columns - 1, colC + footHalf) { wallZ = min(wallZ, zbuf[c]) }
            if tY > wallZ + 0.3 { s.node.isHidden = true; continue }
            if tY > 18 { s.node.isHidden = true; continue }
            let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
            guard screenX > -60, screenX < size.width + 60 else { s.node.isHidden = true; continue }
            let v = getVisItem()
            v.node = s.node
            v.nativeH = s.nativeH
            v.worldH = 0.32
            v.maxH = .greatestFiniteMagnitude
            v.name = nil
            v.bottom = -s.nativeH / 2
            v.tX = tX
            v.tY = tY
        }
        if let tnode = travelerSpawner?.node, let info = travelerSpawner?.activeTraveler {
            tnode.isHidden = true
            let nc = Double(tnode.position.x) / 32.0
            let dCol = nc - travPrevCol
            if abs(dCol) > 0.001, abs(dCol) < 2 { travFlip = info.facesRight ? (dCol < 0 ? -1 : 1) : (dCol < 0 ? 1 : -1) }
            travPrevCol = nc
            if travelerMirror == nil || travelerMirrorEmoji != info.emoji {
                travelerMirror?.removeFromParent()
                let wrap = SKNode()
                let e = emojiBillboard(info.emoji, 40)
                e.name = Strings.NodeName.travelerEmoji
                wrap.addChild(e)
                spriteLayer.addChild(wrap)
                travelerMirror = wrap
                travelerMirrorEmoji = info.emoji
                travelerNativeH = 40
            }
            if let m = travelerMirror {
                if let mE = m.childNode(withName: Strings.NodeName.travelerEmoji) {
                    mE.xScale = abs(mE.xScale) * travFlip
                }
                let relX = Double(tnode.position.x) / 32.0 - camX, relY = Double(rowsCount) - Double(tnode.position.y) / 32.0 - camY
                let tX = invDet * (dirY * relX - dirX * relY)
                let tY = invDet * (-planeY * relX + planeX * relY)
                guard tY > 0.15 else { m.isHidden = true; }
                guard tY <= 18 else { m.isHidden = true; }
                let screenX = (size.width / 2) * CGFloat(1 + tX / tY)
                guard screenX > -60, screenX < size.width + 60 else { m.isHidden = true; }
                let v = getVisItem()
                v.node = m
                v.nativeH = travelerNativeH
                v.worldH = 0.42
                v.maxH = .greatestFiniteMagnitude
                v.name = nil
                v.bottom = -travelerNativeH / 2
                v.tX = tX
                v.tY = tY
            }
        } else {
            travelerMirror?.isHidden = true
        }

        var indices = Array(0..<visPoolCount)
        indices.sort { visPool[$0].tY > visPool[$1].tY }

        let zStep = visPoolCount > 1 ? 80.0 / Double(visPoolCount - 1) : 0
        for (order, idx) in indices.enumerated() {
            let v = visPool[idx]
            let targetH = min(viewH / CGFloat(v.tY) * v.worldH, v.maxH)
            var s = targetH / v.nativeH
            if let name = v.name, let boss = v.node as? PixelPerson, bossController.isImmobilized(boss: boss) {
                s *= 1 + 0.18 * abs(sin(throbClock * .pi * 3))
            }
            v.node.isHidden = false
            v.node.setScale(s)
            let screenX = (size.width / 2) * CGFloat(1 + v.tX / v.tY)
            let floorY = viewMidY - (viewH / CGFloat(v.tY)) * eyeHeight
            v.node.position = CGPoint(x: screenX, y: floorY - v.bottom * s)
            v.node.zPosition = 2 + CGFloat(Double(order) * zStep)
            if let name = v.name, let boss = v.node as? PixelPerson {
                let flee = goldDisc.isActive && bossController.isInFleeMode(boss: boss)
                let label = bossNameplate(for: v.node, text: flee ? "\(bossController.nextCapturePoints)" : name)
                label.fontColor = flee ? .systemYellow : .white
                label.isHidden = false
                label.fontSize = max(13, min(24, targetH * 0.16))
                label.position = CGPoint(x: screenX, y: floorY + targetH + label.fontSize * 0.7)
            }
        }
    }

    override func render(dt: Double) {
        throbClock += dt
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back
        camY = py - dirY * back
        castFloor()
        castCeiling()

        let cube = SpriteFactory.cubicleColor(forLevel: state.level)
        let tops = buildWallCells(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        let wallH = Double(wallHeightScale)
        var quads = buildFaceQuads(tops: tops, cube: cube, invDet: invDet, wallH: wallH,
                                   dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY,
                                   faceGrayRects: true)
        quads.sort { $0.depth > $1.depth }
        paintQuads(quads)
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
        updateMapTravelerMirror()
    }

    override func makeRestartScene() -> Scene3D { VoxelScene(size: size) }
}

