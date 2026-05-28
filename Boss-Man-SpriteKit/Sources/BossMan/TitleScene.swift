import SpriteKit
import KitABI

// Title screen, wasm port. Mirrors the macOS layout: BOSS-MAN wordmark
// tilted slightly, red stapler illustration centered, blinking "P to Play"
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
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 1.0, green: 0.93, blue: 0.34, alpha: 1)
        anchorPoint = .zero

        let title = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
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

        let prompt = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
        prompt.text = Strings.Title.pressSpace
        prompt.fontSize = 40
        prompt.fontColor = .black
        prompt.position = CGPoint(x: size.width / 2, y: size.height * 0.15)
        prompt.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.25, duration: 0.6),
            .fadeAlpha(to: 1.0,  duration: 0.6),
        ])))
        addChild(prompt)

        let high = Persistence.int(forKey: Strings.DefaultsKey.highScore)
        if high > 0 {
            let hs = SKLabelNode(fontNamed: Strings.Font.markerFeltThin)
            hs.text = Strings.Title.highScore(high)
            hs.fontSize = 26
            hs.fontColor = .black
            hs.position = CGPoint(x: size.width / 2, y: size.height * 0.06)
            addChild(hs)
        }

        let hint = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        hint.text = Strings.Title.controlsHint
        hint.fontSize = 16
        hint.fontColor = .black
        hint.position = CGPoint(x: size.width / 2, y: 18)
        addChild(hint)

        let panel = LeaderboardPanel(size: CGSize(width: 320, height: 400))
        panel.position = CGPoint(x: 320 / 2 + 32, y: size.height * 0.5)
        addChild(panel)
    }

    // Input — SF keyCodes mapped to actions. The runtime emits these codes
    // from keydown events; gamepad mapping (gp_map_to_keys on by default)
    // synthesizes Arrow/Space/P so a controller works too.
    override func keyDown(_ key: Int) {
        switch key {
        case 15:  startGame()       // P  → Play
        case 4:   startEditor()     // E  → Level editor
        case 57:  startGame()       // Space → Play (gamepad A button maps here)
        default: break
        }
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
        // Texture size isn't known until the image actually loads in the
        // runtime; we assume the natural aspect and fit it inside maxSize.
        // The image is ~600x440 in the source asset.
        let source = CGSize(width: 600, height: 440)
        let scale = min(maxSize.width / source.width, maxSize.height / source.height)
        let fitted = CGSize(width: source.width * scale, height: source.height * scale)
        if tex.isLoaded {
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
