import AppKit
import SpriteKit

final class TitleScene: SKScene {
    private static let highScoreKey = Strings.DefaultsKey.highScore
    private static let titleFonts = [
        Strings.Font.markerFeltThin, Strings.Font.markerFeltWide
    ]

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.34, alpha: 1)
        anchorPoint = CGPoint(x: 0, y: 0)

        let titleFont = TitleScene.titleFonts.first {
            NSFont(name: $0, size: 90) != nil
        } ?? Strings.Font.helveticaBold

        let titleFontBold = TitleScene.titleFonts.last {
            NSFont(name: $0, size: 90) != nil
        } ?? Strings.Font.helveticaBold
        
        let title = SKLabelNode(fontNamed: titleFontBold)
        title.text = Strings.Title.gameTitle
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
        prompt.text = Strings.Title.pressSpace
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
            hs.text = Strings.Title.highScore(high)
            hs.fontSize = 26
            hs.fontColor = .black
            hs.position = CGPoint(x: size.width / 2, y: size.height * 0.06 + 15)
            addChild(hs)
        }

        let panelSize = CGSize(width: 320, height: 400)
        let panel = LeaderboardPanel(
            size: panelSize,
            titleFont: titleFont,
            bodyFont: Strings.Font.menloBold
        )
        panel.position = CGPoint(x: panelSize.width / 2 + 32, y: size.height * 0.5)
        addChild(panel)

        // Bottom-row hints: controls reminder on the left/center, fullscreen
        // shortcut on the right. JetBrains Mono Bold at 16pt matches the
        // SuperBox64 / C++ build's TitleScreen so all three editions agree.
        let hintFont = NSFont(name: Strings.Font.menloBold, size: 16) != nil
            ? Strings.Font.menloBold
            : Strings.Font.helveticaBold

        let controlsHint = SKLabelNode(fontNamed: hintFont)
        controlsHint.text = "Cursor key to Move \u{00B7} Space to Fire Water Pistol"
        controlsHint.fontSize = 16
        controlsHint.fontColor = .black
        controlsHint.horizontalAlignmentMode = .center
        controlsHint.position = CGPoint(x: size.width / 2, y: 18)
        addChild(controlsHint)

        let fullscreenHint = SKLabelNode(fontNamed: hintFont)
        fullscreenHint.text = "F for Fullscreen"
        fullscreenHint.fontSize = 16
        fullscreenHint.fontColor = .black
        fullscreenHint.horizontalAlignmentMode = .right
        fullscreenHint.position = CGPoint(x: size.width - 20, y: 18)
        addChild(fullscreenHint)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 35:
            let game = GameScene(size: size)
            game.scaleMode = .aspectFit
            view?.presentScene(game, transition: .fade(withDuration: 0.5))
        case 53:
            NSApp.terminate(nil)
        case 14:
            let editor = LevelEditorScene(size: size)
            editor.scaleMode = .aspectFit
            view?.presentScene(editor, transition: .fade(withDuration: 0.3))
        default:
            break
        }
    }

    private func makeStapler() -> SKNode {
        let maxSize = CGSize(width: 380, height: 290)
        if let url = Bundle.main.url(forResource: Strings.Resource.redStaplerFile,
                                      withExtension: Strings.Resource.redStaplerExtension),
           let image = NSImage(contentsOf: url) {
            let source = image.size
            let scale = min(maxSize.width / source.width,
                            maxSize.height / source.height)
            let fitted = CGSize(width: source.width  * scale,
                                height: source.height * scale)
            let texture = SKTexture(image: image)
            let sprite = SKSpriteNode(texture: texture, size: fitted)
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
