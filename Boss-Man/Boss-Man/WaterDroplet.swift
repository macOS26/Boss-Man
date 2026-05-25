import SpriteKit

enum WaterDroplet {
    private static let radius: CGFloat = 5
    private static let speed: CGFloat = 320
    private static let maxDistance: CGFloat = 576

    static func fire(from position: CGPoint, direction: MoveDirection, tileSize: CGFloat) -> SKNode {
        let node = SKNode()
        node.name = "waterDroplet"
        node.zPosition = 12

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = NSColor.systemTeal.withAlphaComponent(0.7)
        circle.strokeColor = .systemBlue
        circle.lineWidth = 1
        node.addChild(circle)
        node.alpha = 0.8

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.isDynamic = true
        body.affectedByGravity = false
        body.categoryBitMask = PhysicsCategory.waterDroplet
        body.contactTestBitMask = PhysicsCategory.boss | PhysicsCategory.wall
        body.collisionBitMask = 0
        body.usesPreciseCollisionDetection = true
        node.physicsBody = body

        let dx = CGFloat(direction.delta.dx)
        let dy = CGFloat(direction.delta.dy)
        let target = CGPoint(x: position.x + dx * maxDistance,
                             y: position.y + dy * maxDistance)
        let distance = maxDistance
        let duration = TimeInterval(distance / speed)

        node.position = CGPoint(x: position.x + dx * (tileSize / 2 + radius + 2),
                                y: position.y + dy * (tileSize / 2 + radius + 2))

        let move = SKAction.move(to: target, duration: duration)
        let remove = SKAction.removeFromParent()
        node.run(.sequence([move, remove]), withKey: Strings.ActionKey.waterDropletMove)

        return node
    }
}