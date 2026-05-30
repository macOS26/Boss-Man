import KitABI

// =============================================================================
// SKShader / SKUniform — compile-only stubs.
//
// Canvas2D has no GLSL pipeline, so any shader attached to a node is recorded
// but ignored at draw time. Games that bind shaders for visual effects degrade
// gracefully to their un-shaded sprites.
// =============================================================================
// SKShader: GLSL fragment compiled lazily on first use. The runtime injects a
// SpriteKit-style preamble (u_time, v_tex_coord, v_color_mix, SKDefaultShading,
// #define texture2D=texture) before the user source.
public final class SKShader {
    public var source: String?
    public var uniforms: [SKUniform] = [] {
        didSet { uniformsDirty = true }
    }
    public var attributes: [SKAttribute] = []
    // Compiled program handle in the WebGL2 runtime. Lazily filled on first
    // apply() call when source is available.
    var handle: Int32 = 0
    var uniformsDirty: Bool = true

    public init() {}
    public init(source: String) { self.source = source }
    public init(source: String, uniforms: [SKUniform]) { self.source = source; self.uniforms = uniforms }
    public init(fileNamed name: String) {
        if let asset = SKSceneLoader.loadAssetText("\(name).fsh") ?? SKSceneLoader.loadAssetText(name) {
            self.source = asset
        }
    }
    public static func shader(withSource s: String) -> SKShader { SKShader(source: s) }

    public func addUniform(_ u: SKUniform) { uniforms.append(u) }
    public func removeUniformNamed(_ name: String) { uniforms.removeAll { $0.name == name } }
    public func uniformNamed(_ name: String) -> SKUniform? { uniforms.first { $0.name == name } }

    // Compile + cache the WebGL2 program. Returns the program handle, or 0
    // if WebGL2 is unavailable / the source failed to compile.
    func ensureCompiled() -> Int32 {
        if handle > 0 { return handle }
        guard let src = source, !src.isEmpty else { return 0 }
        handle = withUTF8Ptr(src) { gfx_shader_compile($0, $1) }
        return handle
    }

    // Push every uniform value to the runtime. Called before every draw when
    // uniformsDirty (which flips on every value change).
    func bindUniforms() {
        guard handle > 0 else { return }
        for u in uniforms { u.push(to: handle) }
        uniformsDirty = false
    }
}

// SKUniform stores a single GLSL uniform value. Type is implied by which
// initializer / property is set. On push the runtime selects the appropriate
// gfx_shader_set_uniform_* call. Reading existing Apple call sites:
// SKUniform(name: "u_time", float: 0) → push as float; SKUniform(name:,
// vectorFloat2:) → push as vec2; SKUniform(name:, texture:) → push as sampler.
public final class SKUniform {
    public enum Kind { case float, v2, v3, v4, texture }
    public let name: String
    public var kind: Kind
    public var floatValue: Float = 0
    public var vectorFloat2: (Float, Float) = (0, 0)
    public var vectorFloat3: (Float, Float, Float) = (0, 0, 0)
    public var vectorFloat4: (Float, Float, Float, Float) = (0, 0, 0, 0)
    public var textureValue: SKTexture?

    public init(name: String) { self.name = name; self.kind = .float }
    public init(name: String, float value: Float) { self.name = name; self.kind = .float; self.floatValue = value }
    public init(name: String, vectorFloat2 v: (Float, Float)) {
        self.name = name; self.kind = .v2; self.vectorFloat2 = v
    }
    public init(name: String, vectorFloat3 v: (Float, Float, Float)) {
        self.name = name; self.kind = .v3; self.vectorFloat3 = v
    }
    public init(name: String, vectorFloat4 v: (Float, Float, Float, Float)) {
        self.name = name; self.kind = .v4; self.vectorFloat4 = v
    }
    public init(name: String, texture: SKTexture?) {
        self.name = name; self.kind = .texture; self.textureValue = texture
    }

