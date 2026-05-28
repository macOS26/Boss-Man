import KitABI

// Physics on the Box2D shim (cb_*; defined in libcbox2d.a). SpriteKit points are
// used directly as Box2D coordinates (y-up, same as the scene). Dynamic bodies
// are driven by the simulation and sync back to their SKNode each step; bodies
// the game drives by velocity push that velocity in before stepping.
public protocol SKPhysicsContactDelegate: AnyObject {
    func didBegin(_ contact: SKPhysicsContact)
    func didEnd(_ contact: SKPhysicsContact)
}
public extension SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {}
    func didEnd(_ contact: SKPhysicsContact) {}
}

public final class SKPhysicsContact {
    public let bodyA: SKPhysicsBody
    public let bodyB: SKPhysicsBody
    public var contactPoint: CGPoint = .zero
    public var contactNormal: CGVector = .zero
    public var collisionImpulse: CGFloat = 0
    init(_ a: SKPhysicsBody, _ b: SKPhysicsBody) { bodyA = a; bodyB = b }
}

public final class SKPhysicsBody {
    public var categoryBitMask: UInt32 = 0xFFFFFFFF
    public var contactTestBitMask: UInt32 = 0
    public var collisionBitMask: UInt32 = 0xFFFFFFFF
    public var isDynamic = true
    public var affectedByGravity = true
    public var allowsRotation = true
    public var velocity = CGVector.zero { didSet { velocityDirty = true } }
    public var linearDamping: CGFloat = 0.1
    public var friction: CGFloat = 0.2
    public var restitution: CGFloat = 0.2
    public var mass: CGFloat = 1
    public var isSensor = false
    public var usesPreciseCollisionDetection = false   // no-op: Box2D continuous detection
    public var fieldBitMask: UInt32 = 0xFFFFFFFF       // no-op: SKFieldNode not yet implemented
    public var pinned = false                          // no-op
    public var density: CGFloat = 1                    // no-op (mass drives the body)
    public var angularDamping: CGFloat = 0.1           // no-op
    public var angularVelocity: CGFloat = 0            // no-op (Box2D shim takes linear velocity only)
    public var charge: CGFloat = 0                     // no-op (SKFieldNode interaction)
    public var resting: Bool = false                   // no-op
    public var area: CGFloat { 0 }                     // computed by shape; cheap to leave at 0

    public internal(set) weak var node: SKNode?
    var bodyId: Int32 = -1
    var velocityDirty = false

    enum Shape {
        case rect(CGFloat, CGFloat)
        case circle(CGFloat)
        case edgeLoop(CGRect)
        case polygon([CGPoint])
        case edgeFromTo(CGPoint, CGPoint)
        case edgeChain([CGPoint])
        case texture(CGSize)            // pixel-perfect init falls back to rect of `size`
    }
    let shape: Shape

    public init(rectangleOf size: CGSize) { shape = .rect(size.width, size.height) }
    public init(rectangleOf size: CGSize, center: CGPoint) { shape = .rect(size.width, size.height) }
    public init(circleOfRadius r: CGFloat) { shape = .circle(r) }
    public init(circleOfRadius r: CGFloat, center: CGPoint) { shape = .circle(r) }
    public init(edgeLoopFrom rect: CGRect) { shape = .edgeLoop(rect); isDynamic = false }
    public init(edgeLoopFrom path: CGPath) {
        let pts = path.flattenedPoints
        shape = .edgeChain(pts.isEmpty ? [.zero, .zero] : pts)
        isDynamic = false
    }
    public init(edgeChainFrom path: CGPath) {
        shape = .edgeChain(path.flattenedPoints)
        isDynamic = false
    }
    public init(edgeFrom a: CGPoint, to b: CGPoint) {
        shape = .edgeFromTo(a, b)
        isDynamic = false
    }
    public init(polygonFrom path: CGPath) { shape = .polygon(path.flattenedPoints) }
    // Pixel-perfect init: ask the runtime to trace the texture's alpha
    // boundary (img_polygon_from_alpha runs marching-squares + RDP simplify in
    // the JS side). If tracing fails or returns fewer than 3 points (e.g. the
    // texture isn't loaded yet, or its host blocks getImageData), fall back to
    // a rectangle of the requested size.
    public init(texture: SKTexture, size: CGSize) {
        if let poly = SKPhysicsBody.polygonFromAlpha(texture: texture, threshold: 0.0, fit: size) {
            shape = .polygon(poly)
        } else {
            shape = .texture(size)
        }
    }
    public init(texture: SKTexture, alphaThreshold: Float, size: CGSize) {
        if let poly = SKPhysicsBody.polygonFromAlpha(texture: texture, threshold: alphaThreshold, fit: size) {
            shape = .polygon(poly)
        } else {
            shape = .texture(size)
        }
    }

