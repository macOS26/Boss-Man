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
    // SKWarpGeometry hook. When set, draw routes the texture through the
    // mesh warp instead of the plain quad / 9-slice. Apple's SKAction.warp
    // animates this field by lerping a target geometry into the current one.
    public var warpGeometry: SKWarpGeometry?
    public var subdivisionLevels: Int = 0

    public init(color: SKColor, size: CGSize) { self.color = color
    self.size = size
    super.init() }
    public init(texture: SKTexture?, size: CGSize) { self.texture = texture
    self.size = size
    super.init() }
    public init(texture: SKTexture?, color: SKColor, size: CGSize) {
        self.texture = texture
        self.color = color
        self.size = size
        super.init()
    }
    public init(texture: SKTexture?) {
        self.texture = texture
        self.size = texture?.size ?? CGSize(width: 32, height: 32)
        super.init()
    }
    public init(texture: SKTexture?, normalMap nt: SKTexture?) {
        self.texture = texture
        self.normalTexture = nt
        self.size = texture?.size ?? CGSize(width: 32, height: 32)
        super.init()
    }
    public init(imageNamed name: String) {
        let t = SKTexture(imageNamed: name)
        self.texture = t
        self.size = CGSize(width: 32, height: 32)
        super.init()
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
        // Re-resolve a deferred-name texture each frame until the runtime
        // registers it. This handles the boot()-before-preload-finishes race:
        // SKSpriteNodes built during the first frame may hold a handle of 0
        // that becomes valid once the manifest preloader catches up.
        texture?.resolvePending()
        guard let t = texture, t.handle != 0 else {
            gfx_fill_rect(-w * ax, -h * ay, w, h, color.rgba)
            return
        }
        // re-flip locally so the bitmap isn't drawn upside down
        gfx_save()
        gfx_scale(1, -1)

        // Shader path: when a SKShader is bound, route the texture through
        // gfx_shader_draw (WebGL2 pass) instead of a plain image blit. The
        // shader's u_texture is the sprite's main texture; u_color_mix is the
        // sprite's tint, u_time is wall-clock seconds since the kit started.
        if let sh = shader, sh.ensureCompiled() > 0 {
            sh.bindUniforms()
            let t0 = SKSpriteNode.kitClock()
            gfx_shader_draw(sh.handle, t.handle,
                            -w * ax, -h * (1 - ay), w, h, t0, color.rgba)
            gfx_restore()
            return
        }

        // Lighting path: when lightingBitMask matches an active SKLightNode,
        // run the built-in lighting fragment so normal-mapped sprites shade.
        if lightingBitMask != 0, let scene = self.scene,
           let lightsBuf = SKSpriteNode.collectActiveLights(scene: scene,
                                                            mask: lightingBitMask) {
            lightsBuf.withUnsafeBufferPointer { ptr in
                gfx_lighting_draw(t.handle,
                                  normalTexture?.handle ?? 0,
                                  ptr.baseAddress, Int32(ptr.count / 8),
                                  -w * ax, -h * (1 - ay), w, h, color.rgba)
            }
            gfx_restore()
            return
        }

        // Warp path: mesh-warp the sprite's texture through the SKWarpGeometry.
        if let warp = warpGeometry as? SKWarpGeometryGrid {
            warp.render(srcImg: t.handle,
                        dstX: -w * ax, dstY: -h * (1 - ay), dstW: w, dstH: h,
                        color: color.rgba)
            gfx_restore()
            return
        }

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

    // Time source passed to u_time. Apple's SKShader sees seconds since the
    // shader was attached; we use seconds since the first kit frame, which is
    // close enough for the typical "ripple by time" patterns. KitClock is
    // refreshed by SKView each frame.
    nonisolated(unsafe) static var _kitTime: Float = 0
    public static func kitClock() -> Float { _kitTime }
    public static func _setKitClock(_ t: Float) { _kitTime = t }

    // Collect up to 8 lights matching `mask` and flatten them into a buffer of
    // 8 floats per light (posX, posY, intensity, _, r, g, b, falloff) for
    // gfx_lighting_draw. Returns nil when no light matches.
    static func collectActiveLights(scene: SKScene, mask: UInt32) -> [Float]? {
        var buf: [Float] = []
        var count = 0
        func walk(_ n: SKNode) {
            guard count < 8 else { return }
            if let l = n as? SKLightNode, l.isEnabled,
               (l.categoryBitMask & mask) != 0 {
                let p = l.absolutePosition()
                buf.append(Float(p.x))
                buf.append(Float(p.y))
                buf.append(1.0)                                  // intensity
                buf.append(0)                                    // padding
                buf.append(Float(l.lightColor.r))
                buf.append(Float(l.lightColor.g))
                buf.append(Float(l.lightColor.b))
                buf.append(Float(l.falloff))
                count += 1
            }
            for c in n.children { walk(c) }
        }
        walk(scene)
        return buf.isEmpty ? nil : buf
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
        _ = sLeft
        _ = sRight  // silence unused warnings on this path
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