    func push(to shader: Int32) {
        withUTF8Ptr(name) { ptr, len in
            switch kind {
            case .float:   gfx_shader_set_uniform_f (shader, ptr, len, floatValue)
            case .v2:      gfx_shader_set_uniform_v2(shader, ptr, len, vectorFloat2.0, vectorFloat2.1)
            case .v3:      gfx_shader_set_uniform_v3(shader, ptr, len, vectorFloat3.0, vectorFloat3.1, vectorFloat3.2)
            case .v4:      gfx_shader_set_uniform_v4(shader, ptr, len, vectorFloat4.0, vectorFloat4.1, vectorFloat4.2, vectorFloat4.3)
            case .texture:
                if let t = textureValue { gfx_shader_set_uniform_t(shader, ptr, len, t.handle) }
            }
        }
    }
}

public final class SKAttribute {
    public let name: String
    public let type: Int
    public init(name: String, type: Int) { self.name = name; self.type = type }
}

public final class SKAttributeValue {
    public var floatValue: Float = 0
    public init() {}
    public init(float v: Float) { self.floatValue = v }
}

// =============================================================================
// SKConstraint / SKRange — per-frame apply hook on SKNode.
//
// positionX/Y/XY clamp axes through SKRange; distance constrains the radius
// to a reference point or node within a SKRange; orient(to:offset:) computes
// atan2 from the node to the target and clamps the resulting bearing through
// the offset SKRange. Node-targeted forms re-evaluate the target's absolute
// position each frame so moving targets work.
// =============================================================================
public final class SKRange {
    public var lowerLimit: CGFloat = -.infinity
    public var upperLimit: CGFloat =  .infinity
    public init(lowerLimit l: CGFloat = -.infinity, upperLimit u: CGFloat = .infinity) {
        self.lowerLimit = l; self.upperLimit = u
    }
    public static func constant(_ v: CGFloat) -> SKRange { SKRange(lowerLimit: v, upperLimit: v) }
    public static func lowerLimit(_ v: CGFloat) -> SKRange { SKRange(lowerLimit: v) }
    public static func upperLimit(_ v: CGFloat) -> SKRange { SKRange(upperLimit: v) }
    public static func with(value v: CGFloat, variance var_: CGFloat) -> SKRange {
        SKRange(lowerLimit: v - var_, upperLimit: v + var_)
    }
    func clamp(_ x: CGFloat) -> CGFloat { min(max(x, lowerLimit), upperLimit) }
}

public final class SKConstraint {
    enum Kind {
        case positionX(SKRange), positionY(SKRange), positionXY(SKRange, SKRange)
        case distance(SKRange, CGPoint), orientToPoint(CGPoint, SKRange)
        case orientToNode(SKRange)            // target captured in referenceNode
        case zRotation(SKRange)
    }
    let kind: Kind
    public var enabled: Bool = true
    public var referenceNode: SKNode?

    init(_ k: Kind) { kind = k }

    public static func positionX(_ r: SKRange) -> SKConstraint { SKConstraint(.positionX(r)) }
    public static func positionY(_ r: SKRange) -> SKConstraint { SKConstraint(.positionY(r)) }
    public static func positionX(_ rx: SKRange, y ry: SKRange) -> SKConstraint { SKConstraint(.positionXY(rx, ry)) }
    public static func distance(_ r: SKRange, to point: CGPoint) -> SKConstraint { SKConstraint(.distance(r, point)) }
    public static func distance(_ r: SKRange, to node: SKNode) -> SKConstraint {
        let c = SKConstraint(.distance(r, node.absolutePosition())); c.referenceNode = node; return c
    }
    public static func orient(to point: CGPoint, offset r: SKRange) -> SKConstraint { SKConstraint(.orientToPoint(point, r)) }
    public static func orient(to node: SKNode, offset r: SKRange) -> SKConstraint {
        let c = SKConstraint(.orientToNode(r)); c.referenceNode = node; return c
    }
    public static func zRotation(_ r: SKRange) -> SKConstraint { SKConstraint(.zRotation(r)) }

