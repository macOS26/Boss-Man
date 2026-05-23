import AppKit
import SpriteKit

@MainActor
enum ScorePopup {
    static func show(_ points: Int, at position: CGPoint, in scene: SKScene, color: NSColor = .systemYellow) {
        let popup = SKLabelNode(fontNamed: Strings.Font.menloBold)
        popup.text = Strings.Score.popup(points)
        popup.fontSize = 18
        popup.fontColor = color
        popup.position = CGPoint(x: position.x, y: position.y + 20)
        popup.zPosition = 12
        scene.addChild(popup)
        popup.run(.sequence([
            .group([
                .moveBy(x: 0, y: 28, duration: 0.7),
                .fadeOut(withDuration: 0.7)
            ]),
            .removeFromParent()
        ]))
    }
}
