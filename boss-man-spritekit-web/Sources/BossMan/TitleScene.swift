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
    private var levelEditorLabel: SKLabelNode?
    private var clickToPlayLabel: SKLabelNode?
    private var promptPlayLabel: SKLabelNode?
    private var promptEditorLabel: SKLabelNode?

    private func bossTracksText() -> String {
        let square = Persistence.bool(forKey: Strings.DefaultsKey.bossTracksSquare)
        return "Boss Tracks: \(square ? "Square" : "Smooth")"
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 1.0, green: 0.93, blue: 0.34, alpha: 1)
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
        stapler.position = CGPoint(x: size.width / 2, y: size.height * 0.46)
        stapler.zRotation = -0.06
        addChild(stapler)

        // Split blinking prompt: green "[P]lay Game" and blue "Level [E]ditor"
        // flanking a "*". Separator centred; the play label right-aligns to its
        // left, the editor label left-aligns to its right, so no width
        // measurement is needed at layout time (font may not be loaded yet).
        let promptY = size.height * 0.15
        let green = SKColor(red: 0.0,  green: 0.45, blue: 0.10, alpha: 1)
        let blue  = SKColor(red: 0.05, green: 0.25, blue: 0.75, alpha: 1)
        let blink = SKAction.repeatForever(.sequence([
            .fadeAlpha(to: 0.25, duration: 0.6),
            .fadeAlpha(to: 1.0,  duration: 0.6),
        ]))

        let sep = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
        sep.text = Strings.Title.promptSep
        sep.fontSize = 40
        sep.fontColor = .black
        sep.position = CGPoint(x: size.width / 2, y: promptY)
        sep.run(blink)
        addChild(sep)

        let playGame = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
        playGame.text = Strings.Title.playGame
        playGame.fontSize = 40
        playGame.fontColor = green
        playGame.horizontalAlignmentMode = .right
        playGame.position = CGPoint(x: size.width / 2 - 18, y: promptY)
        playGame.run(blink)
        addChild(playGame)
        promptPlayLabel = playGame

        let levelEditor = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
        levelEditor.text = Strings.Title.levelEditor
        levelEditor.fontSize = 40
        levelEditor.fontColor = blue
        levelEditor.horizontalAlignmentMode = .left
        levelEditor.position = CGPoint(x: size.width / 2 + 18, y: promptY)
        levelEditor.run(blink)
        addChild(levelEditor)
        promptEditorLabel = levelEditor

        let high = Persistence.int(forKey: Strings.DefaultsKey.highScore)
        if high > 0 {
            let hs = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
            hs.text = Strings.Title.highScore(high)
            hs.fontSize = 26
            hs.fontColor = .black
            hs.position = CGPoint(x: size.width / 2, y: size.height * 0.06 + 15)
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

        // Boss Tracks toggle, just above the fullscreen hint. Click to switch
        // between "Smooth" (this port's continuous lerp) and "Square" (the
        // apple/C++ tile-by-tile cadence). Mode persists in localStorage.
        let tracks = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        tracks.text = bossTracksText()
        tracks.fontSize = 16
        tracks.fontColor = .black
        tracks.horizontalAlignmentMode = .right
        tracks.position = CGPoint(x: size.width - 20, y: 44)
        addChild(tracks)
        bossTracksLabel = tracks

        // Mobile tap targets stacked above the Boss Tracks toggle, same
        // right-aligned column: "Level Editor" (= E key) and "Click to Play"
        // (= P key). Touch devices have no keyboard, so these give a tap path
        // into the game and the editor.
        let editorTap = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        editorTap.text = "Level Editor"
        editorTap.fontSize = 16
        editorTap.fontColor = .black
        editorTap.horizontalAlignmentMode = .right
        editorTap.position = CGPoint(x: size.width - 20, y: 70)
        addChild(editorTap)
        levelEditorLabel = editorTap

        let playTap = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        playTap.text = "Click to Play"
        playTap.fontSize = 16
        playTap.fontColor = .black
        playTap.horizontalAlignmentMode = .right
        playTap.position = CGPoint(x: size.width - 20, y: 96)
        addChild(playTap)
        clickToPlayLabel = playTap

        let panel = LeaderboardPanel(size: CGSize(width: 320, height: 400))
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
        case 57:  startGame()                    // Space → Play (gamepad A button maps here)
        default: break
        }
    }

    override func mouseDown(at p: CGPoint) {
        if let play = clickToPlayLabel, labelHit(play, p) { startGame(); return }
        if let editor = levelEditorLabel, labelHit(editor, p) { startEditor(); return }
        // Big blinking prompt: green "[P]lay Game" starts the game, blue
        // "Level [E]ditor" opens the editor.
        if let play = promptPlayLabel, labelHit(play, p) { startGame(); return }
        if let editor = promptEditorLabel, labelHit(editor, p) { startEditor(); return }
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
