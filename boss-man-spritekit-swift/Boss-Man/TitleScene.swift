import SpriteKit
#if os(macOS)
import AppKit
#elseif os(WASI)
import KitABI
#endif

// Title screen, shared by both ports: BOSS-MAN wordmark tilted slightly, red
// stapler illustration, green "(P)lay" + blue "(E)ditor" buttons, high score,
// the leaderboard panel docked left, and a bottom-right toggle column. Layout +
// builders are common; the only platform branches are input (NSEvent vs the
// kit's keyCode/point callbacks), fullscreen, and loading the stapler image.
final class TitleScene: SKScene {
    private var playButtonRect = CGRect.zero
    private var editorButtonRect = CGRect.zero
    private var bossTracksLabel: SKLabelNode?
    private var waterGunLabel: SKLabelNode?
    private var fullscreenLabel: SKLabelNode?
    private var escWindowLabel: SKLabelNode?

    override func didMove(to view: SKView) {
        // The title is static, so render it at 1 fps: no animation, and it avoids
        // re-rasterizing the leaderboard blur every frame. Game/editor scenes
        // restore 60 fps on the way out (startGame / startEditor).
        view.preferredFramesPerSecond = 1
        backgroundColor = SKColor(calibratedRed: 1.0, green: 0.93, blue: 0.34, alpha: 1)
        anchorPoint = .zero

        let title = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
        title.text = Strings.Title.gameTitle
        title.fontSize = 108
        title.fontColor = .black
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.74)
        title.zRotation = -0.04
        title.zPosition = 10
        addChild(title)

        let credit = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
        credit.text = "Game Design by Todd Bruss"
        credit.fontSize = 24
        credit.fontColor = .black
        credit.position = CGPoint(x: size.width / 2, y: size.height * 0.95 - 15)
        credit.zPosition = 10
        addChild(credit)

        let stapler = makeStapler()
        stapler.position = CGPoint(x: size.width / 2, y: size.height * 0.46 + 8)
        stapler.zRotation = -0.06
        addChild(stapler)

        // Two title buttons: green "(P)lay" and blue "(E)ditor". Click/tap either
        // or press P / E.
        let promptY = size.height * 0.15 + 20
        let green = SKColor(calibratedRed: 0.0,  green: 0.55, blue: 0.18, alpha: 1)
        let blue  = SKColor(calibratedRed: 0.10, green: 0.35, blue: 0.85, alpha: 1)
        let bw: CGFloat = 180, bh: CGFloat = 52, gap: CGFloat = 28
        playButtonRect = makeTitleButton(
            text: Strings.Title.playGame, color: green,
            center: CGPoint(x: size.width / 2 - bw / 2 - gap / 2, y: promptY),
            size: CGSize(width: bw, height: bh), textDY: -2)
        editorButtonRect = makeTitleButton(
            text: Strings.Title.levelEditor, color: blue,
            center: CGPoint(x: size.width / 2 + bw / 2 + gap / 2, y: promptY),
            size: CGSize(width: bw, height: bh))

        let high = Persistence.int(forKey: Strings.DefaultsKey.highScore)
        if high > 0 {
            let hs = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
            hs.text = Strings.Title.highScore(high)
            hs.fontSize = 26
            hs.fontColor = .black
            hs.position = CGPoint(x: size.width / 2, y: size.height * 0.06 + 10)
            addChild(hs)
        }

        let panelSize = CGSize(width: 320, height: 400)
        let panel = LeaderboardPanel(
            size: panelSize,
            titleFont: Strings.Font.markerFeltThin,
            bodyFont: Strings.Font.menloBold
        )
        panel.position = CGPoint(x: panelSize.width / 2 + 32, y: size.height * 0.5 + 15)
        addChild(panel)

        let controlsHint = SKLabelNode(fontNamed: Strings.Font.menloBold)
        controlsHint.text = Strings.Title.controlsHint
        controlsHint.fontSize = 16
        controlsHint.fontColor = .black
        controlsHint.horizontalAlignmentMode = .center
        controlsHint.position = CGPoint(x: size.width / 2, y: 18)
        addChild(controlsHint)

