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

    public internal(set) weak var node: SKNode?
    var bodyId: Int32 = -1
    var velocityDirty = false

    enum Shape { case rect(CGFloat, CGFloat), circle(CGFloat), edgeLoop(CGRect) }
    let shape: Shape

    public init(rectangleOf size: CGSize) { shape = .rect(size.width, size.height) }
    public init(circleOfRadius r: CGFloat) { shape = .circle(r) }
    public init(edgeLoopFrom rect: CGRect) { shape = .edgeLoop(rect); isDynamic = false }

    public func applyImpulse(_ v: CGVector) { velocity = CGVector(dx: velocity.dx + v.dx, dy: velocity.dy + v.dy) }
    public func applyForce(_ v: CGVector) {}

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
        }
        SKPhysicsWorld.registry[bodyId] = self
    }
}

public final class SKPhysicsWorld {
    public var gravity = CGVector(dx: 0, dy: -9.8)
    public weak var contactDelegate: SKPhysicsContactDelegate?
    nonisolated(unsafe) static var registry: [Int32: SKPhysicsBody] = [:]
    private var started = false

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
