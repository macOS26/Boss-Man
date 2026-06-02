import AppKit
import SpriteKit

@MainActor
final class HUD {
    static let startingLives = 3
    static let maxLives = 5
    static let panelHeight: CGFloat = 52

    private let root = SKNode()
    private let scoreLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let tpsLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let progressLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let reportsLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let messageLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let levelEmojisContainer = SKNode()
    private let waterGunAmmoLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let requiredItems: [String]
    private var lifeIcons: [PixelPerson] = []
    private var gameOverOverlay: SKNode?
    private var lastScoreText: String?
    private var lastTpsText: String?
    private var lastProgressText: String?
    private var lastReportsText: String?
    private var lastLevelEmojisText: String?
    private var lastLivesCount: Int = -1
    private var lastWaterGunPellets: Int = -1
    private var lastWaterGunActive: Bool = false
    private var lastWaterGunBlueMode: Bool = false

    init(requiredItems: [String]) {
        self.requiredItems = requiredItems
    }

    func install(in parent: SKNode, size: CGSize, originOffset: CGPoint = .zero) {
        let panelHeight = HUD.panelHeight
        let top = size.height
        let pad: CGFloat = 12

        root.removeFromParent()
        root.removeAllChildren()
        root.position = originOffset
        root.zPosition = 80
        parent.addChild(root)

        let panel = SKShapeNode(rect: CGRect(x: pad, y: top - panelHeight - 8,
                                             width: size.width - pad * 2, height: panelHeight),
                                cornerRadius: 8)
        panel.fillColor = NSColor(calibratedWhite: 0.02, alpha: 0.42)
        panel.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.10)
        panel.lineWidth = 1
        panel.zPosition = 0
        root.addChild(panel)

        let rowY = top - 8 - panelHeight / 2