    func apply(to node: SKNode) {
        guard enabled else { return }
        switch kind {
        case let .positionX(r):  node.position.x = r.clamp(node.position.x)
        case let .positionY(r):  node.position.y = r.clamp(node.position.y)
        case let .positionXY(rx, ry):
            node.position.x = rx.clamp(node.position.x)
            node.position.y = ry.clamp(node.position.y)
        case let .zRotation(r):  node.zRotation = r.clamp(node.zRotation)
        case let .distance(r, p):
            let dx = node.position.x - p.x, dy = node.position.y - p.y
            let d = (Double(dx*dx + dy*dy)).squareRoot()
            if d == 0 { return }
            let clamped = r.clamp(CGFloat(d))
            let s = clamped / CGFloat(d)
            node.position = CGPoint(x: p.x + dx * s, y: p.y + dy * s)
        case let .orientToPoint(p, r):
            let dx = p.x - node.position.x, dy = p.y - node.position.y
            if dx == 0 && dy == 0 { return }
            node.zRotation = r.clamp(atan2c(dy, dx))
        case let .orientToNode(r):
            guard let target = referenceNode else { return }
            let tp = target.absolutePosition()
            let np = node.absolutePosition()
            let dx = tp.x - np.x, dy = tp.y - np.y
            if dx == 0 && dy == 0 { return }
            node.zRotation = r.clamp(atan2c(dy, dx))
        }
    }
}

// =============================================================================
// SKReferenceNode — .sks scene-file references.
//
// Without an .sks parser we can't reconstruct the referenced node tree, so this
// is a compile-only stub that returns an empty SKNode. Games like Space-Bar
// that lean on it for level loading will need a parallel level-loader bridge.
// =============================================================================
public final class SKReferenceNode: SKNode {
    public let fileName: String?
    public let url: SKAudioURL?
    public override init() { fileName = nil; url = nil; super.init() }
    public init(fileNamed name: String) { fileName = name; url = nil; super.init() }
    public init(url: SKAudioURL) { fileName = nil; self.url = url; super.init() }
    public func didLoad() {}
    public func resolve() {}
}

// =============================================================================
// SKTextureAtlas — name-based atlas lookup.
//
// On wasm, each atlas/texture pair resolves to an image asset named
// "atlas/texture" in the runtime's image table. Games that loaded
// .atlas folders in their Xcode bundle can mirror that naming on the web
// asset manifest.
// =============================================================================
public final class SKTextureAtlas {
    public let name: String
    public init(named: String) { self.name = named }
    public static func preloadTextureAtlases(_ atlases: [SKTextureAtlas],
                                             withCompletionHandler handler: @escaping () -> Void) { handler() }
    public func textureNamed(_ tname: String) -> SKTexture { SKTexture(imageNamed: "\(name)/\(tname)") }
    public var textureNames: [String] { [] }
    public func preload(completionHandler handler: @escaping () -> Void) { handler() }
}

// =============================================================================
// SKEffectNode / SKCropNode — transparent containers.
//
// SKEffectNode usually drives a Core Image filter pipeline through an
// offscreen render target; on Canvas2D we just render children straight
// through. SKCropNode optionally honors a rectangular maskNode via a gfx
// clip rect; non-rect masks degrade to "no clip".
// =============================================================================
// SKEffectNode applies a Canvas2D ctx.filter string (read from `filterString`
// if set, else from the legacy `filter: SKFilter` shim) around its children's
// render call. Apple's CIFilter is non-portable; games passing CIFilter
// instances see no effect, but games that adopt our SKFilter helper or set
// `filterString` directly get real ctx.filter rendering.
// Minimal CIFilter shim. SKEffectNode.filter is a CIFilter on Apple; we
// recognize CIGaussianBlur + its inputRadius and render it as a soft Canvas2D
// drop shadow (ctx.shadowBlur), so Apple's SKEffectNode + CIFilter shadow idiom
// is common code and looks good on web.
public final class CIFilter {
    public let name: String
    public var inputRadius: CGFloat = 0
    public init?(name: String, parameters: [String: Any]? = nil) {
        self.name = name
        if let v = parameters?["inputRadius"] {
            if let r = v as? CGFloat     { inputRadius = r }
            else if let r = v as? Double { inputRadius = CGFloat(r) }
            else if let r = v as? Int    { inputRadius = CGFloat(r) }
        }
    }
}

