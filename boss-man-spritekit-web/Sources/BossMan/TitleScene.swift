import SpriteKit
import KitABI

// Title screen, wasm port. Mirrors the macOS layout: BOSS-MAN wordmark
// tilted slightly, red stapler illustration centered, blinking "Press Play"
// prompt, leaderboard panel docked left, controls hint at the bottom.
//
// Differences vs the macOS original:
//   - Background color set on SKScene directly (no NSColor conversion).
//   - Font-availability probing is collapsed: the kit's text renderer falls
//     back to its default monospace stack when a name isn't loaded, so we
//     just name our preferred font and let the runtime choose.
//   - UserDefaults reads route through SKSceneLoader-adjacent localStorage
//     helpers (Persistence.swift) → store_get/store_set.
//   - Input is a single Int keyCode (SF key index from runtime.js SF_KEY).
final class TitleScene: SKScene {
    private var bossTracksLabel: SKLabelNode?
    private var waterGunLabel: SKLabelNode?
    private var fullscreenLabel: SKLabelNode?
    private var escWindowLabel: SKLabelNode?
    private var playButtonRect = CGRect.zero
    private var editorButtonRect = CGRect.zero

    private func bossTracksText() -> String {
        let square = Persistence.bool(forKey: Strings.DefaultsKey.bossTracksSquare)
        return "Boss Tracks: \(square ? "Square" : "Smooth")"
    }

    private func waterGunText() -> String {
        let left = Persistence.bool(forKey: Strings.DefaultsKey.waterGunLeft)
        return "Water Gun: \(left ? "Left" : "Right")"
    }

    // A filled rounded-rect title button with centred white text. Returns its
    // tap rect (scene coords) so mouseDown can hit-test the whole button.
    private func makeTitleButton(text: String, color: SKColor, center: CGPoint, size s: CGSize, textDY: CGFloat = 0) -> CGRect {
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
        return CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2,
                      width: s.width, height: s.height)
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(calibratedRed: 1.0, green: 0.93, blue: 0.34, alpha: 1)
        anchorPoint = .zero

