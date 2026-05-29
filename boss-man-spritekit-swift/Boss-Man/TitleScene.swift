import AppKit
import SpriteKit

final class TitleScene: SKScene {
    private static let highScoreKey = Strings.DefaultsKey.highScore
    private static let titleFonts = [
        Strings.Font.markerFeltThin, Strings.Font.markerFeltWide
    ]

    private var hintFont = Strings.Font.menloBold
    private var playButtonRect = CGRect.zero
    private var editorButtonRect = CGRect.zero
    private var bossTracksLabel: SKLabelNode?
    private var waterGunLabel: SKLabelNode?
    private var fullscreenLabel: SKLabelNode?
    private var escWindowLabel: SKLabelNode?

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
        stapler.position = CGPoint(x: size.width / 2, y: size.height * 0.46 + 8)
        stapler.zRotation = -0.06
        addChild(stapler)

        // Two title buttons: green "(P)lay" and blue "(E)ditor", white text on a
        // filled rect, centred as a pair. Click/tap either, or press P / E.
        let promptY = size.height * 0.15 + 20
        let green = NSColor(calibratedRed: 0.0,  green: 0.55, blue: 0.18, alpha: 1)
        let blue  = NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.85, alpha: 1)
        let bw: CGFloat = 180, bh: CGFloat = 52, gap: CGFloat = 28
        playButtonRect = makeTitleButton(
            text: "(P)lay", color: green, font: titleFont,
            center: CGPoint(x: size.width / 2 - bw / 2 - gap / 2, y: promptY),
            size: CGSize(width: bw, height: bh))
        editorButtonRect = makeTitleButton(
            text: "(E)ditor", color: blue, font: titleFont,
            center: CGPoint(x: size.width / 2 + bw / 2 + gap / 2, y: promptY),
            size: CGSize(width: bw, height: bh))

        let high = UserDefaults.standard.integer(forKey: TitleScene.highScoreKey)
        if high > 0 {
            let hs = SKLabelNode(fontNamed: titleFont)
            hs.text = Strings.Title.highScore(high)
            hs.fontSize = 26
            hs.fontColor = .black
            hs.position = CGPoint(x: size.width / 2, y: size.height * 0.06 + 10)
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

        // Bottom-row hints + the bottom-right toggle column. JetBrains Mono Bold
        // at 16pt keeps all three editions (apple / C++ / wasm) in agreement.
        hintFont = NSFont(name: Strings.Font.menloBold, size: 16) != nil
            ? Strings.Font.menloBold
            : Strings.Font.helveticaBold

        let controlsHint = SKLabelNode(fontNamed: hintFont)
        controlsHint.text = "Cursor key to Move \u{00B7} Space to Fire Water Pistol"
        controlsHint.fontSize = 16
        controlsHint.fontColor = .black
        controlsHint.horizontalAlignmentMode = .center
        controlsHint.position = CGPoint(x: size.width / 2, y: 18)
        addChild(controlsHint)

        // Bottom-right column, 51px apart, anchored at "F for Fullscreen" (y=18).
        let fs = makeHint("F for Fullscreen", y: 18); fullscreenLabel = fs
        let esc = makeHint("ESC for Window", y: 69); escWindowLabel = esc
        let tracks = makeHint(bossTracksText(), y: 120); bossTracksLabel = tracks
        let wg = makeHint(waterGunText(), y: 171); waterGunLabel = wg
    }

    // MARK: - Settings text

    private func bossTracksText() -> String {
        "Boss Tracks: \(isSquareTracks() ? "Square" : "Smooth")"
    }
    private func waterGunText() -> String {
        "Water Gun: \(UserDefaults.standard.bool(forKey: Strings.DefaultsKey.waterGunLeft) ? "Left" : "Right")"
    }
    private func isSquareTracks() -> Bool {
        (UserDefaults.standard.object(forKey: Strings.DefaultsKey.bossTracksSquare) as? Bool) ?? true
    }

    // MARK: - Builders

    @discardableResult
    private func makeTitleButton(text: String, color: NSColor, font: String,
                                 center: CGPoint, size s: CGSize) -> CGRect {
        let bg = SKShapeNode(rect: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height),
                             cornerRadius: 0)
        bg.position = center
        bg.fillColor = color
        bg.strokeColor = .clear
        bg.zPosition = 5
        addChild(bg)
        let label = SKLabelNode(fontNamed: font)
        label.text = text
        label.fontSize = 34
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 6
        bg.addChild(label)
        return CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height)
    }

    private func makeHint(_ text: String, y: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: hintFont)
        label.text = text
        label.fontSize = 16
        label.fontColor = .black
        label.horizontalAlignmentMode = .right
        label.position = CGPoint(x: size.width - 20, y: y)
        addChild(label)
        return label
    }

    // MARK: - Input

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 35, 49:  startGame()        // P or Space
        case 14:      startEditor()      // E
        case 3:       enterFullscreen()  // F
        case 53:      exitToWindow()     // Esc -> windowed (the title hint says "ESC for Window")
        default:      break
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        if playButtonRect.contains(p)   { startGame();   return }
        if editorButtonRect.contains(p) { startEditor(); return }
        if let fs = fullscreenLabel, labelHit(fs, p)  { enterFullscreen(); return }
        if let esc = escWindowLabel, labelHit(esc, p)  { exitToWindow();   return }
        if let t = bossTracksLabel, labelHit(t, p) {
            let square = !isSquareTracks()
            UserDefaults.standard.set(square, forKey: Strings.DefaultsKey.bossTracksSquare)
            t.text = bossTracksText()
            return
        }
        if let wg = waterGunLabel, labelHit(wg, p) {
            let left = !UserDefaults.standard.bool(forKey: Strings.DefaultsKey.waterGunLeft)
            UserDefaults.standard.set(left, forKey: Strings.DefaultsKey.waterGunLeft)
            wg.text = waterGunText()
            return
        }
    }

    private func labelHit(_ label: SKLabelNode, _ p: CGPoint) -> Bool {
        label.frame.insetBy(dx: -12, dy: -10).contains(p)
    }

    private func startGame() {
        let game = GameScene(size: size)
        game.scaleMode = .aspectFit
        view?.presentScene(game, transition: .fade(withDuration: 0.5))
    }

    private func startEditor() {
        let editor = LevelEditorScene(size: size)
        editor.scaleMode = .aspectFit
        view?.presentScene(editor, transition: .fade(withDuration: 0.3))
    }

    private func enterFullscreen() {
        guard let w = view?.window, !w.styleMask.contains(.fullScreen) else { return }
        w.toggleFullScreen(nil)
    }
    private func exitToWindow() {
        guard let w = view?.window, w.styleMask.contains(.fullScreen) else { return }
        w.toggleFullScreen(nil)
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
