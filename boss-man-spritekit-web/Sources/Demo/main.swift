import SpriteKit

// Interactive demo of the wasm-web-kit SpriteKit compat layer: a player moved by
// the arrow keys (input via the kit), SKActions, and a Box2D physics pile (drop
// balls with space; contacts fire SKPhysicsContactDelegate). Swift -> wasm, no
// Emscripten, rendered through runtime.js.
final class DemoScene: SKScene, SKPhysicsContactDelegate {
    var player: SKSpriteNode!
    var lastTime: TimeInterval = 0
    var contacts = 0
    let contactLabel = SKLabelNode(text: "contacts: 0")

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)

        let title = SKLabelNode(text: "SpriteKit on WebAssembly")
        title.fontSize = 42; title.fontColor = .systemYellow
        title.position = CGPoint(x: size.width / 2, y: size.height - 78); addChild(title)

        let sub = SKLabelNode(text: "arrow keys move the box · space drops a ball · Swift -> wasm, no Emscripten")
        sub.fontSize = 18; sub.fontColor = .lightGray
        sub.position = CGPoint(x: size.width / 2, y: size.height - 112); addChild(sub)

        contactLabel.fontSize = 18; contactLabel.fontColor = .systemGreen
        contactLabel.position = CGPoint(x: size.width / 2, y: size.height - 142); addChild(contactLabel)

        physicsWorld.gravity = CGVector(dx: 0, dy: -700)
        physicsWorld.contactDelegate = self

        let floor = SKShapeNode(rectOf: CGSize(width: size.width, height: 28))
        floor.fillColor = SKColor(white: 0.22, alpha: 1)
        floor.position = CGPoint(x: size.width / 2, y: 40)
        let fb = SKPhysicsBody(rectangleOf: CGSize(width: size.width, height: 28))
        fb.isDynamic = false; fb.categoryBitMask = 1; fb.contactTestBitMask = 2
        floor.physicsBody = fb; addChild(floor)

        // player (arrow-controlled, no physics; pulses via SKAction)
        player = SKSpriteNode(color: SKColor(red: 0.35, green: 0.78, blue: 1, alpha: 1),
                              size: CGSize(width: 64, height: 64))
        player.position = CGPoint(x: size.width / 2, y: 110)
        player.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.5), .scale(to: 1.0, duration: 0.5)])))
        addChild(player)

        for i in 0..<5 { dropBall(x: 260 + CGFloat(i) * 160) }
    }

    func dropBall(x: CGFloat) {
        let r = CGFloat(20)
        let ball = SKShapeNode(circleOfRadius: r)
        ball.fillColor = SKColor(red: 1, green: 0.82, blue: 0, alpha: 1)
        ball.strokeColor = .orange; ball.lineWidth = 2
        ball.position = CGPoint(x: x, y: size.height - 220)
        let pb = SKPhysicsBody(circleOfRadius: r)
        pb.categoryBitMask = 2; pb.contactTestBitMask = 1 | 2; pb.restitution = 0.45
        ball.physicsBody = pb
        addChild(ball)
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime
        let v: CGFloat = 420 * dt
        if skKeyIsDown(SKKey.left)  { player.position.x -= v }
        if skKeyIsDown(SKKey.right) { player.position.x += v }
        if skKeyIsDown(SKKey.up)    { player.position.y += v }
        if skKeyIsDown(SKKey.down)  { player.position.y -= v }
        player.position.x = max(40, min(size.width - 40, player.position.x))
        player.position.y = max(70, min(size.height - 60, player.position.y))
    }

    override func keyDown(_ key: Int) {
        if key == SKKey.space { dropBall(x: player.position.x) }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        contacts += 1; contactLabel.text = "contacts: \(contacts)"
    }
}

nonisolated(unsafe) var skView: SKView? = nil
@_cdecl("boot") func boot() { let v = SKView(); v.presentScene(DemoScene(size: CGSize(width: 1184, height: 666))); skView = v }
@_cdecl("frame") func frame(_ dtMs: Double) { skView?.tick(dtMs) }