        let title = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
        title.text = Strings.Title.gameTitle
        title.fontSize = 108
        title.fontColor = .black
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.74)
        title.zRotation = -0.04
        // The leaderboard post-it docks at the left edge and we want the
        // wordmark to read as the foreground element when they overlap.
        title.zPosition = 10
        addChild(title)

        let stapler = makeStapler()
        stapler.position = CGPoint(x: size.width / 2, y: size.height * 0.46 + 8)
        stapler.zRotation = -0.06
        addChild(stapler)

        // Two title buttons: green "(P)lay" and blue "(E)ditor", white text on a
        // filled rounded rect. Centred as a pair; click/tap either, or press
        // P / E. Fixed sizes avoid layout-time text measurement (font-load race).
        let promptY = size.height * 0.15 + 20
        let green = SKColor(red: 0.0,  green: 0.55, blue: 0.18, alpha: 1)
        let blue  = SKColor(red: 0.10, green: 0.35, blue: 0.85, alpha: 1)
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

        let hint = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        hint.text = Strings.Title.controlsHint
        hint.fontSize = 16
        hint.fontColor = .black
        hint.position = CGPoint(x: size.width / 2, y: 18)
        addChild(hint)

        // Fullscreen hint, bottom-right corner (matches the C++ build's
        // TitleScreen layout). Right-aligned at (W - 20, 18) in y-up.
        let fsHint = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        fsHint.text = "F for Fullscreen"
        fsHint.fontSize = 16
        fsHint.fontColor = .black
        fsHint.horizontalAlignmentMode = .right
        fsHint.position = CGPoint(x: size.width - 20, y: 18)
        addChild(fsHint)
        fullscreenLabel = fsHint

        // ESC returns to a window (browsers also exit fullscreen on Esc natively).
        let escHint = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        escHint.text = "ESC for Window"
        escHint.fontSize = 16
        escHint.fontColor = .black
        escHint.horizontalAlignmentMode = .right
        escHint.position = CGPoint(x: size.width - 20, y: 69)
        addChild(escHint)
        escWindowLabel = escHint

        // Boss Tracks toggle, just above the fullscreen hint. Click to switch
        // between "Smooth" (this port's continuous lerp) and "Square" (the
        // apple/C++ tile-by-tile cadence). Mode persists in localStorage.
        let tracks = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        tracks.text = bossTracksText()
        tracks.fontSize = 16
        tracks.fontColor = .black
        tracks.horizontalAlignmentMode = .right
        tracks.position = CGPoint(x: size.width - 20, y: 120)
        addChild(tracks)
        bossTracksLabel = tracks

        // Water Gun side toggle, above Boss Tracks. Switches which side the
        // in-game fire button sits on (Right default; Left pairs with a future
        // left-side joystick). Persists in localStorage.
        let waterGun = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        waterGun.text = waterGunText()
        waterGun.fontSize = 16
        waterGun.fontColor = .black
        waterGun.horizontalAlignmentMode = .right
        waterGun.position = CGPoint(x: size.width - 20, y: 171)
        addChild(waterGun)
        waterGunLabel = waterGun

        let panel = LeaderboardPanel(
            size: CGSize(width: 320, height: 400),
            titleFont: Strings.Font.markerFeltWide,
            bodyFont: Strings.Font.menloBold
        )
        panel.position = CGPoint(x: 320 / 2 + 32, y: size.height * 0.5)
        addChild(panel)
    }

    // Input — SF keyCodes mapped to actions. The runtime emits these codes
    // from keydown events; gamepad mapping (gp_map_to_keys on by default)
    // synthesizes Arrow/Space/P so a controller works too.
    override func keyDown(_ key: Int) {
        switch key {
        case 15:  startGame()                    // P  → Play
        case 4:   startEditor()                  // E  → Level editor
        case 5:   win_request_fullscreen()       // F  → Fullscreen
        case 36:  win_exit_fullscreen()          // Esc → back to a window
        case 57:  startGame()                    // Space → Play (gamepad A button maps here)
        default: break
        }
    }

    override func mouseDown(at p: CGPoint) {
        if let fs = fullscreenLabel, labelHit(fs, p) { win_request_fullscreen(); return }
        if let esc = escWindowLabel, labelHit(esc, p) { win_exit_fullscreen(); return }
        if let wg = waterGunLabel, labelHit(wg, p) {
            let left = !Persistence.bool(forKey: Strings.DefaultsKey.waterGunLeft)
            Persistence.set(left, forKey: Strings.DefaultsKey.waterGunLeft)
            wg.text = waterGunText()
            return
        }
        // Title buttons: green "(P)lay" starts the game, blue "(E)ditor" opens
        // the editor. Whole button rect is the tap target.
        if playButtonRect.contains(p)   { startGame();   return }
        if editorButtonRect.contains(p) { startEditor(); return }
        if let label = bossTracksLabel, labelHit(label, p) {
            let square = !Persistence.bool(forKey: Strings.DefaultsKey.bossTracksSquare)
            Persistence.set(square, forKey: Strings.DefaultsKey.bossTracksSquare)
            label.text = bossTracksText()
        }
    }

    // Hit-test a label with a touch-friendly margin, honoring its horizontal
    // alignment so centered/left/right labels all map to the right glyph box.
    private func labelHit(_ label: SKLabelNode, _ p: CGPoint) -> Bool {
        let w = label.measuredWidth()
        let minX: CGFloat
        switch label.horizontalAlignmentMode {
        case .right:  minX = label.position.x - w
        case .center: minX = label.position.x - w / 2
        case .left:   minX = label.position.x
        }
        let h = max(34, label.fontSize * 1.4)
        let rect = CGRect(x: minX - 12, y: label.position.y - h * 0.3, width: w + 24, height: h)
        return rect.contains(p)
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

    // Red stapler illustration. On the desktop build this loads the
    // PNG asset; on web the kit's image preloader registers the same name
    // through manifest.json, so SKTexture(imageNamed:) resolves it.
    // If the asset hasn't loaded yet (or the manifest doesn't list it), we
    // render a stylized vector stand-in so the title screen never goes blank.
    private func makeStapler() -> SKNode {
        let maxSize = CGSize(width: 380, height: 290)
        let tex = SKTexture(imageNamed: "red-stapler")
        if tex.isLoaded, tex.size.width > 0, tex.size.height > 0 {
            // Use the texture's actual natural dimensions so the sprite keeps
            // its aspect ratio — no more guessing 600x440 and stretching the
            // image when the source is something else (the asset is 1002x1002).
            let scale = min(maxSize.width / tex.size.width, maxSize.height / tex.size.height)
            let fitted = CGSize(width: tex.size.width * scale, height: tex.size.height * scale)
            return SKSpriteNode(texture: tex, size: fitted)
        }
        return makeFallbackStapler()
    }

    private func makeFallbackStapler() -> SKNode {
        let stapler = SKNode()
        let baseRect = CGRect(x: -110, y: -22, width: 220, height: 16)
        let base = SKShapeNode(rect: baseRect, cornerRadius: 4)
        base.fillColor = SKColor(red: 0.55, green: 0.05, blue: 0.05, alpha: 1)
        base.strokeColor = SKColor(red: 0.12, green: 0, blue: 0, alpha: 1)
        base.lineWidth = 1.5
        stapler.addChild(base)
        let armRect = CGRect(x: -100, y: -4, width: 220, height: 26)
        let arm = SKShapeNode(rect: armRect, cornerRadius: 8)
        arm.fillColor = SKColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
        arm.strokeColor = SKColor(red: 0.12, green: 0, blue: 0, alpha: 1)
        arm.lineWidth = 1.5
        stapler.addChild(arm)
        let glossRect = CGRect(x: -90, y: 13, width: 195, height: 5)
        let gloss = SKShapeNode(rect: glossRect, cornerRadius: 2)
        gloss.fillColor = SKColor(red: 1.0, green: 0.78, blue: 0.78, alpha: 0.85)
        gloss.strokeColor = .clear
        stapler.addChild(gloss)
        return stapler
    }
}
