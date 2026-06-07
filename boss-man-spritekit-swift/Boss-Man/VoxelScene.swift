import SpriteKit
import AppKit

final class VoxelScene: Scene3D {

    override var eyeHeight: CGFloat { 0.7 }
    override var wallHeightScale: CGFloat { 0.5 }
    override var pelletWorldH: CGFloat { 0.15 }

    override func buildSky() {
        super.buildSky()
        let tree = SKNode()
        let glowH: CGFloat = 60
        let glowBottom = viewMidY
        let n = max(1, Int(glowH))
        for i in 0..<n {
            let t = 1.0 - CGFloat(i) / CGFloat(max(1, n - 1))
            let alpha = t * t * 0.55
            let band = SKShapeNode(rect: CGRect(x: 0, y: glowBottom + CGFloat(i), width: size.width, height: 1))
            band.fillColor = SKColor(red: 1.0, green: 0.82, blue: 0.35, alpha: alpha)
            band.strokeColor = .clear
            tree.addChild(band)
        }
        let shaftCount = 5
        for s in 0..<shaftCount {
            let fx = CGFloat(s) / CGFloat(shaftCount - 1)
            let cx = fx * size.width * 0.8 + size.width * 0.1
            let shaftW: CGFloat = size.width * 0.045
            let shaftH: CGFloat = glowH * 0.85
            let shaft = SKShapeNode(rect: CGRect(x: cx - shaftW / 2, y: glowBottom + 4, width: shaftW, height: shaftH))
            shaft.fillColor = SKColor(red: 1.0, green: 0.92, blue: 0.6, alpha: 0.18)
            shaft.strokeColor = .clear
            tree.addChild(shaft)
        }
        addBaked(tree, to: self, z: -2)
    }

    override func render() {
        throbClock += 1.0 / 60.0
        let dirX = cos(angle), dirY = sin(angle)
        let planeX = -dirY * planeScale, planeY = dirX * planeScale
        var back = camBack
        while back > 0.05 && isWall(px - dirX * back, py - dirY * back) { back -= 0.1 }
        camX = px - dirX * back; camY = py - dirY * back
        castFloor()

        let cube = SpriteFactory.cubicleColors[(state.level - 1) % SpriteFactory.cubicleColors.count]
        let tops = buildWallCells(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        let invDet = 1.0 / (planeX * dirY - dirX * planeY)
        let wallH = Double(wallHeightScale)
        var quads = buildFaceQuads(tops: tops, cube: cube, invDet: invDet, wallH: wallH,
                                   dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)

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
        paintQuads(quads)
        projectSprites(dirX: dirX, dirY: dirY, planeX: planeX, planeY: planeY)
        updateMap()
        updateMapTravelerMirror()
    }

    override func makeNextLevelScene() -> Scene3D { VoxelScene(size: size) }
    override func makeRestartScene()   -> Scene3D { VoxelScene(size: size) }
}
