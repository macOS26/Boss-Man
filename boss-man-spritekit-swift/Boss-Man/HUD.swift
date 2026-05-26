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
    private let waterGunIconLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let waterGunAmmoLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let waterGunCropNode = SKCropNode()
    private let requiredItems: [String]
    private var lifeIcons: [PixelPerson] = []
    private var gameOverOverlay: SKNode?
    private var lastStatusText: String?
    private var lastTpsText: String?
    private var lastLevelEmojisText: String?
    private var lastLivesCount: Int = -1
    private var lastWaterGunPellets: Int = -1
    private var lastWaterGunActive: Bool = false
    private var lastWaterGunBlueMode: Bool = false

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

        statusLabel.fontSize = 19
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.verticalAlignmentMode = .center
        statusLabel.position = CGPoint(x: 16, y: size.height - 22)
        statusLabel.zPosition = 21
        statusLabel.fontColor = .white
        scene.addChild(statusLabel)

        tpsLabel.fontSize = 19
        tpsLabel.horizontalAlignmentMode = .left
        tpsLabel.verticalAlignmentMode = .center
        tpsLabel.position = CGPoint(x: 16, y: size.height - 52)
        tpsLabel.zPosition = 21
        tpsLabel.fontColor = .white
        scene.addChild(tpsLabel)

        livesLabel.fontSize = 19
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
        lastWaterGunPellets = -1
        lastWaterGunActive = false
        lastWaterGunBlueMode = false
        waterGunIconLabel.isHidden = true
        waterGunAmmoLabel.isHidden = true
        waterGunCropNode.isHidden = true
        let iconStartX: CGFloat = 90
        let iconSpacing: CGFloat = 24
        for i in 0..<HUD.maxLives {
            let icon = SpriteFactory.petePerson()
            icon.setScale(0.45)
            icon.position = CGPoint(x: iconStartX + CGFloat(i) * iconSpacing, y: size.height - 84)
            icon.zPosition = 21
            scene.addChild(icon)
            lifeIcons.append(icon)
        }

        messageLabel.fontSize = 19
        messageLabel.horizontalAlignmentMode = .right
        messageLabel.verticalAlignmentMode = .center
        messageLabel.position = CGPoint(x: size.width - 16, y: size.height - 52)
        messageLabel.zPosition = 21
        messageLabel.fontColor = .systemYellow
        scene.addChild(messageLabel)

        levelEmojisContainer.position = CGPoint(x: size.width - 25, y: size.height - 22)
        levelEmojisContainer.zPosition = 21
        scene.addChild(levelEmojisContainer)

        let iconPos = CGPoint(x: size.width - 14, y: size.height - 84)
        waterGunIconLabel.fontSize = 19
        waterGunIconLabel.horizontalAlignmentMode = .right
        waterGunIconLabel.verticalAlignmentMode = .center
        waterGunIconLabel.position = iconPos
        waterGunIconLabel.zPosition = 21
        waterGunIconLabel.fontColor = .systemBlue
        waterGunIconLabel.text = Strings.Emoji.waterGun
        waterGunIconLabel.isHidden = true
        scene.addChild(waterGunIconLabel)

        let maskLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
        maskLabel.fontSize = 19
        maskLabel.horizontalAlignmentMode = .right
        maskLabel.verticalAlignmentMode = .center
        maskLabel.text = Strings.Emoji.waterGun
        waterGunCropNode.maskNode = maskLabel

        let lf = waterGunIconLabel.frame
        let redFill = SKSpriteNode(color: NSColor.systemRed.withAlphaComponent(0.25),
                                   size: CGSize(width: max(lf.width, 16) + 8, height: max(lf.height, 14) + 8))
        redFill.position = CGPoint(x: lf.midX - iconPos.x, y: lf.midY - iconPos.y)
        waterGunCropNode.addChild(redFill)
        waterGunCropNode.position = iconPos
        waterGunCropNode.zPosition = 22
        waterGunCropNode.isHidden = true
        scene.addChild(waterGunCropNode)

        waterGunAmmoLabel.fontSize = 19
        waterGunAmmoLabel.horizontalAlignmentMode = .right
        waterGunAmmoLabel.verticalAlignmentMode = .center
        waterGunAmmoLabel.position = CGPoint(x: lf.minX - 6, y: size.height - 84)
        waterGunAmmoLabel.zPosition = 21
        waterGunAmmoLabel.fontColor = .systemBlue
        waterGunAmmoLabel.isHidden = true
        scene.addChild(waterGunAmmoLabel)
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

    func updateWaterGun(active: Bool, pellets: Int, blueMode: Bool = false) {
        if active == lastWaterGunActive && pellets == lastWaterGunPellets && blueMode == lastWaterGunBlueMode { return }
        lastWaterGunActive = active
        lastWaterGunPellets = pellets
        lastWaterGunBlueMode = blueMode
        let neverPickedUp = !active && pellets < 0
        waterGunIconLabel.isHidden = neverPickedUp
        waterGunAmmoLabel.isHidden = neverPickedUp
        waterGunCropNode.isHidden = neverPickedUp
        guard !neverPickedUp else { return }
        let ammoText = (0..<8).map { $0 < pellets ? "●" : "○" }.joined(separator: " ")
        waterGunAmmoLabel.text = ammoText
        let empty = !active || pellets == 0
        if blueMode {
            waterGunAmmoLabel.fontColor = NSColor.systemBlue.withAlphaComponent(0.5)
            waterGunIconLabel.alpha = 0.25
            waterGunCropNode.isHidden = true
        } else {
            waterGunAmmoLabel.fontColor = empty ? .systemRed : .systemBlue
            waterGunIconLabel.alpha = empty ? 0.5 : 1.0
            waterGunCropNode.isHidden = !empty
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
