import KitABI

// SKWarpGeometry / SKWarpGeometryGrid — mesh-warp deformation backed by
// the runtime's WebGL2 gfx_warp_draw. A grid records:
//   numberOfColumns, numberOfRows                    (cell count)
//   sourcePositions  (col+1)*(row+1) normalized UVs  (0..1 in texture space)
//   destPositions    (col+1)*(row+1) normalized      (0..1 in dest rect)
//
// When attached to an SKSpriteNode via the warpGeometry property, the sprite
// renders its texture as a mesh of triangles, each cell remapped from src→dst.
// SKAction.warp(to:duration:) interpolates a sprite from its current geometry
// to a target by lerping all destPositions.

public class SKWarpGeometry {
    public internal(set) var numberOfColumns: Int = 0
    public internal(set) var numberOfRows: Int = 0
    public internal(set) var sourcePositions: [CGPoint] = []
    public internal(set) var destPositions: [CGPoint] = []

    public init() {}

    public func sourcePosition(at index: Int) -> CGPoint {
        guard index >= 0 && index < sourcePositions.count else { return .zero }
        return sourcePositions[index]
    }
    public func destPosition(at index: Int) -> CGPoint {
        guard index >= 0 && index < destPositions.count else { return .zero }
        return destPositions[index]
    }
    public func gridByReplacingSourcePositions(_ pos: [CGPoint]) -> SKWarpGeometryGrid {
        let g = SKWarpGeometryGrid(columns: numberOfColumns, rows: numberOfRows,
                                   sourcePositions: pos, destPositions: destPositions)
        return g
    }
    public func gridByReplacingDestPositions(_ pos: [CGPoint]) -> SKWarpGeometryGrid {
        let g = SKWarpGeometryGrid(columns: numberOfColumns, rows: numberOfRows,
                                   sourcePositions: sourcePositions, destPositions: pos)
        return g
    }
}

public final class SKWarpGeometryGrid: SKWarpGeometry {
    public init(columns: Int, rows: Int) {
        super.init()
        self.numberOfColumns = columns
        self.numberOfRows = rows
        // Identity grid: src + dst evenly spaced [0..1] across both axes.
        let cw = columns + 1, rh = rows + 1
        var src: [CGPoint] = []
        src.reserveCapacity(cw * rh)
        var dst: [CGPoint] = []
        dst.reserveCapacity(cw * rh)
        for r in 0..<rh {
            for c in 0..<cw {
                let u = CGFloat(c) / CGFloat(columns)
                let v = CGFloat(r) / CGFloat(rows)
                src.append(CGPoint(x: u, y: v))
                dst.append(CGPoint(x: u, y: v))
            }
        }
        self.sourcePositions = src
        self.destPositions = dst
    }
    public init(columns: Int, rows: Int, sourcePositions src: [CGPoint], destPositions dst: [CGPoint]) {
        super.init()
        self.numberOfColumns = columns
        self.numberOfRows = rows
        self.sourcePositions = src
        self.destPositions = dst
    }

    // SKWarpGeometryGrid render hook used by SKSpriteNode.draw when a sprite's
    // warpGeometry is non-nil. dstX/Y are in the sprite's local space (origin
    // at the sprite's center; +Y down because we're inside the SKSpriteNode
    // y-flipped block).
    func render(srcImg: Int32, dstX: Float, dstY: Float, dstW: Float, dstH: Float, color: UInt32) {
        if sourcePositions.isEmpty || destPositions.isEmpty { return }
        // Flatten both arrays into [Float] (xy pairs).
        var srcXY: [Float] = []
        srcXY.reserveCapacity(sourcePositions.count * 2)
        for p in sourcePositions {
            srcXY.append(Float(p.x))
            srcXY.append(Float(p.y))
        }
        var dstXY: [Float] = []
        dstXY.reserveCapacity(destPositions.count * 2)
        for p in destPositions {
            dstXY.append(Float(p.x))
            dstXY.append(Float(p.y))
        }
        srcXY.withUnsafeBufferPointer { srcPtr in
            dstXY.withUnsafeBufferPointer { dstPtr in
                gfx_warp_draw(srcImg, Int32(numberOfColumns), Int32(numberOfRows),
                              srcPtr.baseAddress, dstPtr.baseAddress,
                              dstX, dstY, dstW, dstH, color)
            }
        }
    }
}


