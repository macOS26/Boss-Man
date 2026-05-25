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
        circle.fillColor = NSColor.systemCyan.withAlphaComponent(0.85)
        circle.strokeColor = .systemBlue
        circle.lineWidth = 1
        node.addChild(circle)

        let specular = SKShapeNode(circleOfRadius: radius * 0.35)
        specular.fillColor = NSColor(calibratedWhite: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.3, y: radius * 0.3)
        node.addChild(specular)

        node.alpha = 1.0

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
        node.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.4)))

        return node
    }
}