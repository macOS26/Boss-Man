import SpriteKit

// HUD overlay for the maze. Matches bossman-apple's layout exactly:
//   Row 1 (y = h-22): Score: X   High: Y   Level: Z   Dots: D/T   Reports: R
//   Row 2 (y = h-52): TPS: <emoji checklist>            (right: flash messages)
//   Row 3 (y = h-84): Lives: <pete icons>               (right: water gun + ammo dots)
//
// A translucent dark panel (100px tall) backs the whole strip so labels
// never sit on top of cubicle walls.
final class HUD {
    static let panelHeight: CGFloat = 100
    static let maxLives = 5
    static let startingLives = 3

    private let statusLabel  = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let tpsLabel     = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let livesLabel   = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let messageLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let waterGunIcon = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let ammoDots     = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private var lifeIcons: [PixelPerson] = []
    // Container for the upcoming-traveler emoji trail at the top-right.
    private let levelEmojisContainer = SKNode()
    private var lastTravelerKey: String? = nil

    private weak var scene: SKScene?

    func install(in scene: SKScene) {
        self.scene = scene
        let size = scene.size

        let panel = SKShapeNode(rect: CGRect(x: 0, y: size.height - HUD.panelHeight,
                                             width: size.width, height: HUD.panelHeight))
        panel.fillColor = SKColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 0.92)
        panel.strokeColor = .clear
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
        tpsLabel.text = "TPS:"
        scene.addChild(tpsLabel)

