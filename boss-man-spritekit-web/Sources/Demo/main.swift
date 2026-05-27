import SpriteKit

// A demo SpriteKit scene exercising the wasm-web-kit SpriteKit compat layer:
// labels, a moving sprite, a pulsing shape, a rotating shape — all rendered
// through runtime.js (Canvas2D), Swift compiled to wasm, no Emscripten.
final class DemoScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)

        let title = SKLabelNode(text: "SpriteKit on WebAssembly")
        title.fontSize = 46; title.fontColor = .systemYellow; title.fontName = "JetBrainsMono-Bold"
        title.position = CGPoint(x: size.width / 2, y: size.height - 96)
        addChild(title)

        let sub = SKLabelNode(text: "Swift -> wasm, no Emscripten, drawn through wasm-web-kit")
        sub.fontSize = 20; sub.fontColor = .lightGray
        sub.position = CGPoint(x: size.width / 2, y: size.height - 140)
        addChild(sub)

        let box = SKSpriteNode(color: SKColor(red: 0.35, green: 0.78, blue: 1, alpha: 1),
                               size: CGSize(width: 92, height: 92))
        box.position = CGPoint(x: 200, y: 360)
        box.run(.repeatForever(.sequence([
            .move(to: CGPoint(x: size.width - 200, y: 360), duration: 1.6),
            .move(to: CGPoint(x: 200, y: 360), duration: 1.6),
        ])))
        addChild(box)

        let dot = SKShapeNode(circleOfRadius: 42)
        dot.fillColor = SKColor(red: 1, green: 0.82, blue: 0, alpha: 1)
        dot.strokeColor = .orange; dot.lineWidth = 3
        dot.position = CGPoint(x: size.width / 2, y: 230)
        dot.run(.repeatForever(.sequence([.scale(to: 1.5, duration: 0.7), .scale(to: 1.0, duration: 0.7)])))
        addChild(dot)

        let spinner = SKShapeNode(rectOf: CGSize(width: 84, height: 84))
        spinner.fillColor = .clear; spinner.strokeColor = .systemGreen; spinner.lineWidth = 5
        spinner.position = CGPoint(x: size.width / 2, y: 110)
        spinner.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 3)))
        addChild(spinner)
    }
}

nonisolated(unsafe) var skView: SKView? = nil

@_cdecl("boot")
func boot() {
    let v = SKView()
    v.presentScene(DemoScene(size: CGSize(width: 1184, height: 666)))
    skView = v
}

@_cdecl("frame")
func frame(_ dtMs: Double) { skView?.tick(dtMs) }
