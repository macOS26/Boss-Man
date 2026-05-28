import KitABI

// =============================================================================
// SKShader / SKUniform — compile-only stubs.
//
// Canvas2D has no GLSL pipeline, so any shader attached to a node is recorded
// but ignored at draw time. Games that bind shaders for visual effects degrade
// gracefully to their un-shaded sprites.
// =============================================================================
public final class SKShader {
    public var source: String?
    public var uniforms: [SKUniform] = []
    public var attributes: [SKAttribute] = []

    public init() {}
    public init(source: String) { self.source = source }
    public init(source: String, uniforms: [SKUniform]) { self.source = source; self.uniforms = uniforms }
    public init(fileNamed name: String) {}
    public static func shader(withSource s: String) -> SKShader { SKShader(source: s) }

    public func addUniform(_ u: SKUniform) { uniforms.append(u) }
    public func removeUniformNamed(_ name: String) { uniforms.removeAll { $0.name == name } }
    public func uniformNamed(_ name: String) -> SKUniform? { uniforms.first { $0.name == name } }
}

public final class SKUniform {
    public let name: String
    public var floatValue: Float = 0
    public var vectorFloat2: (Float, Float) = (0, 0)
    public var vectorFloat3: (Float, Float, Float) = (0, 0, 0)
    public var vectorFloat4: (Float, Float, Float, Float) = (0, 0, 0, 0)
    public var textureValue: SKTexture?

    public init(name: String) { self.name = name }
    public init(name: String, float value: Float) { self.name = name; self.floatValue = value }
    public init(name: String, texture: SKTexture?) { self.name = name; self.textureValue = texture }
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
public class SKEffectNode: SKNode {
    public var shouldEnableEffects: Bool = false
    public var shouldRasterize: Bool = false
    public var shouldCenterFilter: Bool = false
    public var blendMode: SKBlendMode = .alpha
    public var filter: AnyObject?      // CIFilter on Apple; ignored here
    public var shader: SKShader?
    public override init() { super.init() }
}

public final class SKCropNode: SKEffectNode {
    public var maskNode: SKNode?
    public override init() { super.init() }
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
public final class SKVideoNode: SKNode {
    public let videoName: String?
    public let videoURL: SKAudioURL?
    public var size = CGSize.zero
    public var isPlaying = false
    public init(fileNamed name: String) { videoName = name; videoURL = nil; super.init() }
    public init(url: SKAudioURL) { videoName = nil; videoURL = url; super.init() }
    public func play()  { isPlaying = true }
    public func pause() { isPlaying = false }
    public func stop()  { isPlaying = false }
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