        livesLabel.fontSize = 19
        livesLabel.horizontalAlignmentMode = .left
        livesLabel.verticalAlignmentMode = .center
        livesLabel.position = CGPoint(x: 16, y: size.height - 84)
        livesLabel.zPosition = 21
        livesLabel.fontColor = SKColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1) // systemGreen
        livesLabel.text = "Lives:"
        scene.addChild(livesLabel)

        let iconStartX: CGFloat = 90
        let iconSpacing: CGFloat = 24
        for i in 0..<HUD.maxLives {
            let icon = SpriteFactory.petePerson()
            icon.setScale(0.45)
            icon.position = CGPoint(x: iconStartX + CGFloat(i) * iconSpacing,
                                    y: size.height - 84)
            icon.zPosition = 21
            scene.addChild(icon)
            lifeIcons.append(icon)
        }

        levelEmojisContainer.position = CGPoint(x: size.width - 30, y: size.height - 22)
        levelEmojisContainer.zPosition = 21
        scene.addChild(levelEmojisContainer)

        messageLabel.fontSize = 19
        messageLabel.horizontalAlignmentMode = .right
        messageLabel.verticalAlignmentMode = .center
        messageLabel.position = CGPoint(x: size.width - 16, y: size.height - 52)
        messageLabel.zPosition = 21
        messageLabel.fontColor = SKColor(red: 1.0, green: 0.91, blue: 0.34, alpha: 1) // systemYellow
        scene.addChild(messageLabel)

        let iconX = size.width - 16
        waterGunIcon.fontSize = 19
        waterGunIcon.horizontalAlignmentMode = .right
        waterGunIcon.verticalAlignmentMode = .center
        waterGunIcon.position = CGPoint(x: iconX, y: size.height - 84)
        waterGunIcon.zPosition = 21
        waterGunIcon.fontColor = SKColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1) // systemBlue
        waterGunIcon.text = Strings.Emoji.waterGun
        waterGunIcon.alpha = 0.5
        scene.addChild(waterGunIcon)

        ammoDots.fontSize = 19
        ammoDots.horizontalAlignmentMode = .right
        ammoDots.verticalAlignmentMode = .center
        ammoDots.position = CGPoint(x: iconX - 28, y: size.height - 84)
        ammoDots.zPosition = 21
        ammoDots.fontColor = SKColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1) // systemRed
        ammoDots.text = (0..<8).map { _ in "\u{25CB}" }.joined(separator: " ")          // ○
        scene.addChild(ammoDots)
    }

    func update(score: Int, highScore: Int, level: Int, dotsLeft: Int, totalDots: Int, reports: Int = 0) {
        statusLabel.text = Strings.HUD.statusLine(
            score: score, highScore: highScore, level: level,
            dots: dotsLeft, total: totalDots, reports: reports)
    }

    func update(lives: Int) {
        for (i, icon) in lifeIcons.enumerated() { icon.isHidden = i >= lives }
    }

    // Render 8 ammo slots: ● for each remaining shot (capped at 8), ○ for the
    // rest. systemBlue when ammo > 0, systemRed at 0 (matching bossman-apple).
    func update(ammo: Int) {
        let shown = min(8, max(0, ammo))
        let text = (0..<8).map { $0 < shown ? "\u{25CF}" : "\u{25CB}" }.joined(separator: " ")
        ammoDots.text = text
        let blue = SKColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1)
        let red  = SKColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
        if ammo > 0 {
            ammoDots.fontColor = blue
            waterGunIcon.alpha = 1.0
        } else {
            ammoDots.fontColor = red
            waterGunIcon.alpha = 0.5
        }
    }

    // bossman-apple's TPS checklist row: "TPS: ✅🖨 ❌📠 ❌📄 ❌📚".
    // The four glyph slots correspond to printer/fax/coverSheet/binder
    // in Strings.Machine.required order.
    func updateTPSChecklist(collected: Set<String>) {
        let glyphs: [(name: String, emoji: String)] = [
            (Strings.Machine.printer,    Strings.Emoji.printer),
            (Strings.Machine.fax,        Strings.Emoji.fax),
            (Strings.Machine.coverSheet, Strings.Emoji.coverSheet),
            (Strings.Machine.bookBinder, Strings.Emoji.bookBinder),
        ]
        let parts = glyphs.map { item -> String in
            let check = collected.contains(item.name) ? Strings.Emoji.checked
                                                      : Strings.Emoji.unchecked
            return "\(check)\(item.emoji)"
        }
        tpsLabel.text = "\(Strings.HUD.tpsPrefix) " + parts.joined(separator: "  ")
    }

    // bossman-apple's HUD.showGameOver — translucent dim, orange-bordered
    // central card, big red GAME OVER + yellow prompt that pulses, and
    // a small "PRESS ESC FOR TITLE SCREEN" hint below. Returns the overlay
    // so GameScene can dismiss it after the timer.
    @discardableResult
    func showGameOver(in scene: SKScene) -> SKNode {
        let s = scene.size
        let overlay = SKNode()
        overlay.zPosition = 100

        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: s))
        dim.fillColor = SKColor(white: 0, alpha: 0.78)
        dim.strokeColor = .clear
        dim.zPosition = 100
        overlay.addChild(dim)

        let frame = SKShapeNode(rect: CGRect(x: s.width / 2 - 260,
                                              y: s.height / 2 - 110,
                                              width: 520, height: 220),
                                 cornerRadius: 6)
        frame.fillColor = SKColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        frame.strokeColor = SKColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1)
        frame.lineWidth = 3
        frame.zPosition = 101
        overlay.addChild(frame)

        let big = SKLabelNode(fontNamed: Strings.Font.menloBold)
        big.text = Strings.HUD.gameOver
        big.fontSize = 56
        big.fontColor = SKColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
        big.position = CGPoint(x: s.width / 2, y: s.height / 2 + 20)
        big.zPosition = 102
        overlay.addChild(big)

        let prompt = SKLabelNode(fontNamed: Strings.Font.menloBold)
        prompt.text = Strings.HUD.promptNewGame
        prompt.fontSize = 18
        prompt.fontColor = SKColor(red: 1.0, green: 0.91, blue: 0.34, alpha: 1)
        prompt.position = CGPoint(x: s.width / 2, y: s.height / 2 - 40)
        prompt.zPosition = 102
        prompt.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.2, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6),
        ])))
        overlay.addChild(prompt)

        let exit = SKLabelNode(fontNamed: Strings.Font.menloBold)
        exit.text = Strings.HUD.promptTitle
        exit.fontSize = 14
        exit.fontColor = SKColor(white: 0.75, alpha: 1)
        exit.position = CGPoint(x: s.width / 2, y: s.height / 2 - 72)
        exit.zPosition = 102
        overlay.addChild(exit)

        scene.addChild(overlay)
        return overlay
    }

    // Upcoming-traveler emoji trail in the top-right corner. Identical
    // layout to bossman-apple: right-to-left, ~26px spacing, with the
    // current level's traveler at the rightmost position. Pass an empty
    // array to clear.
    func update(travelers: [LevelTraveler]) {
        let key = travelers.map { $0.image ?? $0.emoji }.joined(separator: ",")
        if key == lastTravelerKey { return }
        lastTravelerKey = key
        levelEmojisContainer.removeAllChildren()
        let pointSize: CGFloat = 18
        let spacing:   CGFloat = 26
        let count = travelers.count
        for (i, t) in travelers.enumerated() {
            let node: SKNode
            if let imgName = t.image, let tex = textureNamed(imgName) {
                let sprite = SKSpriteNode(texture: tex)
                let s = tex.size
                let aspect = s.height > 0 ? s.width / s.height : 1
                sprite.size = CGSize(width: pointSize * aspect * 0.8, height: pointSize)
                node = sprite
            } else {
                let label = SKLabelNode(text: t.emoji)
                label.fontSize = pointSize
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = .center
                node = label
            }
            node.position = CGPoint(x: CGFloat(i - (count - 1)) * spacing, y: 0)
            levelEmojisContainer.addChild(node)
        }
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