    // Pulls up to 64 polygon points from the texture's alpha channel through
    // the kit ABI, then scales them to fit `size` (centered on origin). Returns
    // nil when the trace yields < 3 points (image hasn't loaded, blocked by
    // CORS getImageData, etc.); the caller falls back to a rect body.
    private static func polygonFromAlpha(texture: SKTexture, threshold: Float, fit size: CGSize) -> [CGPoint]? {
        var buf = [Float](repeating: 0, count: 64 * 2)
        let n = Int(buf.withUnsafeMutableBufferPointer { ptr in
            img_polygon_from_alpha(texture.handle, threshold, ptr.baseAddress, Int32(64))
        })
        if n < 3 { return nil }
        // The runtime returns centered, y-up coordinates in pixels; rescale to
        // the requested body size.
        var minX = Float.infinity, maxX = -Float.infinity, minY = Float.infinity, maxY = -Float.infinity
        for i in 0..<n {
            let x = buf[i*2], y = buf[i*2+1]
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
        let rangeX = max(maxX - minX, 0.0001), rangeY = max(maxY - minY, 0.0001)
        let sx = Float(size.width)  / rangeX
        let sy = Float(size.height) / rangeY
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            out.append(CGPoint(x: CGFloat(buf[i*2] * sx), y: CGFloat(buf[i*2+1] * sy)))
        }
        return out
    }
    public init(bodies: [SKPhysicsBody]) { shape = .rect(0, 0) }   // compound bodies: stub

    public func applyImpulse(_ v: CGVector) { velocity = CGVector(dx: velocity.dx + v.dx, dy: velocity.dy + v.dy) }
    public func applyImpulse(_ v: CGVector, at point: CGPoint) { applyImpulse(v) }
    public func applyForce(_ v: CGVector) {}
    public func applyForce(_ v: CGVector, at point: CGPoint) {}
    public func applyTorque(_ t: CGFloat) {}
    public func applyAngularImpulse(_ i: CGFloat) {}

    // Returns the set of bodies currently in contact with this one. The Box2D
    // shim doesn't expose a continuous contact list yet, so we filter the
    // global registry by node proximity; good enough for game-level checks.
    public func allContactedBodies() -> [SKPhysicsBody] {
        guard let n = node else { return [] }
        return SKPhysicsWorld.registry.values.filter { other in
            guard other !== self, let on = other.node else { return false }
            let dx = n.position.x - on.position.x, dy = n.position.y - on.position.y
            return (dx*dx + dy*dy) < 4096   // ~64px radius rough cull
        }
    }

    func createInWorld() {
        guard bodyId < 0, let n = node else { return }
        let x = Float(n.position.x), y = Float(n.position.y)
        let cat = UInt16(truncatingIfNeeded: categoryBitMask)
        let mask = UInt16(truncatingIfNeeded: collisionBitMask)
        let dyn: Int32 = isDynamic ? 1 : 0
        let sensor: Int32 = isSensor ? 1 : 0
        switch shape {
        case let .rect(w, h): bodyId = cb_add_box(x, y, Float(w/2), Float(h/2), dyn, cat, mask, sensor)
        case let .circle(r):  bodyId = cb_add_circle(x, y, Float(r), dyn, cat, mask, sensor)
        case let .edgeLoop(rc):
            // Closed-loop chain of the rect's four corners (static).
            let pts: [CGPoint] = [
                CGPoint(x: rc.minX, y: rc.minY), CGPoint(x: rc.maxX, y: rc.minY),
                CGPoint(x: rc.maxX, y: rc.maxY), CGPoint(x: rc.minX, y: rc.maxY),
            ]
            bodyId = withFlatXY(pts) { ptr, n in cb_add_chain(ptr, n, 1, cat, mask) }
        case let .polygon(pts):
            // Real convex polygon (up to b2_maxPolygonVertices); Box2D enforces
            // convexity and vertex count. Falls back to AABB on degenerate inputs.
            if pts.count >= 3 {
                bodyId = withFlatXY(pts) { ptr, n in cb_add_polygon(x, y, ptr, n, dyn, cat, mask, sensor) }
            } else {
                let r = boundingBox(of: pts)
                bodyId = cb_add_box(x + Float(r.midX), y + Float(r.midY),
                                    Float(r.width/2), Float(r.height/2), dyn, cat, mask, sensor)
            }
        case let .edgeFromTo(a, b):
            bodyId = cb_add_edge(Float(a.x), Float(a.y), Float(b.x), Float(b.y), cat, mask)
        case let .edgeChain(pts):
            bodyId = withFlatXY(pts) { ptr, n in cb_add_chain(ptr, n, 0, cat, mask) }
        case let .texture(size):
            bodyId = cb_add_box(x, y, Float(size.width/2), Float(size.height/2), dyn, cat, mask, sensor)
        }
        SKPhysicsWorld.registry[bodyId] = self
    }
}

