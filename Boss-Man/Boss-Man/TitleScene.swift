import AppKit
import SpriteKit

final class TitleScene: SKScene {
    private static let highScoreKey = "Boss-Man.highScore"
    private static let titleFonts = [
        "Marker Felt Thin", "Marker Felt Wide"
    ]

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.34, alpha: 1)
        anchorPoint = CGPoint(x: 0, y: 0)

        let titleFont = TitleScene.titleFonts.first {
            NSFont(name: $0, size: 90) != nil
        } ?? "Helvetica-Bold"

        let titleFontBold = TitleScene.titleFonts.last {
            NSFont(name: $0, size: 90) != nil
        } ?? "Helvetica-Bold"
        
        let title = SKLabelNode(fontNamed: titleFontBold)
        title.text = "BOSS-MAN"
        title.fontSize = 108
        title.fontColor = .black
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.74)
        title.zRotation = -0.04
        addChild(title)

        let stapler = makeStapler()
        stapler.position = CGPoint(x: size.width / 2, y: size.height * 0.46)
        stapler.zRotation = -0.06
        addChild(stapler)

        let prompt = SKLabelNode(fontNamed: titleFont)
        prompt.text = "Press SPACE to Play"
        prompt.fontSize = 40
        prompt.fontColor = .black
        prompt.position = CGPoint(x: size.width / 2, y: size.height * 0.15)
        prompt.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.25, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])))
        addChild(prompt)

        let high = UserDefaults.standard.integer(forKey: TitleScene.highScoreKey)
        if high > 0 {
            let hs = SKLabelNode(fontNamed: titleFont)
            hs.text = "HIGH SCORE \(high)"
            hs.fontSize = 26
            hs.fontColor = .black
            hs.position = CGPoint(x: size.width / 2, y: size.height * 0.06)
            addChild(hs)
        }

        let panelSize = CGSize(width: 320, height: 400)
        let panel = LeaderboardPanel(
            size: panelSize,
            titleFont: titleFont,
            bodyFont: "Menlo-Bold"
        )
        panel.position = CGPoint(x: panelSize.width / 2 + 32, y: size.height * 0.5)
        addChild(panel)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // space
            let game = GameScene(size: size)
            game.scaleMode = .aspectFit
            view?.presentScene(game, transition: .fade(withDuration: 0.5))
        }
    }

    /// Loads the CC0 red-stapler SVG (Wikimedia Commons) bundled with the app.
    /// Falls back to a procedural drawing if the asset can't be loaded.
    private func makeStapler() -> SKNode {
        let targetSize = CGSize(width: 380, height: 290)
        if let url = Bundle.main.url(forResource: "RedStapler", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = targetSize
            let texture = SKTexture(image: image)
            let sprite = SKSpriteNode(texture: texture, size: targetSize)
            return sprite
        }
        return makeFallbackStapler()
    }

    private func makeFallbackStapler() -> SKNode {
        let stapler = SKNode()
        let base = SKShapeNode(rect: CGRect(x: -110, y: -22, width: 220, height: 16), cornerRadius: 4)
        base.fillColor = NSColor(calibratedRed: 0.55, green: 0.05, blue: 0.05, alpha: 1)
        base.strokeColor = NSColor(calibratedRed: 0.12, green: 0, blue: 0, alpha: 1)
        base.lineWidth = 1.5
        stapler.addChild(base)
        let arm = SKShapeNode(rect: CGRect(x: -100, y: -4, width: 220, height: 26), cornerRadius: 8)
        arm.fillColor = NSColor.systemRed
        arm.strokeColor = NSColor(calibratedRed: 0.12, green: 0, blue: 0, alpha: 1)
        arm.lineWidth = 1.5
        stapler.addChild(arm)
        let gloss = SKShapeNode(rect: CGRect(x: -90, y: 13, width: 195, height: 5), cornerRadius: 2)
        gloss.fillColor = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.78, alpha: 0.85)
        gloss.strokeColor = .clear
        stapler.addChild(gloss)
        return stapler
    }
}
