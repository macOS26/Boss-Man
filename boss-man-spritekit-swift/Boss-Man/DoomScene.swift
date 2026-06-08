import SpriteKit
import AppKit

final class DoomScene: Scene3D {

    override var eyeHeight: CGFloat { 0.333 }
    override var wallHeightScale: CGFloat { 1.0 }

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