        scoreLabel.fontSize = 16
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: pad + 150, y: rowY)
        scoreLabel.zPosition = 1
        scoreLabel.fontColor = .white
        root.addChild(scoreLabel)

        tpsLabel.fontSize = 16
        tpsLabel.horizontalAlignmentMode = .center
        tpsLabel.verticalAlignmentMode = .center
        tpsLabel.position = CGPoint(x: size.width / 2, y: rowY)
        tpsLabel.zPosition = 1
        tpsLabel.fontColor = .white
        root.addChild(tpsLabel)

        progressLabel.fontSize = 16
        progressLabel.horizontalAlignmentMode = .center
        progressLabel.verticalAlignmentMode = .center
        progressLabel.position = CGPoint(x: size.width / 2, y: rowY)
        progressLabel.zPosition = 2
        progressLabel.fontColor = .white
        progressLabel.alpha = 0
        root.addChild(progressLabel)

        let hold: TimeInterval = 2.6
        let fade: TimeInterval = 0.5
        tpsLabel.alpha = 1
        tpsLabel.run(.repeatForever(.sequence([
            .wait(forDuration: hold), .fadeOut(withDuration: fade),
            .wait(forDuration: hold), .fadeIn(withDuration: fade)
        ])), withKey: Strings.ActionKey.hudSwap)
        progressLabel.run(.repeatForever(.sequence([
            .wait(forDuration: hold), .fadeIn(withDuration: fade),
            .wait(forDuration: hold), .fadeOut(withDuration: fade)
        ])), withKey: Strings.ActionKey.hudSwap)

        reportsLabel.fontSize = 16
        reportsLabel.horizontalAlignmentMode = .right
        reportsLabel.verticalAlignmentMode = .center
        reportsLabel.position = CGPoint(x: size.width - pad - 14 - 270, y: rowY)
        reportsLabel.zPosition = 1
        reportsLabel.fontColor = .systemYellow
        root.addChild(reportsLabel)

        lifeIcons.removeAll()
        lastLivesCount = -1
        lastScoreText = nil
        lastTpsText = nil
        lastReportsText = nil
        lastLevelEmojisText = nil
        lastWaterGunPellets = -1
        lastWaterGunActive = false
        lastWaterGunBlueMode = false

        let lifeStartX: CGFloat = pad + 18
        let lifeSpacing: CGFloat = 26
        for i in 0..<HUD.maxLives {
            let icon = SpriteFactory.petePerson()
            icon.setScale(0.529)
            icon.position = CGPoint(x: lifeStartX + CGFloat(i) * lifeSpacing, y: rowY)
            icon.zPosition = 1
            root.addChild(icon)
            lifeIcons.append(icon)
        }

        waterGunAmmoLabel.fontSize = 11
        waterGunAmmoLabel.horizontalAlignmentMode = .right
        waterGunAmmoLabel.verticalAlignmentMode = .center
        waterGunAmmoLabel.position = CGPoint(x: size.width - pad - 14, y: top - 8 - panelHeight - 12)
        waterGunAmmoLabel.zPosition = 1
        waterGunAmmoLabel.fontColor = .systemBlue
        waterGunAmmoLabel.isHidden = true
        root.addChild(waterGunAmmoLabel)

        messageLabel.fontSize = 15
        messageLabel.horizontalAlignmentMode = .center
        messageLabel.verticalAlignmentMode = .center
        messageLabel.position = CGPoint(x: size.width / 2, y: top - 8 - panelHeight - 16)
        messageLabel.zPosition = 1
        messageLabel.fontColor = .systemYellow
        root.addChild(messageLabel)

        levelEmojisContainer.position = CGPoint(x: size.width - pad - 14, y: rowY)
        levelEmojisContainer.zPosition = 1
        root.addChild(levelEmojisContainer)
    }

    private static let emojiByName: [String: String] = [
        Strings.Machine.printer:    Strings.Emoji.printer,
        Strings.Machine.fax:        Strings.Emoji.fax,
        Strings.Machine.coverSheet: Strings.Emoji.coverSheet,
        Strings.Machine.bookBinder: Strings.Emoji.bookBinder
    ]

    func updateStatus(score: Int, highScore: Int, level: Int, dots: Int, total: Int, reports: Int, items: Set<String>) {
        let scoreText = Strings.HUD.compactScore(score)
        if scoreText != lastScoreText {
            scoreLabel.text = scoreText
            lastScoreText = scoreText
        }
        let parts = requiredItems
            .map { name -> String in
                let icon = HUD.emojiByName[name] ?? name
                return items.contains(name) ? icon : "\(icon)\(Strings.Emoji.unchecked)"
            }
            .joined(separator: Strings.HUD.tpsItemSeparator)
        if parts != lastTpsText {
            tpsLabel.text = parts
            lastTpsText = parts
        }
        let reportsText = Strings.HUD.compactReports(reports)
        if reportsText != lastReportsText {
            reportsLabel.text = reportsText
            lastReportsText = reportsText
        }
        let progressText = Strings.HUD.compactDots(dots, total)
        if progressText != lastProgressText {
            progressLabel.text = progressText
            lastProgressText = progressText
        }
    }

    func updateLevelEmojis(_ travelers: [LevelTraveler]) {
        let key = travelers.map { $0.image ?? $0.emoji }.joined(separator: ",")
        if key == lastLevelEmojisText { return }
        lastLevelEmojisText = key

        levelEmojisContainer.removeAllChildren()
        let pointSize: CGFloat = 16
        let spacing:   CGFloat = 22
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

    func updateWaterGun(active: Bool, pellets: Int, blueMode: Bool = false) {
        if active == lastWaterGunActive && pellets == lastWaterGunPellets && blueMode == lastWaterGunBlueMode { return }
        lastWaterGunActive = active
        lastWaterGunPellets = pellets
        lastWaterGunBlueMode = blueMode
        let neverPickedUp = !active && pellets < 0
        waterGunAmmoLabel.isHidden = neverPickedUp
        guard !neverPickedUp else { return }
        let dots = (0..<8).map { $0 < pellets ? "\u{25CF}" : "\u{25CB}" }.joined()
        waterGunAmmoLabel.text = "\(Strings.Emoji.waterGun)\(dots)"
        let empty = !active || pellets == 0
        if blueMode {
            waterGunAmmoLabel.fontColor = NSColor.systemBlue.withAlphaComponent(0.5)
        } else {
            waterGunAmmoLabel.fontColor = empty ? .systemRed : .systemBlue
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
