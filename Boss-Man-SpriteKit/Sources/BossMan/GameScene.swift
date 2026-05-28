import SpriteKit

// Game scene. First wasm port iteration is a placeholder: black backdrop with
// a "GAME STARTING…" caption and an Escape key to return to the title. The
// real maze build (MazeBuilder + Pete/Boss controllers + ContactRouter +
// HUD) lands in follow-up commits once the support types are in place.
final class GameScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .black
        anchorPoint = .zero

        let caption = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
        caption.text = "GAME STARTING…"
        caption.fontSize = 48
        caption.fontColor = .white
        caption.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(caption)

        let hint = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        hint.text = "ESC to return to title"
        hint.fontSize = 14
        hint.fontColor = SKColor(white: 0.6, alpha: 1)
        hint.position = CGPoint(x: size.width / 2, y: size.height / 2 - 60)
        addChild(hint)
    }

    override func keyDown(_ key: Int) {
        if key == 36 {        // Escape
            let title = TitleScene(size: size)
            title.scaleMode = .aspectFit
            view?.presentScene(title, transition: .fade(withDuration: 0.4))
        }
    }
}
