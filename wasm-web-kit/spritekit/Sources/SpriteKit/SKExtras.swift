import KitABI

// Small additions that real SpriteKit games commonly use.

public extension SKNode {
    func run(_ action: SKAction, completion: @escaping () -> Void) {
        run(.sequence([action, .run(completion)]))
    }
    // Coordinate conversion between nodes sharing the scene (translation only;
    // good enough for the unscaled/unrotated cases games usually convert through).
    func absolutePosition() -> CGPoint {
        var p = position, n: SKNode? = parent
        while let cur = n { p = CGPoint(x: p.x + cur.position.x, y: p.y + cur.position.y)
        n = cur.parent }
        return p
    }
    func convert(_ point: CGPoint, from node: SKNode) -> CGPoint {
        let a = node.absolutePosition()
        let me = absolutePosition()
        return CGPoint(x: point.x + a.x - me.x, y: point.y + a.y - me.y)
    }
    func convert(_ point: CGPoint, to node: SKNode) -> CGPoint {
        let me = absolutePosition()
        let other = node.absolutePosition()
        return CGPoint(x: point.x + me.x - other.x, y: point.y + me.y - other.y)
    }
}

public extension SKAction {
    static func fadeAlpha(by factor: CGFloat, duration d: TimeInterval) -> SKAction { fadeAlpha(to: factor, duration: d) }
    static func playSoundFileNamed(_ name: String, waitForCompletion wait: Bool) -> SKAction {
        SKAction.run { let h = withUTF8Ptr(name) { snd_by_name($0, $1) }
        if h != 0 { _ = snd_play(h, 100, 0) } }
    }
}