public class SKEffectNode: SKNode {
    public var shouldEnableEffects: Bool = false
    public var shouldRasterize: Bool = false
    public var shouldCenterFilter: Bool = false
    public var blendMode: SKBlendMode = .alpha
    public var filter: AnyObject?              // CIFilter stand-in
    public var shader: SKShader?
    // Convenience: a portable CSS-filter string honored by Canvas2D's
    // ctx.filter — e.g. "blur(8px) saturate(150%)". Games can set this
    // directly to get a real visual effect on web.
    public var filterString: String?
    public override init() { super.init() }

    override func draw(alpha: CGFloat) {
        // Children are drawn by renderTree via the SKNode base path; this hook
        // exists so the effect node can wrap that draw with a filter set/clear.
        // We can't intercept renderTree directly, so apply the filter at the
        // gfx layer for the duration of this subtree by toggling it in
        // renderTree (see SKEffectNode-specific override below).
    }

    override func renderTree(parentAlpha: CGFloat) {
        if isHidden || alpha <= 0 { return }
        let eff = parentAlpha * alpha
        gfx_save()
        gfx_translate(Float(position.x), Float(position.y))
        if zRotation != 0 { gfx_rotate(Float(zRotation * 180.0 / Double.pi)) }
        if xScale != 1 || yScale != 1 { gfx_scale(Float(xScale), Float(yScale)) }

        // CIGaussianBlur drop-shadow path: render children sharp into a tight
        // offscreen, then blit it back as a soft Canvas2D shadow (ctx.shadowBlur
        // via gfx_draw_shadow_image). This is the nice halo Apple's
        // SKEffectNode + CIFilter idiom gets from a CIGaussianBlur — the same
        // common code, the prettier primitive under the hood.
        if shouldEnableEffects, let cf = filter as? CIFilter,
           cf.name.hasSuffix("GaussianBlur"), cf.inputRadius > 0, !children.isEmpty {
            var bounds = CGRect.zero
            for c in children where !c.isHidden {
                let cf2 = c.frame
                bounds = (bounds == .zero) ? cf2 : bounds.union(cf2)
            }
            let w = Int(bounds.width), h = Int(bounds.height)
            if w > 0 && h > 0 {
                let handle = gfx_offscreen_begin(Int32(w), Int32(h))
                gfx_save()
                gfx_translate(Float(-bounds.minX), Float(-bounds.minY))
                for c in children.sorted(by: { $0.zPosition < $1.zPosition }) {
                    c.renderTree(parentAlpha: eff)
                }
                gfx_restore()
                let img = gfx_offscreen_end_to_image(handle)
                if img > 0 {
                    gfx_draw_shadow_image(img, Float(bounds.minX), Float(bounds.minY),
                                          Float(w), Float(h), Float(cf.inputRadius), 0x000000FF)
                    gfx_free_image(img)   // per-frame bake; release so this.images can't grow unbounded
                }
            }
            gfx_restore()
            return
        }

        // Filter path: render children into an offscreen canvas at their
        // natural sharpness, then drawImage that bitmap back onto the main
        // target with ctx.filter applied so the blur/saturate/etc. actually
        // takes effect. Setting ctx.filter inline on the live target loses
        // the state across the children's own gfx_save/restore boundaries,
        // which is why my prior attempt rendered the shadow with hard edges.
        let usingFilter = shouldEnableEffects && filterString != nil
        if usingFilter, let f = filterString, !children.isEmpty {
            // Bound the offscreen to the union of children's accumulated
            // frames, then pad it so the blur halo doesn't get clipped at
            // the edge. Pad = 16px is enough for a 6px Gaussian blur (the
            // post-it shadow uses blur(6px) at most).
            // Union the children's frames (already in self's coord system
            // thanks to SKShapeNode/SKSpriteNode.frame overrides) to size
            // the offscreen. SKNode.frame includes position so we don't add
            // it again here.
            var bounds = CGRect.zero
            for c in children where !c.isHidden {
                let cf = c.frame
                bounds = (bounds == .zero) ? cf : bounds.union(cf)
            }
            let pad: CGFloat = 16
            let w = Int(bounds.width  + pad * 2)
            let h = Int(bounds.height + pad * 2)
            if w > 0 && h > 0 {
                let handle = gfx_offscreen_begin(Int32(w), Int32(h))
                // Apply the filter on the OFFSCREEN target. Canvas2D's
                // save/restore preserves ctx.filter, so the children's own
                // gfx_save / gfx_restore boundaries can't clobber it. Setting
                // the filter on the main canvas after gfx_offscreen_end and
                // hoping it survives drawImage is unreliable — multiple
                // browsers reset ctx.filter on context switches and after
                // certain composite ops.
                withUTF8Ptr(f) { gfx_set_filter($0, $1) }
                gfx_save()
                gfx_translate(Float(-bounds.minX + pad), Float(-bounds.minY + pad))
                for c in children.sorted(by: { $0.zPosition < $1.zPosition }) {
                    c.renderTree(parentAlpha: eff)
                }
                gfx_restore()
                gfx_clear_filter()
                let img = gfx_offscreen_end_to_image(handle)
                if img > 0 {
                    // No filter on the back-blit — the offscreen already
                    // contains the blurred pixels. -1, -1 source dims route
                    // through gfx_draw_image's 5-arg form so we read the
                    // full backing canvas (not just the top-left at dpr=2).
                    gfx_draw_image(img, 0, 0, -1, -1,
                                   Float(bounds.minX - pad), Float(bounds.minY - pad),
                                   Float(w), Float(h), 0xFFFFFFFF)
                    gfx_free_image(img)   // per-frame bake; release so this.images can't grow unbounded
                }
            }
        } else {
            for c in children.sorted(by: { $0.zPosition < $1.zPosition }) {
                c.renderTree(parentAlpha: eff)
            }
        }
        gfx_restore()
    }
}

