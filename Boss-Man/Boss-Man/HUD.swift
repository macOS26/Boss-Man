import AppKit
import SpriteKit

@MainActor
final class HUD {
    static let maxLives = 3

    private let statusLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let tpsLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let livesLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let messageLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let levelEmojisLabel = SKLabelNode()
    private let requiredItems: [String]
    private var lifeIcons: [PixelPerson] = []
    private var gameOverOverlay: SKNode?
    // Cache the last-rendered text so we only reassign SKLabelNode.text
    // (which forces a glyph re-rasterization) when the string actually
    // changes. refreshHUD fires on every dot pickup — without caching,
    // each label rebuilds its texture ~7x per second.
    private var lastStatusText: String?
    private var lastTpsText: String?
    private var lastLevelEmojisText: String?
    private var lastLivesCount: Int = -1

    init(requiredItems: [String]) {
        self.requiredItems = requiredItems
    }

    func install(in scene: SKScene) {
        let size = scene.size
        let panelHeight: CGFloat = 104

        let panel = SKShapeNode(rect: CGRect(x: 0, y: size.height - panelHeight, width: size.width, height: panelHeight))
        panel.fillColor = NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.05, alpha: 0.92)
        panel.strokeColor = .systemOrange
        panel.lineWidth = 2
        panel.zPosition = 20
        scene.addChild(panel)

        statusLabel.fontSize = 16
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.verticalAlignmentMode = .center
        statusLabel.position = CGPoint(x: 16, y: size.height - 22)
        statusLabel.zPosition = 21
        statusLabel.fontColor = .white
        scene.addChild(statusLabel)

        tpsLabel.fontSize = 16
        tpsLabel.horizontalAlignmentMode = .left
        tpsLabel.verticalAlignmentMode = .center
        tpsLabel.position = CGPoint(x: 16, y: size.height - 52)
        tpsLabel.zPosition = 21
        tpsLabel.fontColor = .white
        scene.addChild(tpsLabel)

        livesLabel.fontSize = 16
        livesLabel.horizontalAlignmentMode = .left
        livesLabel.verticalAlignmentMode = .center
        livesLabel.position = CGPoint(x: 16, y: size.height - 84)
        livesLabel.zPosition = 21
        livesLabel.fontColor = .systemGreen
        livesLabel.text = "Lives:"
        scene.addChild(livesLabel)

        lifeIcons.removeAll()
        let iconStartX: CGFloat = 90
        let iconSpacing: CGFloat = 24
        for i in 0..<HUD.maxLives {
            let icon = PixelPerson(
                bodyColor: .systemTeal,
                tieColor: .systemBlue,
                hairColor: NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
                shoeOutlineColor: .white,
                pantsColor: NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1)
            )
            icon.setScale(0.45)
            icon.position = CGPoint(x: iconStartX + CGFloat(i) * iconSpacing, y: size.height - 84)
            icon.zPosition = 21
            scene.addChild(icon)
            lifeIcons.append(icon)
        }

        messageLabel.fontSize = 16
        messageLabel.horizontalAlignmentMode = .right
        messageLabel.verticalAlignmentMode = .center
        messageLabel.position = CGPoint(x: size.width - 16, y: size.height - 84)
        messageLabel.zPosition = 21
        messageLabel.fontColor = .systemYellow
        scene.addChild(messageLabel)

        levelEmojisLabel.fontSize = 22
        levelEmojisLabel.horizontalAlignmentMode = .right
        levelEmojisLabel.verticalAlignmentMode = .center
        levelEmojisLabel.position = CGPoint(x: size.width - 16, y: size.height - 30)
        levelEmojisLabel.zPosition = 21
        scene.addChild(levelEmojisLabel)
    }

    private static let emojiByName: [String: String] = [
        "Printer": "🖨️",
        "Fax": "📠",
        "Cover Sheet": "📄",
        "Book Binder": "📚"
    ]

    func updateStatus(score: Int, highScore: Int, level: Int, dots: Int, total: Int, reports: Int, items: Set<String>) {
        let statusText = "Score: \(score)   High: \(highScore)   Level: \(level)   Dots: \(dots)/\(total)   Reports: \(reports)"
        if statusText != lastStatusText {
            statusLabel.text = statusText
            lastStatusText = statusText
        }
        let parts = requiredItems
            .map { name -> String in
                let icon = HUD.emojiByName[name] ?? name
                return items.contains(name) ? "✅\(icon)" : "❌\(icon)"
            }
            .joined(separator: "  ")
        let tpsText = "TPS: \(parts)"
        if tpsText != lastTpsText {
            tpsLabel.text = tpsText
            lastTpsText = tpsText
        }
    }

    func updateLevelEmojis(_ emojis: [String]) {
        let text = emojis.joined(separator: " ")
        if text != lastLevelEmojisText {
            levelEmojisLabel.text = text
            lastLevelEmojisText = text
        }
    }

    func updateLives(_ count: Int) {
        if count == lastLivesCount { return }
        lastLivesCount = count
        for (i, icon) in lifeIcons.enumerated() {
            icon.isHidden = i >= count
        }
    }

    func showMessage(_ text: String, duration: TimeInterval) {
        messageLabel.text = text
        messageLabel.removeAction(forKey: "clear")
        messageLabel.run(.sequence([
            .wait(forDuration: duration),
            .run { [weak self] in self?.messageLabel.text = "" }
        ]), withKey: "clear")
    }

    func showGameOver(in scene: SKScene) {
        hideGameOver()
        let size = scene.size
        let overlay = SKNode()
        overlay.zPosition = 100

        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        dim.fillColor = NSColor(calibratedWhite: 0, alpha: 0.78)
        dim.strokeColor = .clear
        dim.zPosition = 100
        overlay.addChild(dim)

        let frame = SKShapeNode(rect: CGRect(x: size.width / 2 - 260, y: size.height / 2 - 110, width: 520, height: 220), cornerRadius: 6)
        frame.fillColor = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        frame.strokeColor = .systemOrange
        frame.lineWidth = 3
        frame.zPosition = 101
        overlay.addChild(frame)

        let gameOver = SKLabelNode(fontNamed: "Menlo-Bold")
        gameOver.text = "GAME OVER"
        gameOver.fontSize = 56
        gameOver.fontColor = .systemRed
        gameOver.position = CGPoint(x: size.width / 2, y: size.height / 2 + 20)
        gameOver.zPosition = 102
        overlay.addChild(gameOver)

        let prompt = SKLabelNode(fontNamed: "Menlo-Bold")
        prompt.text = "PRESS SPACE TO START A NEW GAME"
        prompt.fontSize = 18
        prompt.fontColor = .systemYellow
        prompt.position = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
        prompt.zPosition = 102
        prompt.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])))
        overlay.addChild(prompt)

        let exit = SKLabelNode(fontNamed: "Menlo-Bold")
        exit.text = "PRESS ESC FOR TITLE SCREEN"
        exit.fontSize = 14
        exit.fontColor = NSColor(calibratedWhite: 0.75, alpha: 1)
        exit.position = CGPoint(x: size.width / 2, y: size.height / 2 - 72)
        exit.zPosition = 102
        overlay.addChild(exit)

        scene.addChild(overlay)
        gameOverOverlay = overlay
    }

    func hideGameOver() {
        gameOverOverlay?.removeFromParent()
        gameOverOverlay = nil
    }
}
