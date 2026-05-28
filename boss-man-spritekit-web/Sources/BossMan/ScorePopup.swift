import SpriteKit

// ScorePopup — the floating "+200" feedback that drifts up and fades out
// when Pete collects a pickup or smashes a boss. Stateless; the caller
// passes the world position and the popup runs a fixed action sequence
// before removing itself from the scene graph.
enum ScorePopup {
    static func show(_ points: Int,
                     at position: CGPoint,
                     in scene: SKNode,
                     color: SKColor = SKColor(red: 1.0, green: 0.85, blue: 0.34, alpha: 1)) {
        let label = SKLabelNode(fontNamed: Strings.Font.menloBold)
        label.text = points >= 0 ? "+\(points)" : "\(points)"
        label.fontSize = 18
        label.fontColor = color
        label.position = position
        label.zPosition = 30
        scene.addChild(label)
        let drift: SKAction = SKAction.group([
            SKAction.moveBy(x: 0, y: 24, duration: 0.7),
            SKAction.fadeAlpha(to: 0,    duration: 0.7),
        ])
        label.run(SKAction.sequence([drift, SKAction.removeFromParent()]))
    }
}
