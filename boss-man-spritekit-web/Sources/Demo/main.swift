import SpriteKit

// Demo exercising the wasm-web-kit SpriteKit compat layer end to end: labels,
// a moving sprite, a pulsing shape (SKAction), and a Box2D-backed physics pile
// (dynamic shapes fall onto a static floor; contacts fire SKPhysicsContactDelegate).
// Swift -> wasm, no Emscripten, drawn through runtime.js.
final class DemoScene: SKScene, SKPhysicsContactDelegate {
    var contacts = 0
    let contactLabel = SKLabelNode(text: "contacts: 0")

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)

        let title = SKLabelNode(text: "SpriteKit on WebAssembly")
        title.fontSize = 44; title.fontColor = .systemYellow
        title.position = CGPoint(x: size.width / 2, y: size.height - 84)
        addChild(title)

        let sub = SKLabelNode(text: "Swift -> wasm + Box2D physics, no Emscripten, via wasm-web-kit")
        sub.fontSize = 19; sub.fontColor = .lightGray
        sub.position = CGPoint(x: size.width / 2, y: size.height - 120)
        addChild(sub)

        let box = SKSpriteNode(color: SKColor(red: 0.35, green: 0.78, blue: 1, alpha: 1),
                               size: CGSize(width: 70, height: 70))
        box.position = CGPoint(x: 150, y: size.height - 200)
        box.run(.repeatForever(.sequence([
            .move(to: CGPoint(x: size.width - 150, y: size.height - 200), duration: 1.8),
            .move(to: CGPoint(x: 150, y: size.height - 200), duration: 1.8),
        ])))
        addChild(box)

        contactLabel.fontSize = 20; contactLabel.fontColor = .systemGreen
        contactLabel.position = CGPoint(x: size.width / 2, y: size.height - 160)
        addChild(contactLabel)

        // --- physics ---
        physicsWorld.gravity = CGVector(dx: 0, dy: -700)
        physicsWorld.contactDelegate = self

        let floor = SKShapeNode(rectOf: CGSize(width: size.width, height: 28))
        floor.fillColor = SKColor(white: 0.22, alpha: 1)
        floor.position = CGPoint(x: size.width / 2, y: 40)
        let fb = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 28))
        fb.isDynamic = false; fb.categoryBitMask = 1; fb.contactTestBitMask = 2
        floor.physicsBody = fb
        addChild(floor)

        let palette: [SKColor] = [.systemYellow, .systemBlue, .systemGreen, .orange, .magenta, .cyan]
        for i in 0..<8 {
            let r = CGFloat(22 + (i % 3) * 8)
            let node = SKShapeNode(circleOfRadius: r)
            node.fillColor = palette[i % palette.count]
            node.strokeColor = .white; node.lineWidth = 2
            node.position = CGPoint(x: 220 + CGFloat(i) * 95, y: size.height - 260 - CGFloat(i % 3) * 60)
            let pb = SKPhysicsBody(circleOfRadius: r)
            pb.categoryBitMask = 2; pb.contactTestBitMask = 1 | 2; pb.restitution = 0.4
            node.physicsBody = pb
            addChild(node)
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        contacts += 1
        contactLabel.text = "contacts: \(contacts)"
    }
}

nonisolated(unsafe) var skView: SKView? = nil
@_cdecl("boot") func boot() {
    let v = SKView(); v.presentScene(DemoScene(size: CGSize(width: 1184, height: 666))); skView = v
}
@_cdecl("frame") func frame(_ dtMs: Double) { skView?.tick(dtMs) }