// SKCropNode: render the children into an offscreen, render the mask with
// composite mode destination-in so opaque mask pixels keep children, then
// commit the offscreen back to the main target. Apple's mask uses alpha;
// Canvas2D destination-in does the same.
public final class SKCropNode: SKEffectNode {
    public var maskNode: SKNode?
    public override init() { super.init() }

    override func renderTree(parentAlpha: CGFloat) {
        guard let mask = maskNode else {
            // No mask: behave like a transparent container.
            super.renderTree(parentAlpha: parentAlpha)
            return
        }
        if isHidden || alpha <= 0 { return }
        let eff = parentAlpha * alpha

        // Bounds in our local coordinate space.
        let frame = calculateAccumulatedFrame()
        let w = max(1, Int(frame.width)), h = max(1, Int(frame.height))

        gfx_save()
        gfx_translate(Float(position.x), Float(position.y))
        if zRotation != 0 { gfx_rotate(Float(zRotation * 180.0 / Double.pi)) }
        if xScale != 1 || yScale != 1 { gfx_scale(Float(xScale), Float(yScale)) }

        // Render children + mask into an offscreen canvas, then composite back.
        let off = gfx_offscreen_begin(Int32(w), Int32(h))
        // Children first.
        gfx_save()
        gfx_translate(Float(-frame.minX), Float(-frame.minY))
        for c in children.sorted(by: { $0.zPosition < $1.zPosition }) where c !== mask {
            c.renderTree(parentAlpha: eff)
        }
        // Mask second with destination-in: only keep pixels under opaque mask.
        gfx_set_composite(1)   // destination-in
        mask.renderTree(parentAlpha: 1)
        gfx_set_composite(0)   // restore default
        gfx_restore()

        let img = gfx_offscreen_end_to_image(off)
        if img > 0 {
            // Draw the masked image back onto the current target at the
            // child bounding box position.
            gfx_draw_image(img, 0, 0, Float(w), Float(h),
                           Float(frame.minX), Float(frame.minY),
                           Float(w), Float(h), 0xFFFFFFFF)
            gfx_free_image(img)   // per-frame bake; release so this.images can't grow unbounded
        }
        gfx_restore()
    }
}

