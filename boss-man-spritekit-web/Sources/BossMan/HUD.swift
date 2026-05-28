import SpriteKit

// HUD overlay for the maze. First wasm pass keeps the macOS original's
// information density but trims the iconography (TPS reports counter,
// water-gun crop node, level emoji container) until those gameplay loops
// are wired through. What ships today:
//
//   - statusLabel: score + high-score + level + dots, top-left.
//   - livesLabel:  remaining lives, top-left under status.
//   - messageLabel: transient announcement strip, top-right.
//
// All labels live on the SKScene directly so they ride above the maze
// without needing a separate camera layer.
final class HUD {
    private let statusLabel  = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let livesLabel   = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let ammoLabel    = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let messageLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private weak var scene: SKScene?

    func install(in scene: SKScene) {
        self.scene = scene
        let size = scene.size

        statusLabel.fontSize = 19
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.verticalAlignmentMode = .center
        statusLabel.position = CGPoint(x: 16, y: size.height - 22)
        statusLabel.zPosition = 21
        statusLabel.fontColor = .white
        statusLabel.text = ""
        scene.addChild(statusLabel)

        livesLabel.fontSize = 19
        livesLabel.horizontalAlignmentMode = .left
        livesLabel.verticalAlignmentMode = .center
        livesLabel.position = CGPoint(x: 16, y: size.height - 52)
        livesLabel.zPosition = 21
        livesLabel.fontColor = SKColor(red: 0.20, green: 0.85, blue: 0.30, alpha: 1)
        livesLabel.text = "LIVES 3"
        scene.addChild(livesLabel)

        ammoLabel.fontSize = 19
        ammoLabel.horizontalAlignmentMode = .left
        ammoLabel.verticalAlignmentMode = .center
        ammoLabel.position = CGPoint(x: 16, y: size.height - 84)
        ammoLabel.zPosition = 21
        ammoLabel.fontColor = SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)
        ammoLabel.text = "AMMO 0"
        scene.addChild(ammoLabel)

        messageLabel.fontSize = 19
        messageLabel.horizontalAlignmentMode = .right
        messageLabel.verticalAlignmentMode = .center
        messageLabel.position = CGPoint(x: size.width - 16, y: size.height - 22)
        messageLabel.zPosition = 21
        messageLabel.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.34, alpha: 1)
        messageLabel.text = ""
        scene.addChild(messageLabel)
    }

    // MARK: - State updates

    func update(score: Int, highScore: Int, level: Int, dotsLeft: Int) {
        statusLabel.text = "SCORE \(score)   HI \(highScore)   LEVEL \(level)   DOTS \(dotsLeft)"
    }
    func update(lives: Int) {
        livesLabel.text = "LIVES \(max(0, lives))"
    }
    func update(ammo: Int) {
        ammoLabel.text = "AMMO \(max(0, ammo))"
    }
    func flash(_ text: String, duration: TimeInterval = 1.6) {
        messageLabel.removeAllActions()
        messageLabel.text = text
        messageLabel.alpha = 1
        let fade = SKAction.sequence([
            .wait(forDuration: duration),
            .fadeAlpha(to: 0, duration: 0.35),
        ])
        messageLabel.run(fade)
    }
}
