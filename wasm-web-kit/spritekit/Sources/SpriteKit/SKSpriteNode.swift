import KitABI

public final class SKSpriteNode: SKNode {
    public var texture: SKTexture? { didSet { if size == .zero, let t = texture { size = t.size } } }
    public var normalTexture: SKTexture?
    public var color: SKColor = .white
    public var colorBlendFactor: CGFloat = 0
    public var size: CGSize
    public var anchorPoint = CGPoint(x: 0.5, y: 0.5)
    public var blendMode: SKBlendMode = .alpha
    // Stretchable 9-slice. Normalized rect inside the texture (0..1) that
    // stretches; the four corners + four edges stay at their natural size.
    // Defaults to .zero (full stretch == legacy behavior).
    public var centerRect: CGRect = .zero
    public var lightingBitMask: UInt32 = 0
    public var shadowCastBitMask: UInt32 = 0
    public var shadowedBitMask: UInt32 = 0xFFFFFFFF
    public var shader: SKShader?

    public init(color: SKColor, size: CGSize) { self.color = color; self.size = size; super.init() }
    public init(texture: SKTexture?, size: CGSize) { self.texture = texture; self.size = size; super.init() }
    public init(texture: SKTexture?, color: SKColor, size: CGSize) {
        self.texture = texture; self.color = color; self.size = size; super.init()
    }
    public init(texture: SKTexture?) {
        self.texture = texture; self.size = texture?.size ?? CGSize(width: 32, height: 32); super.init()
    }
    public init(texture: SKTexture?, normalMap nt: SKTexture?) {
        self.texture = texture; self.normalTexture = nt
        self.size = texture?.size ?? CGSize(width: 32, height: 32); super.init()
    }
    public init(imageNamed name: String) {
        let t = SKTexture(imageNamed: name); self.texture = t; self.size = CGSize(width: 32, height: 32); super.init()
    }

    // Override SKNode.frame so calculateAccumulatedFrame / hit-testing reports
    // the sprite's actual extent (centered on anchorPoint).
    public override var frame: CGRect {
        CGRect(x: position.x - size.width  * anchorPoint.x,
               y: position.y - size.height * anchorPoint.y,
               width: size.width, height: size.height)
    }

    override func draw(alpha: CGFloat) {
        let w = Float(size.width), h = Float(size.height)
        let ax = Float(anchorPoint.x), ay = Float(anchorPoint.y)
        gfx_set_alpha(Float(alpha))
        guard let t = texture, t.handle != 0 else {
            gfx_fill_rect(-w * ax, -h * ay, w, h, color.rgba)
            return
        }
        // re-flip locally so the bitmap isn't drawn upside down
        gfx_save(); gfx_scale(1, -1)
        if centerRect == .zero {
            // Single-quad draw. Honor the texture's sub-region when set so
            // atlas slices (SKTexture(rect:in:)) render correctly.
            let sr = t.sourceRect
            if sr == .zero {
                gfx_draw_image(t.handle, 0, 0, -1, -1,
                               -w * ax, -h * (1 - ay), w, h, color.rgba)
            } else {
                gfx_draw_image(t.handle,
                               Float(sr.minX), Float(sr.minY), Float(sr.width), Float(sr.height),
                               -w * ax, -h * (1 - ay), w, h, color.rgba)
            }
        } else {
            draw9Slice(t, dx: -w * ax, dy: -h * (1 - ay), dw: w, dh: h)
        }
        gfx_restore()
    }

    // 9-slice: split the source texture into corners/edges/center using the
    // normalized centerRect, then draw each patch separately. Corners keep
    // their natural pixel size; edges stretch along one axis; center stretches
    // both. Apple's centerRect is in unit (0..1) coordinates.
    private func draw9Slice(_ t: SKTexture, dx: Float, dy: Float, dw: Float, dh: Float) {
        let tw = Float(t.size.width  > 0 ? t.size.width  : CGFloat(dw))
        let th = Float(t.size.height > 0 ? t.size.height : CGFloat(dh))
        let cr = centerRect
        // Source rect corners in source pixel coordinates.
        let sLeft   = Float(cr.minX) * tw
        let sRight  = tw - Float(cr.maxX) * tw + Float(cr.minX) * tw
        // Actually compute as widths/heights for source:
        let srcL = Float(cr.minX) * tw                              // left  edge width
        let srcR = (1 - Float(cr.maxX)) * tw                        // right edge width
        let srcT = Float(cr.minY) * th                              // top edge (in source pixels)
        let srcB = (1 - Float(cr.maxY)) * th                        // bottom edge
        let srcCenterW = Float(cr.width)  * tw
        let srcCenterH = Float(cr.height) * th
        // Destination edge widths/heights — corners keep natural size.
        let dstL = srcL, dstR = srcR, dstT = srcT, dstB = srcB
        let dstCenterW = max(0, dw - dstL - dstR)
        let dstCenterH = max(0, dh - dstT - dstB)
        _ = sLeft; _ = sRight   // silence unused warnings on this path
        let col = color.rgba

        // Helper to draw one source-rect → dest-rect slice.
        func slice(_ sx: Float, _ sy: Float, _ sw: Float, _ sh: Float,
                   _ ddx: Float, _ ddy: Float, _ ddw: Float, _ ddh: Float) {
            if ddw <= 0 || ddh <= 0 { return }
            gfx_draw_image(t.handle, sx, sy, sw, sh, ddx, ddy, ddw, ddh, col)
        }

        // Source slice anchor points.
        let sCX = srcL, sCY = srcT
        // Top-left
        slice(0,         0,         srcL,        srcT,        dx,                dy,                dstL,       dstT)
        // Top-edge
        slice(sCX,       0,         srcCenterW,  srcT,        dx + dstL,         dy,                dstCenterW, dstT)
        // Top-right
        slice(sCX + srcCenterW, 0,  srcR,        srcT,        dx + dstL + dstCenterW, dy,           dstR,       dstT)
        // Left-edge
        slice(0,         sCY,       srcL,        srcCenterH,  dx,                dy + dstT,         dstL,       dstCenterH)
        // Center
        slice(sCX,       sCY,       srcCenterW,  srcCenterH,  dx + dstL,         dy + dstT,         dstCenterW, dstCenterH)
        // Right-edge
        slice(sCX + srcCenterW, sCY, srcR,       srcCenterH,  dx + dstL + dstCenterW, dy + dstT,    dstR,       dstCenterH)
        // Bottom-left
        slice(0,         sCY + srcCenterH, srcL, srcB,        dx,                dy + dstT + dstCenterH, dstL,  dstB)
        // Bottom-edge
        slice(sCX,       sCY + srcCenterH, srcCenterW, srcB, dx + dstL,         dy + dstT + dstCenterH, dstCenterW, dstB)
        // Bottom-right
        slice(sCX + srcCenterW, sCY + srcCenterH, srcR, srcB,
              dx + dstL + dstCenterW, dy + dstT + dstCenterH, dstR, dstB)
    }
}
