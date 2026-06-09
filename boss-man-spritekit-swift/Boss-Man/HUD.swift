import AppKit
import SpriteKit

final class HUD {
    static let startingLives = 3
    static let maxLives = 5
    static let panelHeight: CGFloat = 89.7

    private let root = SKNode()
    private let scoreLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let diceLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let tpsContainer = SKNode()
    private var tpsItemLabels: [SKLabelNode] = []
    private let reportsContainer = SKNode()
    private var reportBookLabels: [SKLabelNode] = []
    private let messageLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let levelEmojisContainer = SKNode()
    private let ammoContainer = SKNode()
    private var ammoDots: [SKLabelNode] = []
    private let gunLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let highScoreLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let dotsCounterLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let dotsBulletLabel = SKLabelNode(fontNamed: Strings.Font.menloBold)
    private let bottomTravelerContainer = SKNode()
    private let requiredItems: [String]
    private var lifeIcons: [PixelPerson] = []
    private var gameOverOverlay: SKNode?
    private var lastScoreText: String?
    private var lastLevelEmojisText: String?
    private var lastLivesCount: Int = -1
    private var lastWaterGunPellets: Int = -1
    private var lastWaterGunActive: Bool = false
    private var panelRowY: CGFloat = 0
    private var bottomRowY: CGFloat = 0
    private var showExtraRow = false
    private var lastHighScore: Int = -1
    private var lastDotsCounter: String?

    init(requiredItems: [String]) {
        self.requiredItems = requiredItems
    }

    func install(in parent: SKNode, size: CGSize, originOffset: CGPoint = .zero, extraRow: Bool = false) {
        let panelHeight = HUD.panelHeight
        let top = size.height
        let pad: CGFloat = 12
        showExtraRow = extraRow

        root.removeFromParent()
        root.removeAllChildren()
        root.position = originOffset
        root.zPosition = 80
        parent.addChild(root)

        // The panel border/background is only drawn in the camera modes (150%/200%),
        // at 100% (extraRow) the HUD floats borderless over the full board.
        if !extraRow {
            let panel = SKShapeNode(rect: CGRect(x: pad - 5, y: top - panelHeight - 8 - 3,
                                                 width: size.width - pad * 2 + 10, height: panelHeight + 6),
                                    cornerRadius: 8)
            panel.fillColor = NSColor(calibratedWhite: 0.02, alpha: 0.42)
            panel.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.10)
            panel.lineWidth = 1
            panel.zPosition = 0
            root.addChild(panel)
        }

        // 100% has no panel, so float the top row near the screen top and give it
        // room above the lower row, the camera modes keep the panel-centred row.
        let rowY = extraRow ? top - 38 : top - 8 - panelHeight / 2
        panelRowY = rowY

        diceLabel.text = "\u{1F3B2}"
        diceLabel.fontSize = 31.74
        diceLabel.horizontalAlignmentMode = .left
        diceLabel.verticalAlignmentMode = .center
        diceLabel.position = CGPoint(x: pad + 204, y: rowY - 1)
        diceLabel.zPosition = 1
        root.addChild(diceLabel)

