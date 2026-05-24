import AppKit
import SpriteKit

@MainActor
final class HUD {
    static let startingLives = 3
    static let maxLives = 5

    private let statusLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let tpsLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let livesLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let messageLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let levelEmojisContainer = SKNode()
    private let requiredItems: [String]
    private var lifeIcons: [PixelPerson] = []
    private var gameOverOverlay: SKNode?
    private var lastStatusText: String?
    private var lastTpsText: String?
    private var lastLevelEmojisText: String?
    private var lastLivesCount: Int = -1

    init(requiredItems: [String]) {
        self.requiredItems = requiredItems
    }

    func install(in scene: SKScene) {
        let size = scene.size
        let panelHeight: CGFloat = 100

        let panel = SKShapeNode(rect: CGRect(x: 0, y: size.height - panelHeight, width: size.width, height: panelHeight))
        panel.fillColor = NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.05, alpha: 0.92)
        panel.strokeColor = .clear
        panel.lineWidth = 0
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
        livesLabel.text = Strings.HUD.livesPrefix
        scene.addChild(livesLabel)

        lifeIcons.removeAll()
        lastLivesCount = -1
        lastStatusText = nil
        lastTpsText = nil
        lastLevelEmojisText = nil
        let iconStartX: CGFloat = 90
        let iconSpacing: CGFloat = 24
        for i in 0..<HUD.maxLives {
            let icon = PixelPerson(
                bodyColor: .systemBlue,
                tieColor: .systemOrange,
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

        levelEmojisContainer.position = CGPoint(x: size.width - 28, y: size.height - 30)
        levelEmojisContainer.zPosition = 21
        scene.addChild(levelEmojisContainer)
    }

    private static let emojiByName: [String: String] = [
        Strings.Machine.printer:    Strings.Emoji.printer,
        Strings.Machine.fax:        Strings.Emoji.fax,
        Strings.Machine.coverSheet: Strings.Emoji.coverSheet,
        Strings.Machine.bookBinder: Strings.Emoji.bookBinder
    ]

    func updateStatus(score: Int, highScore: Int, level: Int, dots: Int, total: Int, reports: Int, items: Set<String>) {
        let statusText = Strings.HUD.statusLine(score: score, highScore: highScore,
                                                 level: level, dots: dots,
                                                 total: total, reports: reports)
        if statusText != lastStatusText {
            statusLabel.text = statusText
            lastStatusText = statusText
        }
        let parts = requiredItems
            .map { name -> String in
                let icon = HUD.emojiByName[name] ?? name
                return items.contains(name)
                    ? "\(Strings.Emoji.checked)\(icon)"
                    : "\(Strings.Emoji.unchecked)\(icon)"
            }
            .joined(separator: Strings.HUD.tpsItemSeparator)
        let tpsText = "\(Strings.HUD.tpsPrefix) \(parts)"
        if tpsText != lastTpsText {
            tpsLabel.text = tpsText
            lastTpsText = tpsText
        }
    }

    func updateLevelEmojis(_ travelers: [LevelTraveler]) {
        let key = travelers.map { $0.image ?? $0.emoji }.joined(separator: ",")
        if key == lastLevelEmojisText { return }
        lastLevelEmojisText = key

        levelEmojisContainer.removeAllChildren()
        let pointSize: CGFloat = 18
        let spacing:   CGFloat = 26
        let count = travelers.count
        for (i, t) in travelers.enumerated() {
            let glyph = TravelerGlyph.makeNode(for: t, pointSize: pointSize)
            let xOffset: CGFloat = t.image != nil ? -1.5 : 0
            let yOffset: CGFloat = t.image != nil ? -2   : 0
            glyph.position = CGPoint(x: CGFloat(i - (count - 1)) * spacing + xOffset, y: yOffset)
            if t.image != nil { glyph.xScale = -1 }
            levelEmojisContainer.addChild(glyph)
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
        messageLabel.removeAction(forKey: Strings.ActionKey.clear)
        messageLabel.run(.sequence([
            .wait(forDuration: duration),
            .run { [weak self] in self?.messageLabel.text = Strings.HUD.empty }
        ]), withKey: Strings.ActionKey.clear)
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

        let gameOver = SKLabelNode(fontNamed: Strings.Font.menloBold)
        gameOver.text = Strings.HUD.gameOver
        gameOver.fontSize = 56
        gameOver.fontColor = .systemRed
        gameOver.position = CGPoint(x: size.width / 2, y: size.height / 2 + 20)
        gameOver.zPosition = 102
        overlay.addChild(gameOver)

        let prompt = SKLabelNode(fontNamed: Strings.Font.menloBold)
        prompt.text = Strings.HUD.promptNewGame
        prompt.fontSize = 18
        prompt.fontColor = .systemYellow
        prompt.position = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
        prompt.zPosition = 102
        prompt.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])))
        overlay.addChild(prompt)

        let exit = SKLabelNode(fontNamed: Strings.Font.menloBold)
        exit.text = Strings.HUD.promptTitle
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
