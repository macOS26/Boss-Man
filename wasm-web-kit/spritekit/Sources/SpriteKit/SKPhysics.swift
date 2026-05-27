// Physics types. Phase 3 backs these with the Box2D shim (cb_*); for now the
// world stub lets the scene graph compile and run without physics.
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
    public var velocity = CGVector.zero
    public var linearDamping: CGFloat = 0.1
    public var friction: CGFloat = 0.2
    public var restitution: CGFloat = 0.2
    public var mass: CGFloat = 1
    weak var node: SKNode?
    var bodyId: Int32 = -1
    enum Shape { case rect(CGFloat, CGFloat), circle(CGFloat), edgeLoop(CGRect) }
    let shape: Shape

    public init(rectangleOf size: CGSize) { shape = .rect(size.width, size.height) }
    public init(circleOfRadius r: CGFloat) { shape = .circle(r) }
    public init(edgeLoopFrom rect: CGRect) { shape = .edgeLoop(rect); isDynamic = false }
    public func applyImpulse(_ v: CGVector) { velocity = CGVector(dx: velocity.dx + v.dx, dy: velocity.dy + v.dy) }
    public func applyForce(_ v: CGVector) {}
}

public final class SKPhysicsWorld {
    public var gravity = CGVector(dx: 0, dy: -9.8)
    public weak var contactDelegate: SKPhysicsContactDelegate?
    func step(_ dt: TimeInterval) {}   // phase 3: Box2D
}