        scoreLabel.fontSize = 31.74
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: pad + 243, y: rowY - 1)
        scoreLabel.zPosition = 1
        scoreLabel.fontColor = .white
        root.addChild(scoreLabel)

        tpsContainer.position = CGPoint(x: size.width / 2, y: rowY)
        tpsContainer.zPosition = 1
        tpsContainer.alpha = 1
        root.addChild(tpsContainer)

        tpsItemLabels.removeAll()
        let tpsSpacing: CGFloat = 56.13
        for (i, name) in requiredItems.enumerated() {
            let label = SKLabelNode(fontNamed: Strings.Font.menloBold)
            label.text = HUD.emojiByName[name] ?? name
            label.fontSize = 34.5
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: (CGFloat(i) - CGFloat(requiredItems.count - 1) / 2) * tpsSpacing, y: 0)
            label.alpha = 0.5
            tpsContainer.addChild(label)
            tpsItemLabels.append(label)
        }

        reportsContainer.position = CGPoint(x: size.width - pad - 14 - 280, y: rowY)
        reportsContainer.zPosition = 1
        root.addChild(reportsContainer)
        reportBookLabels.removeAll()
        let bookSpacing: CGFloat = 35
        let books = Strings.HUD.reportBooks
        for (i, book) in books.enumerated() {
            let b = SKLabelNode(fontNamed: Strings.Font.menloBold)
            b.text = book
            b.fontSize = 36.5
            b.horizontalAlignmentMode = .center
            b.verticalAlignmentMode = .center
            b.position = CGPoint(x: CGFloat(i - (books.count - 1)) * bookSpacing, y: 0)
            b.zPosition = 1
            reportBookLabels.append(b)
            reportsContainer.addChild(b)
        }

        lifeIcons.removeAll()
        lastLivesCount = -1
        lastScoreText = nil
        lastLevelEmojisText = nil
        lastWaterGunPellets = -1
        lastWaterGunActive = false
        lastHighScore = -1
        lastDotsCounter = nil

        let lifeStartX: CGFloat = pad + 27.05
        let lifeSpacing: CGFloat = 37
        for i in 0..<HUD.maxLives {
            let icon = SpriteFactory.petePerson()
            icon.setScale(1.049)
            icon.position = CGPoint(x: lifeStartX + CGFloat(i) * lifeSpacing, y: rowY + 1)
            icon.zPosition = 1
            root.addChild(icon)
            lifeIcons.append(icon)
        }

        ammoContainer.position = CGPoint(x: size.width - pad - 14 - 370, y: rowY)
        ammoContainer.zPosition = 1
        ammoContainer.isHidden = true
        root.addChild(ammoContainer)
        ammoDots.removeAll()
        let ammoDotSpacing: CGFloat = 19
        for i in 0..<8 {
            let d = SKLabelNode(fontNamed: Strings.Font.menloBold)
            d.fontSize = 28.87
            d.horizontalAlignmentMode = .center
            d.verticalAlignmentMode = .center
            d.position = CGPoint(x: CGFloat(i - 7) * ammoDotSpacing, y: 0)
            d.fontColor = .systemBlue
            ammoContainer.addChild(d)
            ammoDots.append(d)
        }

        gunLabel.text = Strings.Emoji.waterGun
        gunLabel.fontSize = 36.5
        gunLabel.horizontalAlignmentMode = .right
        gunLabel.verticalAlignmentMode = .center
        gunLabel.position = ammoContainer.position
        gunLabel.zPosition = 1
        gunLabel.isHidden = true
        root.addChild(gunLabel)

        messageLabel.fontName = Strings.Font.markerFeltWide
        messageLabel.fontSize = 25.72
        messageLabel.horizontalAlignmentMode = .center
        messageLabel.verticalAlignmentMode = .center
        messageLabel.position = CGPoint(x: size.width / 2, y: rowY)
        messageLabel.zPosition = 100
        messageLabel.fontColor = .white
        messageLabel.alpha = 0
        root.addChild(messageLabel)

        levelEmojisContainer.position = CGPoint(x: size.width - pad - 24.15, y: rowY)
        levelEmojisContainer.zPosition = 1
        root.addChild(levelEmojisContainer)

        if extraRow {
            let bottomY = top - 98
            bottomRowY = bottomY

            highScoreLabel.fontSize = 24.84
            highScoreLabel.horizontalAlignmentMode = .left
            highScoreLabel.verticalAlignmentMode = .center
            highScoreLabel.position = CGPoint(x: lifeStartX - 13.8, y: bottomY)
            highScoreLabel.zPosition = 1
            highScoreLabel.fontColor = .white
            root.addChild(highScoreLabel)

            dotsCounterLabel.fontSize = 24.84
            dotsCounterLabel.horizontalAlignmentMode = .center
            dotsCounterLabel.verticalAlignmentMode = .center
            dotsCounterLabel.position = CGPoint(x: size.width / 2 + 3.4, y: bottomY)
            dotsCounterLabel.zPosition = 1
            dotsCounterLabel.fontColor = .white
            root.addChild(dotsCounterLabel)

            dotsBulletLabel.text = "\u{25CF}"
            dotsBulletLabel.fontSize = 19.32
            dotsBulletLabel.horizontalAlignmentMode = .right
            dotsBulletLabel.verticalAlignmentMode = .center
            dotsBulletLabel.position = CGPoint(x: size.width / 2 - 77.28, y: bottomY)
            dotsBulletLabel.zPosition = 1
            dotsBulletLabel.fontColor = .systemYellow
            root.addChild(dotsBulletLabel)

            bottomTravelerContainer.position = CGPoint(x: size.width - pad - 19.32, y: bottomY)
            bottomTravelerContainer.zPosition = 1
            root.addChild(bottomTravelerContainer)
        }
    }

    // ASCII-only uppercase over UTF-8 bytes, String.uppercased()/.unicodeScalars
    // pull stdlib Unicode machinery, and multibyte UTF-8 is never in the a-z range.
    private static func allCaps(_ s: String) -> String {
        var b = Array(s.utf8)
        for i in b.indices where b[i] >= 97 && b[i] <= 122 { b[i] &-= 32 }
        return String(decoding: b, as: UTF8.self)
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
        for (i, name) in requiredItems.enumerated() where i < tpsItemLabels.count {
            tpsItemLabels[i].alpha = items.contains(name) ? 1.0 : 0.4
        }
        let shown = reports <= 0 ? 0 : (reports - 1) % reportBookLabels.count + 1
        for (i, b) in reportBookLabels.enumerated() {
            b.isHidden = i >= shown
        }
        if showExtraRow {
            if highScore != lastHighScore {
                highScoreLabel.text = "\u{1F48E} \(highScore)"
                lastHighScore = highScore
            }
            let totalStr = "\(total)"
            var paddedDots = "\(dots)"
            while paddedDots.count < totalStr.count { paddedDots = "0" + paddedDots }
            let dc = paddedDots
            if dc != lastDotsCounter {
                dotsCounterLabel.text = dc
                lastDotsCounter = dc
                let charW = dotsCounterLabel.fontSize * 0.62
                let halfW = CGFloat(dc.count) * charW / 2
                dotsBulletLabel.position = CGPoint(x: dotsCounterLabel.position.x - halfW - 9.66,
                                                   y: dotsCounterLabel.position.y)
            }
        }
    }

    func updateLevelEmojis(_ travelers: [LevelTraveler]) {
        let key = travelers.map { $0.image ?? $0.emoji }.joined(separator: ",")
        if key == lastLevelEmojisText { return }
        lastLevelEmojisText = key

        levelEmojisContainer.removeAllChildren()
        let pointSize: CGFloat = 45.18
        let spacing:   CGFloat = 50.2
        if let current = travelers.last {
            let glyph = TravelerGlyph.makeNode(for: current, pointSize: pointSize)
            let xOffset: CGFloat = current.image != nil ? -1.5 : 0
            let yOffset: CGFloat = current.image != nil ? -2   : 0
            glyph.position = CGPoint(x: xOffset, y: yOffset)
            if current.image != nil {
                glyph.xScale = -0.8
                glyph.yScale = 0.8
            }
            levelEmojisContainer.addChild(glyph)
        }
        let gap: CGFloat = 9
        let booksReserve: CGFloat = 4 * 41.07
        let groupShift: CGFloat = -8
        let gunWidth: CGFloat = 41.07
        let indicatorLeft = levelEmojisContainer.position.x - spacing / 2
        let booksRight = indicatorLeft - gap
        reportsContainer.position = CGPoint(x: booksRight - 15.5, y: panelRowY)
        let gunNaturalRight = booksRight - booksReserve - gap - groupShift
        gunLabel.position = CGPoint(x: gunNaturalRight + 13, y: panelRowY)
        ammoContainer.position = CGPoint(x: gunNaturalRight - gunWidth + 2, y: panelRowY - 4)

        if showExtraRow {
            bottomTravelerContainer.removeAllChildren()
            let bottomPointSize: CGFloat = 35.88
            let bottomSpacing:   CGFloat = 41.4
            // Newest traveler on the left, the first (fish) on the right: index 0
            // hugs the right edge and later levels grow leftward.
            for (i, t) in travelers.enumerated() {
                let glyph = TravelerGlyph.makeNode(for: t, pointSize: bottomPointSize)
                let xOffset: CGFloat = t.image != nil ? -2 : 0
                let yOffset: CGFloat = t.image != nil ? -2.5 : 0
                glyph.position = CGPoint(x: -CGFloat(i) * bottomSpacing + xOffset, y: yOffset)
                if t.image != nil {
                    glyph.xScale = -0.8
                    glyph.yScale = 0.8
                }
                bottomTravelerContainer.addChild(glyph)
            }
        }
    }

    func updateLives(_ count: Int) {
        if count == lastLivesCount { return }
        lastLivesCount = count
        for (i, icon) in lifeIcons.enumerated() {
            icon.isHidden = i >= count
        }
    }

    func updateWaterGun(active: Bool, pellets: Int) {
        if active == lastWaterGunActive && pellets == lastWaterGunPellets { return }
        lastWaterGunActive = active
        lastWaterGunPellets = pellets
        let neverPickedUp = !active && pellets < 0
        ammoContainer.isHidden = neverPickedUp
        gunLabel.isHidden = neverPickedUp
        guard !neverPickedUp else { return }
        let empty = !active || pellets == 0
        let color: NSColor = empty ? .systemRed : .systemBlue
        for (i, d) in ammoDots.enumerated() {
            d.text = i < pellets ? "\u{25CF}" : "\u{25CB}"
            d.fontColor = color
        }
    }

    func showMessage(_ text: String, duration: TimeInterval) {
        messageLabel.text = HUD.allCaps(text)
        messageLabel.fontSize = 25.72
        let fade: TimeInterval = 0.3
        tpsContainer.removeAction(forKey: Strings.ActionKey.hudSwap)
        tpsContainer.run(.sequence([
            .fadeOut(withDuration: fade),
            .wait(forDuration: duration),
            .fadeIn(withDuration: fade)
        ]), withKey: Strings.ActionKey.hudSwap)
        for n in [scoreLabel, diceLabel, ammoContainer, gunLabel] {
            n.removeAction(forKey: Strings.ActionKey.hudSwap)
            n.run(.sequence([
                .fadeAlpha(to: 0.33, duration: fade),
                .wait(forDuration: duration),
                .fadeAlpha(to: 1.0, duration: fade)
            ]), withKey: Strings.ActionKey.hudSwap)
        }
        messageLabel.removeAction(forKey: Strings.ActionKey.hudSwap)
        messageLabel.run(.sequence([
            .fadeIn(withDuration: fade),
            .wait(forDuration: duration),
            .fadeOut(withDuration: fade)
        ]), withKey: Strings.ActionKey.hudSwap)
    }

    func showPaused(_ paused: Bool) {
        for n in [tpsContainer, messageLabel, scoreLabel, diceLabel, ammoContainer, gunLabel] {
            n.removeAction(forKey: Strings.ActionKey.hudSwap)
        }
        if paused {
            messageLabel.text = HUD.allCaps(Strings.HUD.paused)
            messageLabel.fontSize = 30
            messageLabel.alpha = 1
            tpsContainer.alpha = 0
            scoreLabel.alpha = 0.33
            diceLabel.alpha = 0.33
            ammoContainer.alpha = 0.33
            gunLabel.alpha = 0.33
        } else {
            messageLabel.alpha = 0
            tpsContainer.alpha = 1
            scoreLabel.alpha = 1
            diceLabel.alpha = 1
            ammoContainer.alpha = 1
            gunLabel.alpha = 1
        }
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