// Flatten a [CGPoint] into a contiguous [Float] pair-buffer and hand a pointer
// + count to the closure. Used for cb_add_polygon / cb_add_chain.
@inline(__always)
private func withFlatXY<R>(_ pts: [CGPoint], _ body: (UnsafePointer<Float>, Int32) -> R) -> R {
    var flat = [Float](); flat.reserveCapacity(pts.count * 2)
    for p in pts { flat.append(Float(p.x)); flat.append(Float(p.y)) }
    return flat.withUnsafeBufferPointer { buf in
        body(buf.baseAddress!, Int32(pts.count))
    }
}

// Quick AABB over an arbitrary point list — used for polygon/edge body fallback.
private func boundingBox(of pts: [CGPoint]) -> CGRect {
    guard let first = pts.first else { return .zero }
    var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
    for p in pts.dropFirst() {
        if p.x < minX { minX = p.x }; if p.x > maxX { maxX = p.x }
        if p.y < minY { minY = p.y }; if p.y > maxY { maxY = p.y }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

// =============================================================================
// SKPhysicsJoint family — compile-only stubs. The Box2D shim doesn't yet
// surface a create-joint API, so calls succeed but the joint isn't simulated.
// Games using SKPhysicsJointPin (UFOEmoji's flight yoke) compile unchanged.
// =============================================================================
public class SKPhysicsJoint {
    public var bodyA: SKPhysicsBody
    public var bodyB: SKPhysicsBody
    public var reactionForce = CGVector.zero
    public var reactionTorque: CGFloat = 0
    var jointId: Int32 = -1
    init(_ a: SKPhysicsBody, _ b: SKPhysicsBody) { bodyA = a; bodyB = b }
    // Subclasses override to create the joint in the Box2D world once both
    // bodies are registered. SKPhysicsWorld.add calls this.
    func createInWorld() {}
}
public final class SKPhysicsJointPin: SKPhysicsJoint {
    public var shouldEnableLimits = false
    public var lowerAngleLimit: CGFloat = 0
    public var upperAngleLimit: CGFloat = 0
    public var frictionTorque: CGFloat = 0
    public var rotationSpeed: CGFloat = 0
    var anchor: CGPoint = .zero
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchor: CGPoint) -> SKPhysicsJointPin {
        let j = SKPhysicsJointPin(a, b); j.anchor = anchor; return j
    }
    override func createInWorld() {
        if jointId >= 0 || bodyA.bodyId < 0 || bodyB.bodyId < 0 { return }
        jointId = cb_add_joint_pin(bodyA.bodyId, bodyB.bodyId, Float(anchor.x), Float(anchor.y),
                                   shouldEnableLimits ? 1 : 0,
                                   Float(lowerAngleLimit), Float(upperAngleLimit),
                                   Float(frictionTorque), Float(rotationSpeed))
    }
}
public final class SKPhysicsJointSpring: SKPhysicsJoint {
    public var damping: CGFloat = 0
    public var frequency: CGFloat = 1
    var anchorA: CGPoint = .zero, anchorB: CGPoint = .zero
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchorA aa: CGPoint, anchorB ab: CGPoint) -> SKPhysicsJointSpring {
        let j = SKPhysicsJointSpring(a, b); j.anchorA = aa; j.anchorB = ab; return j
    }
    override func createInWorld() {
        if jointId >= 0 || bodyA.bodyId < 0 || bodyB.bodyId < 0 { return }
        jointId = cb_add_joint_spring(bodyA.bodyId, bodyB.bodyId,
                                      Float(anchorA.x), Float(anchorA.y),
                                      Float(anchorB.x), Float(anchorB.y),
                                      Float(frequency), Float(damping))
    }
}
public final class SKPhysicsJointFixed: SKPhysicsJoint {
    var anchor: CGPoint = .zero
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchor: CGPoint) -> SKPhysicsJointFixed {
        let j = SKPhysicsJointFixed(a, b); j.anchor = anchor; return j
    }
    override func createInWorld() {
        if jointId >= 0 || bodyA.bodyId < 0 || bodyB.bodyId < 0 { return }
        jointId = cb_add_joint_fixed(bodyA.bodyId, bodyB.bodyId, Float(anchor.x), Float(anchor.y))
    }
}
public final class SKPhysicsJointSliding: SKPhysicsJoint {
    public var shouldEnableLimits = false
    public var lowerDistanceLimit: CGFloat = 0
    public var upperDistanceLimit: CGFloat = 0
    var anchor: CGPoint = .zero, axis: CGVector = CGVector(dx: 1, dy: 0)
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchor: CGPoint, axis: CGVector) -> SKPhysicsJointSliding {
        let j = SKPhysicsJointSliding(a, b); j.anchor = anchor; j.axis = axis; return j
    }
    override func createInWorld() {
        if jointId >= 0 || bodyA.bodyId < 0 || bodyB.bodyId < 0 { return }
        jointId = cb_add_joint_sliding(bodyA.bodyId, bodyB.bodyId,
                                       Float(anchor.x), Float(anchor.y),
                                       Float(axis.dx), Float(axis.dy),
                                       shouldEnableLimits ? 1 : 0,
                                       Float(lowerDistanceLimit), Float(upperDistanceLimit))
    }
}
public final class SKPhysicsJointLimit: SKPhysicsJoint {
    public var maxLength: CGFloat = 0
    var anchorA: CGPoint = .zero, anchorB: CGPoint = .zero
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchorA aa: CGPoint, anchorB ab: CGPoint) -> SKPhysicsJointLimit {
        let j = SKPhysicsJointLimit(a, b); j.anchorA = aa; j.anchorB = ab; return j
    }
    override func createInWorld() {
        if jointId >= 0 || bodyA.bodyId < 0 || bodyB.bodyId < 0 { return }
        jointId = cb_add_joint_limit(bodyA.bodyId, bodyB.bodyId,
                                     Float(anchorA.x), Float(anchorA.y),
                                     Float(anchorB.x), Float(anchorB.y),
                                     Float(maxLength))
    }
}
public final class SKPhysicsJointDistance: SKPhysicsJoint {
    var anchorA: CGPoint = .zero, anchorB: CGPoint = .zero
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchorA aa: CGPoint, anchorB ab: CGPoint) -> SKPhysicsJointDistance {
        let j = SKPhysicsJointDistance(a, b); j.anchorA = aa; j.anchorB = ab; return j
    }
    override func createInWorld() {
        if jointId >= 0 || bodyA.bodyId < 0 || bodyB.bodyId < 0 { return }
        jointId = cb_add_joint_distance(bodyA.bodyId, bodyB.bodyId,
                                        Float(anchorA.x), Float(anchorA.y),
                                        Float(anchorB.x), Float(anchorB.y))
    }
}

