import AppKit
import SpriteKit

/// One-off "+N" score popup that floats upward and fades. Lives in its
/// own file so the scene doesn't have to.
@MainActor
enum ScorePopup {
    static func show(_ points: Int, at position: CGPoint, in scene: SKScene) {
        let popup = SKLabelNode(fontNamed: "Menlo-Bold")
        popup.text = "\(points)"
        popup.fontSize = 18
        popup.fontColor = .systemYellow
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
