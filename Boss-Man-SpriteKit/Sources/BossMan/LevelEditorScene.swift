import SpriteKit

// Level editor — placeholder for the wasm port. The macOS version lets you
// paint tiles into a grid and serialize the result to JSON. The web port
// will reach feature parity once the level-file loader is wired through
// SKSceneLoader and Persistence.setString stores the edited grid back.
final class LevelEditorScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        anchorPoint = .zero

        let caption = SKLabelNode(fontNamed: Strings.Font.markerFeltWide)
        caption.text = "LEVEL EDITOR"
        caption.fontSize = 48
        caption.fontColor = .white
        caption.position = CGPoint(x: size.width / 2, y: size.height * 0.65)
        addChild(caption)

        let stub = SKLabelNode(fontNamed: Strings.Font.jetBrainsMono)
        stub.text = "coming soon · ESC to return"
        stub.fontSize = 14
        stub.fontColor = SKColor(white: 0.6, alpha: 1)
        stub.position = CGPoint(x: size.width / 2, y: size.height * 0.45)
        addChild(stub)
    }

    override func keyDown(_ key: Int) {
        if key == 36 {        // Escape
            let title = TitleScene(size: size)
            title.scaleMode = .aspectFit
            view?.presentScene(title, transition: .fade(withDuration: 0.3))
        }
    }
}