public final class SKPhysicsWorld {
    public var gravity = CGVector(dx: 0, dy: -9.8)
    public var speed: CGFloat = 1            // not yet honored by the Box2D step
    public weak var contactDelegate: SKPhysicsContactDelegate?
    nonisolated(unsafe) static var registry: [Int32: SKPhysicsBody] = [:]
    private var started = false
    private var joints: [SKPhysicsJoint] = []

    // Create the joint in Box2D as soon as both bodies are registered. If
    // bodies are still missing, the joint is deferred and tried again from
    // step() (see createPendingJoints).
    public func add(_ joint: SKPhysicsJoint) {
        joints.append(joint)
        joint.createInWorld()
    }
    public func remove(_ joint: SKPhysicsJoint) {
        if joint.jointId >= 0 { cb_remove_joint(joint.jointId); joint.jointId = -1 }
        joints.removeAll { $0 === joint }
    }
    public func removeAllJoints() {
        for j in joints where j.jointId >= 0 { cb_remove_joint(j.jointId); j.jointId = -1 }
        joints.removeAll()
    }
    fileprivate func createPendingJoints() {
        for j in joints where j.jointId < 0 { j.createInWorld() }
    }

    // Hit testing: caller-driven, no Box2D query yet. We scan the registry.
    public func body(at point: CGPoint) -> SKPhysicsBody? {
        SKPhysicsWorld.registry.values.first { b in
            guard let n = b.node else { return false }
            let dx = point.x - n.position.x, dy = point.y - n.position.y
            return (dx*dx + dy*dy) < 256
        }
    }
    public func body(in rect: CGRect) -> SKPhysicsBody? {
        SKPhysicsWorld.registry.values.first { b in
            guard let n = b.node else { return false }
            return rect.contains(n.position)
        }
    }
    public func enumerateBodies(at point: CGPoint, using block: (SKPhysicsBody, UnsafeMutablePointer<Bool>) -> Void) {
        var stop = false
        for b in SKPhysicsWorld.registry.values {
            if stop { return }
            if let n = b.node {
                let dx = point.x - n.position.x, dy = point.y - n.position.y
                if (dx*dx + dy*dy) < 256 { block(b, &stop) }
            }
        }
    }
    public func enumerateBodies(in rect: CGRect, using block: (SKPhysicsBody, UnsafeMutablePointer<Bool>) -> Void) {
        var stop = false
        for b in SKPhysicsWorld.registry.values {
            if stop { return }
            if let n = b.node, rect.contains(n.position) { block(b, &stop) }
        }
    }
    // Ray-cast: walks bodies along a line segment in scene space, returning
    // the first body hit. The Box2D shim doesn't yet expose a ray query, so
    // we sample at fixed intervals — accurate enough for most game queries.
    public func body(alongRayStart start: CGPoint, end: CGPoint) -> SKPhysicsBody? {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = (Double(dx*dx + dy*dy)).squareRoot()
        if len == 0 { return body(at: start) }
        let steps = max(2, Int(len / 8))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            if let b = body(at: p) { return b }
        }
        return nil
    }
    public func enumerateBodies(alongRayStart start: CGPoint, end: CGPoint,
                                using block: (SKPhysicsBody, CGPoint, CGVector, UnsafeMutablePointer<Bool>) -> Void) {
        var stop = false
        let dx = end.x - start.x, dy = end.y - start.y
        let len = (Double(dx*dx + dy*dy)).squareRoot()
        if len == 0 { return }
        let steps = max(2, Int(len / 8))
        var seen = Set<Int32>()
        for i in 0...steps {
            if stop { return }
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            if let b = body(at: p), !seen.contains(b.bodyId) {
                seen.insert(b.bodyId)
                block(b, p, CGVector(dx: dx / CGFloat(len), dy: dy / CGFloat(len)), &stop)
            }
        }
    }

    func begin(_ scene: SKScene) {
        SKPhysicsWorld.registry.removeAll()
        cb_reset(Float(gravity.dx), Float(gravity.dy))
        started = true
        createBodies(scene)
    }

    private func createBodies(_ node: SKNode) {
        if let b = node.physicsBody, b.bodyId < 0 { b.node = node; b.createInWorld() }
        for c in node.children { createBodies(c) }
    }

    // Walk the scene once collecting active field nodes, then for every
    // dynamic body whose fieldBitMask overlaps the field's categoryBitMask,
    // sample the force the field would apply at the body's position and call
    // cb_apply_force. Field models honored: linearGravity, radialGravity,
    // vortex, drag, spring, magnetic (treated as radialGravity with sign),
    // noise/turbulence/electric/customField left as no-ops.
    private func applyFields(_ scene: SKNode, dt: TimeInterval) {
        var fields: [SKFieldNode] = []
        collectFields(scene, into: &fields)
        if fields.isEmpty { return }
        for (_, body) in SKPhysicsWorld.registry {
            guard body.isDynamic, let n = body.node else { continue }
            let p = n.absolutePosition()
            for f in fields where (f.categoryBitMask & body.fieldBitMask) != 0 {
                let fp = f.absolutePosition()
                let dx: CGFloat = p.x - fp.x
                let dy: CGFloat = p.y - fp.y
                let dist: CGFloat = (dx*dx + dy*dy).squareRoot()
                if f.minimumRadius > 0 && dist < CGFloat(f.minimumRadius) { continue }
                let atten: CGFloat = (f.falloff > 0 && dist > 0)
                    ? 1 / CGFloat(sb64_pow(Double(dist), Double(f.falloff)))
                    : 1
                let strength: CGFloat = CGFloat(f.strength) * atten
                var fx: CGFloat = 0, fy: CGFloat = 0
                switch f.fieldType {
                case .linearGravity:
                    fx = strength * f.direction.dx
                    fy = strength * f.direction.dy
                case .radialGravity:
                    if dist == 0 { continue }
                    fx = (-dx / dist) * strength; fy = (-dy / dist) * strength
                case .vortex:
                    if dist == 0 { continue }
                    fx = (-dy / dist) * strength; fy = ( dx / dist) * strength
                case .drag:
                    fx = -body.velocity.dx * strength
                    fy = -body.velocity.dy * strength
                case .spring:
                    fx = -dx * strength
                    fy = -dy * strength
                case .magnetic:
                    if dist == 0 { continue }
                    let s = strength * body.charge
                    fx = (-dx / dist) * s; fy = (-dy / dist) * s
                case .noise, .turbulence, .electric, .velocityField, .customField:
                    continue
                }
                cb_apply_force(body.bodyId, Float(fx), Float(fy))
            }
        }
        _ = dt   // currently unused; kept for future per-frame ramping
    }
    private func collectFields(_ node: SKNode, into out: inout [SKFieldNode]) {
        if let f = node as? SKFieldNode { out.append(f) }
        for c in node.children { collectFields(c, into: &out) }
    }

    func step(_ dt: TimeInterval, scene: SKScene) {
        if !started { begin(scene); return }
        createBodies(scene)                                   // pick up nodes added since last step
        createPendingJoints()                                 // joints added before their bodies
        applyFields(scene, dt: dt)                            // SKFieldNode → cb_apply_force
        for (_, b) in SKPhysicsWorld.registry where b.velocityDirty {
            cb_set_velocity(b.bodyId, Float(b.velocity.dx), Float(b.velocity.dy)); b.velocityDirty = false
        }
        // Push every body's Box2D transform FROM its SKNode each frame
        // so contact detection always sees the actual current scene
        // positions. Apple SpriteKit does this implicitly; SuperBox64
        // has to do it explicitly because Box2D bodies don't observe
        // SKNode mutations on their own.
        //
        // This is the missing half of node<->body sync. Without it, a
        // dynamic body that the game moves via SKAction.move or by
        // writing node.position directly (which is what every consumer
        // does, including bossman-apple) stays at its spawn position
        // in Box2D's world — and no contacts fire because the body
        // never goes anywhere as far as Box2D is concerned.
        for (id, b) in SKPhysicsWorld.registry {
            guard let n = b.node else { continue }
            cb_set_transform(id, Float(n.position.x), Float(n.position.y),
                             Float(n.zRotation))
        }
        cb_step(Float(dt))
        // Read positions back for true dynamic bodies (so simulated
        // motion — gravity, contacts with non-zero collisionBitMask —
        // is visible). For game-driven bodies the read-back will equal
        // what we just pushed in.
        for (id, b) in SKPhysicsWorld.registry {
            guard b.isDynamic, let n = b.node else { continue }
            var x: Float = 0, y: Float = 0
            cb_get_position(id, &x, &y)
            n.position = CGPoint(x: CGFloat(x), y: CGFloat(y))
            if b.allowsRotation { n.zRotation = CGFloat(cb_get_angle(id)) }
        }
        var ca: Int32 = 0, cbb: Int32 = 0, ba: Int32 = 0, bb: Int32 = 0
        while cb_poll_contact(&ca, &cbb, &ba, &bb) != 0 {
            guard let A = SKPhysicsWorld.registry[ba], let B = SKPhysicsWorld.registry[bb] else { continue }
            let hit = (UInt32(truncatingIfNeeded: ca) & B.contactTestBitMask) != 0
                   || (UInt32(truncatingIfNeeded: cbb) & A.contactTestBitMask) != 0
            if hit { contactDelegate?.didBegin(SKPhysicsContact(A, B)) }
        }
    }
}
