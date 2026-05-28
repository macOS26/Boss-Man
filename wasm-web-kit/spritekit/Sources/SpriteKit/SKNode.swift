import KitABI

// SpriteKit node. World space is y-up (SpriteKit); the SKView root flips it onto
// the kit's y-down Canvas2D. Transforms map to gfx_save/translate/rotate/scale.
open class SKNode {
    public var position = CGPoint.zero
    public var zPosition: CGFloat = 0
    public var xScale: CGFloat = 1
    public var yScale: CGFloat = 1
    public var zRotation: CGFloat = 0       // radians, ccw-positive (SpriteKit)
    public var alpha: CGFloat = 1
    public var isHidden = false
    public var name: String?
    public weak var parent: SKNode?
    public private(set) var children: [SKNode] = []

    public var userData: [String: Any]? = nil
    public var physicsBody: SKPhysicsBody? { didSet { physicsBody?.node = self } }
    public var speed: CGFloat = 1
    public var isPaused = false
    public var constraints: [SKConstraint]? = nil  // applied after stepActions, before render

    public init() {}

    public func setScale(_ s: CGFloat) { xScale = s; yScale = s }

    open func addChild(_ node: SKNode) { node.parent = self; children.append(node) }
    public func insertChild(_ node: SKNode, at index: Int) { node.parent = self; children.insert(node, at: max(0, min(index, children.count))) }
    open func removeFromParent() {
        guard let p = parent else { return }
        p.children.removeAll { $0 === self }
        parent = nil
    }
    public func removeAllChildren() { for c in children { c.parent = nil }; children.removeAll() }
    public func childNode(withName name: String) -> SKNode? { children.first { $0.name == name } }
    public func contains(_ node: SKNode) -> Bool { children.contains { $0 === node } }

    // Swift-friendly enumeration over children (and descendants) matching a name.
    // The block can set `stop = true` to short-circuit.
    public func enumerateChildNodes(withName name: String, using block: (SKNode, inout Bool) -> Void) {
        var stop = false
        enumerateImpl(withName: name, stop: &stop, using: block)
    }
    private func enumerateImpl(withName name: String, stop: inout Bool,
                               using block: (SKNode, inout Bool) -> Void) {
        for c in children {
            if stop { return }
            if c.name == name { block(c, &stop); if stop { return } }
            c.enumerateImpl(withName: name, stop: &stop, using: block)
        }
    }

    public var scene: SKScene? { (self as? SKScene) ?? parent?.scene }

    // ---- rendering ----
    func draw(alpha: CGFloat) {}   // overridden by leaf nodes

    final func renderTree(parentAlpha: CGFloat) {
        if isHidden || alpha <= 0 { return }
        let eff = parentAlpha * alpha
        gfx_save()
        gfx_translate(Float(position.x), Float(position.y))
        if zRotation != 0 { gfx_rotate(Float(-zRotation * 180.0 / Double.pi)) } // flipped space
        if xScale != 1 || yScale != 1 { gfx_scale(Float(xScale), Float(yScale)) }
        draw(alpha: eff)
        if children.count > 1 {
            for c in children.sorted(by: { $0.zPosition < $1.zPosition }) { c.renderTree(parentAlpha: eff) }
        } else {
            for c in children { c.renderTree(parentAlpha: eff) }
        }
        gfx_restore()
    }

    // ---- actions (implemented in SKAction.swift) ----
    var runningActions: [RunningAction] = []
    public func run(_ action: SKAction) { runningActions.append(RunningAction(action)) }
    public func run(_ action: SKAction, withKey key: String) {
        runningActions.removeAll { $0.key == key }
        let r = RunningAction(action); r.key = key; runningActions.append(r)
    }
    public func removeAllActions() { runningActions.removeAll() }
    public func removeAction(forKey key: String) { runningActions.removeAll { $0.key == key } }
    public func action(forKey key: String) -> SKAction? { runningActions.first { $0.key == key }?.action }
    public var hasActions: Bool { !runningActions.isEmpty }

    final func stepActions(_ dt: CGFloat) {
        if isPaused { return }                       // halt this subtree
        let scaled = dt * speed                      // SKNode.speed scales time per subtree
        var i = 0
        while i < runningActions.count {
            if runningActions[i].step(scaled, node: self) { runningActions.remove(at: i) } else { i += 1 }
        }
        tickSelf(TimeInterval(scaled))
        if let cs = constraints {                    // post-action constraint pass
            for c in cs { c.apply(to: self) }
        }
        for c in children { c.stepActions(scaled) }
    }

    // Per-frame update hook for nodes that animate themselves (e.g. SKEmitterNode).
    // Default is a no-op; overridden by node types that need to advance state.
    open func tickSelf(_ dt: TimeInterval) {}
}