public enum SKBlendMode: Int {
    case alpha, add, subtract, multiply, multiplyX2, screen, replace
}

// =============================================================================
// SKFieldNode — physics field stub.
//
// Box2D doesn't expose field forces, and most games using these are doing
// gravitational/magnetic feel that Box2D's normal gravity can approximate.
// We record the field type and parameters so game code compiles unchanged.
// =============================================================================
public final class SKFieldNode: SKNode {
    public enum FieldType {
        case linearGravity, radialGravity, vortex, drag, spring, noise, turbulence,
             electric, magnetic, velocityField, customField
    }
    public var fieldType: FieldType = .linearGravity
    public var strength: Float = 1
    public var falloff: Float = 0
    public var minimumRadius: Float = 0
    public var region: Any?
    public var direction = CGVector.zero
    public var isExclusive: Bool = false
    public var categoryBitMask: UInt32 = 0xFFFFFFFF

    public override init() { super.init() }

    public static func linearGravityField(withVector v: CGVector) -> SKFieldNode {
        let n = SKFieldNode(); n.fieldType = .linearGravity; n.direction = v; return n
    }
    public static func radialGravityField() -> SKFieldNode { let n = SKFieldNode(); n.fieldType = .radialGravity; return n }
    public static func vortexField() -> SKFieldNode { let n = SKFieldNode(); n.fieldType = .vortex; return n }
    public static func dragField() -> SKFieldNode { let n = SKFieldNode(); n.fieldType = .drag; return n }
    public static func springField() -> SKFieldNode { let n = SKFieldNode(); n.fieldType = .spring; return n }
    public static func noiseField(withSmoothness s: CGFloat, animationSpeed a: CGFloat) -> SKFieldNode {
        let n = SKFieldNode(); n.fieldType = .noise; return n
    }
    public static func turbulenceField(withSmoothness s: CGFloat, animationSpeed a: CGFloat) -> SKFieldNode {
        let n = SKFieldNode(); n.fieldType = .turbulence; return n
    }
    public static func electricField() -> SKFieldNode { let n = SKFieldNode(); n.fieldType = .electric; return n }
    public static func magneticField() -> SKFieldNode { let n = SKFieldNode(); n.fieldType = .magnetic; return n }
}

// =============================================================================
// SKLightNode — compile-only stub. The kit doesn't run a lighting pass.
// Properties are recorded; sprites that filter by lightingBitMask just render.
// =============================================================================
public final class SKLightNode: SKNode {
    public var isEnabled: Bool = true
    public var ambientColor: SKColor = .black
    public var lightColor: SKColor = .white
    public var shadowColor: SKColor = .black
    public var falloff: CGFloat = 1
    public var categoryBitMask: UInt32 = 1
    public override init() { super.init() }
}

// =============================================================================
// SKTileMapNode — minimal Space-Bar-style grid.
//
// We model just enough to compile games that iterate (column, row) and read
// tile groups. Render hook draws a flat fillColor per cell; richer tileset
// rendering requires hooking SKTexture into the cell lookup.
// =============================================================================
public final class SKTileDefinition {
    public var textures: [SKTexture] = []
    public var name: String?
    public var size = CGSize.zero
    public var timePerFrame: TimeInterval = 0
    public var placementWeight: Int = 1
    public var userData: [String: Any]? = nil
    public init() {}
    public init(texture: SKTexture) { textures = [texture] }
    public init(texture: SKTexture, size: CGSize) { textures = [texture]; self.size = size }
    public init(textures: [SKTexture], size: CGSize, timePerFrame: TimeInterval) {
        self.textures = textures; self.size = size; self.timePerFrame = timePerFrame
    }
}

public final class SKTileGroup {
    public let name: String?
    public var rules: [AnyObject] = []
    public init() { name = nil }
    public init(_ name: String) { self.name = name }
    public init(tileDefinition: SKTileDefinition) { name = tileDefinition.name }
    public init(rules: [AnyObject]) { name = nil; self.rules = rules }
}
public final class SKTileSet {
    public let name: String?
    public init() { name = nil }
    public init(named: String) { self.name = named }
}
public final class SKTileMapNode: SKNode {
    public let numberOfColumns: Int
    public let numberOfRows: Int
    public let tileSize: CGSize
    public var tileSet: SKTileSet
    public var color: SKColor = .clear
    public var colorBlendFactor: CGFloat = 0
    public var enableAutomapping: Bool = false