        // Window controls hug the bottom-right corner; the gameplay toggles
        // (Water Gun / Boss Tracks) hug the bottom-left. 80px apart, big + tappable.
        fullscreenLabel = makeHint("F for Fullscreen", y: 18)
        escWindowLabel  = makeHint("ESC for Window", y: 98)
        bossTracksLabel = makeHint(bossTracksText(), y: 18, left: true)
        waterGunLabel   = makeHint(waterGunText(), y: 98, left: true)
    }

    // MARK: - Settings text
    private func bossTracksText() -> String {
        "Boss Tracks: \(isSquareTracks() ? "Square" : "Smooth")"
    }
    private func waterGunText() -> String {
        let mode: String
        if Persistence.bool(forKey: Strings.DefaultsKey.waterGunHide) {
            mode = "Hide"
        } else {
            mode = Persistence.bool(forKey: Strings.DefaultsKey.waterGunLeft) ? "Left" : "Right"
        }
        return "Water Gun: \(mode)"
    }

    // Cycle Left -> Right -> Hide -> Left (two bools: waterGunLeft + waterGunHide).
    private func cycleWaterGun() {
        if Persistence.bool(forKey: Strings.DefaultsKey.waterGunHide) {          // Hide -> Left
            Persistence.set(false, forKey: Strings.DefaultsKey.waterGunHide)
            Persistence.set(true,  forKey: Strings.DefaultsKey.waterGunLeft)
        } else if Persistence.bool(forKey: Strings.DefaultsKey.waterGunLeft) {   // Left -> Right
            Persistence.set(false, forKey: Strings.DefaultsKey.waterGunLeft)
        } else {                                                                 // Right -> Hide
            Persistence.set(true,  forKey: Strings.DefaultsKey.waterGunHide)
        }
    }
    private func isSquareTracks() -> Bool {
        Persistence.bool(forKey: Strings.DefaultsKey.bossTracksSquare, default: true)
    }

    // MARK: - Builders
    @discardableResult
    private func makeTitleButton(text: String, color: SKColor, center: CGPoint,
                                 size s: CGSize, textDY: CGFloat = 0) -> CGRect {
        let bg = SKShapeNode(rect: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height),
                             cornerRadius: 10)
        bg.position = center
        bg.fillColor = color
        bg.strokeColor = .clear
        bg.zPosition = 5
        addChild(bg)
        let label = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
        label.text = text
        label.fontSize = 34
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: textDY)
        label.zPosition = 6
        bg.addChild(label)
        return CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height)
    }

    private func makeHint(_ text: String, y: CGFloat, left: Bool = false) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: Strings.Font.menloBold)
        label.text = text
        label.fontSize = 25
        label.fontColor = .black
        label.horizontalAlignmentMode = left ? .left : .right
        label.position = CGPoint(x: left ? 20 : size.width - 20, y: y)
        addChild(label)
        return label
    }

    // MARK: - Actions (shared)
    private func startGame() {
        view?.preferredFramesPerSecond = 60
        let game = GameScene(size: size)
        game.scaleMode = .aspectFit
        view?.presentScene(game, transition: .fade(withDuration: 0.5))
    }

    private func startEditor() {
        view?.preferredFramesPerSecond = 30
        let editor = LevelEditorScene(size: size)
        editor.scaleMode = .aspectFit
        view?.presentScene(editor, transition: .fade(withDuration: 0.3))
    }

    private func enterFullscreen() {
        #if os(macOS)
        guard let w = view?.window, !w.styleMask.contains(.fullScreen) else { return }
        w.toggleFullScreen(nil)
        #elseif os(WASI)
        win_request_fullscreen()
        #endif
    }
    private func exitToWindow() {
        #if os(macOS)
        guard let w = view?.window, w.styleMask.contains(.fullScreen) else { return }
        w.toggleFullScreen(nil)
        #elseif os(WASI)
        win_exit_fullscreen()
        #endif
    }

    // Shared tap routing — both ports funnel their pointer event through here.
    private func handleTap(at p: CGPoint) {
        if playButtonRect.contains(p)   { startGame();   return }
        if editorButtonRect.contains(p) { startEditor(); return }
        if let fs = fullscreenLabel, labelHit(fs, p) { enterFullscreen(); return }
        if let esc = escWindowLabel, labelHit(esc, p) { exitToWindow();   return }
        if let t = bossTracksLabel, labelHit(t, p) {
            Persistence.set(!isSquareTracks(), forKey: Strings.DefaultsKey.bossTracksSquare)
            t.text = bossTracksText()
            return
        }
        if let wg = waterGunLabel, labelHit(wg, p) {
            cycleWaterGun()
            wg.text = waterGunText()
            return
        }
    }

    private func labelHit(_ label: SKLabelNode, _ p: CGPoint) -> Bool {
        label.frame.insetBy(dx: -12, dy: -10).contains(p)
    }

    // MARK: - Input (platform event shapes funnel into the shared actions)
    #if os(macOS)
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 35, 49: startGame()        // P or Space
        case 14:     startEditor()      // E
        case 3:      enterFullscreen()  // F
        case 53:     exitToWindow()     // Esc -> windowed
        default:     break
        }
    }
    override func mouseDown(with event: NSEvent) { handleTap(at: event.location(in: self)) }
    #elseif os(WASI)
    override func keyDown(_ key: Int) {
        switch key {
        case 15:     startGame()              // P
        case 4:      startEditor()            // E
        case 5:      enterFullscreen()        // F
        case 36:     exitToWindow()           // Esc
        case 57:     startGame()              // Space (gamepad A maps here)
        default:     break
        }
    }
    override func mouseDown(at p: CGPoint) { handleTap(at: p) }
    #endif

    // MARK: - Stapler
    private func makeStapler() -> SKNode {
        let maxSize = CGSize(width: 380, height: 290)
        #if os(macOS)
        if let url = Bundle.main.url(forResource: Strings.Resource.redStaplerFile,
                                      withExtension: Strings.Resource.redStaplerExtension),
           let image = NSImage(contentsOf: url) {
            let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height)
            let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            return SKSpriteNode(texture: SKTexture(image: image), size: fitted)
        }
        #elseif os(WASI)
        if let tex = textureNamed(Strings.Resource.redStaplerFile) {
            let scale = min(maxSize.width / tex.size.width, maxSize.height / tex.size.height)
            let fitted = CGSize(width: tex.size.width * scale, height: tex.size.height * scale)
            return SKSpriteNode(texture: tex, size: fitted)
        }
        #endif
        return makeFallbackStapler()
    }

    private func makeFallbackStapler() -> SKNode {
        let stapler = SKNode()
        let base = SKShapeNode(rect: CGRect(x: -110, y: -22, width: 220, height: 16), cornerRadius: 4)
        base.fillColor = SKColor(calibratedRed: 0.55, green: 0.05, blue: 0.05, alpha: 1)
        base.strokeColor = SKColor(calibratedRed: 0.12, green: 0, blue: 0, alpha: 1)
        base.lineWidth = 1.5
        stapler.addChild(base)
        let arm = SKShapeNode(rect: CGRect(x: -100, y: -4, width: 220, height: 26), cornerRadius: 8)
        arm.fillColor = .systemRed
        arm.strokeColor = SKColor(calibratedRed: 0.12, green: 0, blue: 0, alpha: 1)
        arm.lineWidth = 1.5
        stapler.addChild(arm)
        let gloss = SKShapeNode(rect: CGRect(x: -90, y: 13, width: 195, height: 5), cornerRadius: 2)
        gloss.fillColor = SKColor(calibratedRed: 1.0, green: 0.78, blue: 0.78, alpha: 0.85)
        gloss.strokeColor = .clear
        stapler.addChild(gloss)
        return stapler
    }
}
