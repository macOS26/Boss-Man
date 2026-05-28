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
    // Pixel-perfect init: Canvas2D can't alpha-test a texture cheaply, so we
    // approximate with a rectangle of the requested size. Most games using
    // this end up wrapping a near-rectangular sprite anyway.
    public init(texture: SKTexture, size: CGSize) { shape = .texture(size) }
    public init(texture: SKTexture, alphaThreshold: Float, size: CGSize) { shape = .texture(size) }
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
            bodyId = cb_add_box(Float(rc.midX), Float(rc.midY), Float(rc.width/2), Float(rc.height/2), 0, cat, mask, sensor)
        case let .polygon(pts):
            // Box2D shim only takes boxes/circles; fall back to the bounding
            // box of the polygon points. Close enough for hit detection in
            // most games that supply convex shapes.
            let r = boundingBox(of: pts)
            bodyId = cb_add_box(x + Float(r.midX), y + Float(r.midY),
                                Float(r.width/2), Float(r.height/2), dyn, cat, mask, sensor)
        case let .edgeFromTo(a, b):
            let r = boundingBox(of: [a, b])
            bodyId = cb_add_box(Float(r.midX), Float(r.midY),
                                Float(max(r.width/2, 1)), Float(max(r.height/2, 1)), 0, cat, mask, sensor)
        case let .edgeChain(pts):
            let r = boundingBox(of: pts)
            bodyId = cb_add_box(Float(r.midX), Float(r.midY),
                                Float(max(r.width/2, 1)), Float(max(r.height/2, 1)), 0, cat, mask, sensor)
        case let .texture(size):
            bodyId = cb_add_box(x, y, Float(size.width/2), Float(size.height/2), dyn, cat, mask, sensor)
        }
        SKPhysicsWorld.registry[bodyId] = self
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
    init(_ a: SKPhysicsBody, _ b: SKPhysicsBody) { bodyA = a; bodyB = b }
}
public final class SKPhysicsJointPin: SKPhysicsJoint {
    public var shouldEnableLimits = false
    public var lowerAngleLimit: CGFloat = 0
    public var upperAngleLimit: CGFloat = 0
    public var frictionTorque: CGFloat = 0
    public var rotationSpeed: CGFloat = 0
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchor: CGPoint) -> SKPhysicsJointPin {
        SKPhysicsJointPin(a, b)
    }
}
public final class SKPhysicsJointSpring: SKPhysicsJoint {
    public var damping: CGFloat = 0
    public var frequency: CGFloat = 0
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchorA aa: CGPoint, anchorB ab: CGPoint) -> SKPhysicsJointSpring {
        SKPhysicsJointSpring(a, b)
    }
}
public final class SKPhysicsJointFixed: SKPhysicsJoint {
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchor: CGPoint) -> SKPhysicsJointFixed {
        SKPhysicsJointFixed(a, b)
    }
}
public final class SKPhysicsJointSliding: SKPhysicsJoint {
    public var shouldEnableLimits = false
    public var lowerDistanceLimit: CGFloat = 0
    public var upperDistanceLimit: CGFloat = 0
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchor: CGPoint, axis: CGVector) -> SKPhysicsJointSliding {
        SKPhysicsJointSliding(a, b)
    }
}
public final class SKPhysicsJointLimit: SKPhysicsJoint {
    public var maxLength: CGFloat = 0
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchorA aa: CGPoint, anchorB ab: CGPoint) -> SKPhysicsJointLimit {
        SKPhysicsJointLimit(a, b)
    }
}
public final class SKPhysicsJointDistance: SKPhysicsJoint {
    public static func joint(withBodyA a: SKPhysicsBody, bodyB b: SKPhysicsBody, anchorA aa: CGPoint, anchorB ab: CGPoint) -> SKPhysicsJointDistance {
        SKPhysicsJointDistance(a, b)
    }
}

public final class SKPhysicsWorld {
    public var gravity = CGVector(dx: 0, dy: -9.8)
    public var speed: CGFloat = 1            // not yet honored by the Box2D step
    public weak var contactDelegate: SKPhysicsContactDelegate?
    nonisolated(unsafe) static var registry: [Int32: SKPhysicsBody] = [:]
    private var started = false
    private var joints: [SKPhysicsJoint] = []

    public func add(_ joint: SKPhysicsJoint) { joints.append(joint) }
    public func remove(_ joint: SKPhysicsJoint) { joints.removeAll { $0 === joint } }
    public func removeAllJoints() { joints.removeAll() }

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

    func step(_ dt: TimeInterval, scene: SKScene) {
        if !started { begin(scene); return }
        createBodies(scene)                                   // pick up nodes added since last step
        for (_, b) in SKPhysicsWorld.registry where b.velocityDirty {
            cb_set_velocity(b.bodyId, Float(b.velocity.dx), Float(b.velocity.dy)); b.velocityDirty = false
        }
        cb_step(Float(dt))
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