    var grid: [SKTileGroup?]

    public init(tileSet: SKTileSet, columns: Int, rows: Int, tileSize: CGSize) {
        self.tileSet = tileSet
        self.numberOfColumns = columns
        self.numberOfRows = rows
        self.tileSize = tileSize
        self.grid = Array(repeating: nil, count: columns * rows)
        super.init()
    }
    public func setTileGroup(_ group: SKTileGroup?, forColumn col: Int, row: Int) {
        if col < 0 || row < 0 || col >= numberOfColumns || row >= numberOfRows { return }
        grid[row * numberOfColumns + col] = group
    }
    public func tileGroup(atColumn col: Int, row: Int) -> SKTileGroup? {
        if col < 0 || row < 0 || col >= numberOfColumns || row >= numberOfRows { return nil }
        return grid[row * numberOfColumns + col]
    }
    public func centerOfTile(atColumn col: Int, row: Int) -> CGPoint {
        let x = (CGFloat(col) - CGFloat(numberOfColumns - 1) / 2) * tileSize.width
        let y = (CGFloat(row) - CGFloat(numberOfRows - 1) / 2) * tileSize.height
        return CGPoint(x: x, y: y)
    }
    public func fill(with group: SKTileGroup?) { for i in grid.indices { grid[i] = group } }
}

// =============================================================================
// SKVideoNode — DOM <video> stand-in.
//
// First-pass implementation: stores the source name; play/pause flips a
// no-op flag. Wiring an actual HTML <video> element requires a vid_* ABI
// (deferred). For now this exists so games using video splashes compile.
// =============================================================================
// SKVideoNode — DOM <video> overlay. The vid_* ABI mounts an absolutely
// positioned <video> element above the canvas; play/pause/stop control it.
// Position + size are re-syncd each frame from the node's transform so it
// rides along with parent scrolling / scene transitions.
public final class SKVideoNode: SKNode {
    public let videoName: String?
    public let videoURL: SKAudioURL?
    public var size = CGSize.zero
    public var isPlaying = false
    var videoId: Int32 = -1

    public init(fileNamed name: String) {
        videoName = name; videoURL = nil; super.init()
        self.videoId = withUTF8Ptr(name) { vid_load($0, $1) }
    }
    public init(url: SKAudioURL) {
        videoName = nil; videoURL = url; super.init()
        self.videoId = withUTF8Ptr(url.lastPathComponent) { vid_load($0, $1) }
    }
    public func play()  { if videoId >= 0 { vid_play(videoId); isPlaying = true } }
    public func pause() { if videoId >= 0 { vid_pause(videoId); isPlaying = false } }
    public func stop()  { if videoId >= 0 { vid_stop(videoId);  isPlaying = false } }

    override func draw(alpha: CGFloat) {
        guard videoId >= 0 else { return }
        // Position the DOM video element to match this node's current location.
        // Apple's SKVideoNode uses anchorPoint (0.5, 0.5) implicitly, so center
        // the rect on the absolute position. Y-up to y-down: the SKView root
        // flip is in effect, so we feed the unflipped coords directly.
        let abs = absolutePosition()
        let w = Float(size.width), h = Float(size.height)
        vid_set_rect(videoId, Float(abs.x) - w/2, Float(abs.y) - h/2, w, h)
        vid_set_visible(videoId, isHidden || alpha <= 0 ? 0 : 1)
    }
    public override func removeFromParent() {
        if videoId >= 0 { vid_set_visible(videoId, 0) }
        super.removeFromParent()
    }
}

// =============================================================================
// SKRegion — used by SKFieldNode.region. Compile-only stub.
// =============================================================================
public final class SKRegion {
    public var path: CGPath?
    public init() {}
    public init(radius: Float) {}
    public init(size: CGSize) {}
    public init(path: CGPath) { self.path = path }
}
