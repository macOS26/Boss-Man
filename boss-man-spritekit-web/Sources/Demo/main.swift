import SpriteKit

// A small Pac-Man-style maze mini-game on the wasm-web-kit SpriteKit compat layer
// (original demo code, NOT the BOSS-MAN game): a wall grid (static Box2D bodies),
// an arrow-key player (dynamic body, no gravity, velocity-driven, blocked by
// walls), and collectible dots (sensor bodies removed on contact). Swift -> wasm,
// no Emscripten, drawn through runtime.js.
//
// NB: constants live as `static let` on the scene (lazily initialized), NOT as
// top-level `let` in main.swift — top-level initializers run in main(), which a
// WASI reactor never calls, so they'd be left uninitialized.
final class MazeScene: SKScene, SKPhysicsContactDelegate {
    static let WALL: UInt32 = 1, DOT: UInt32 = 2, PLAYER: UInt32 = 4
    static let MAZE = [
        "#####################",
        "#........#.#........#",
        "#.##.###.#.#.###.##.#",
        "#.#...............#.#",
        "#.#.##.#####.##.#.#.#",
        "#......#. P .#......#",
        "#.#.##.#####.##.#.#.#",
        "#.#...............#.#",
        "#.##.###.#.#.###.##.#",
        "#........#.#........#",
        "#####################",
    ]

    let tile: CGFloat = 48
    var player: SKShapeNode!
    var score = 0, total = 0
    var collected = Set<ObjectIdentifier>()
    let scoreLabel = SKLabelNode(text: "dots: 0")

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(white: 0.05, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        let title = SKLabelNode(text: "BOSS-MAN-style maze · SpriteKit on WebAssembly")
        title.fontSize = 30; title.fontColor = .systemYellow
        title.position = CGPoint(x: size.width / 2, y: size.height - 40); addChild(title)
        scoreLabel.fontSize = 22; scoreLabel.fontColor = .systemGreen
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - 74); addChild(scoreLabel)

        let maze = MazeScene.MAZE
        let cols = maze[0].count
        let originX = (size.width - CGFloat(cols) * tile) / 2
        let mazeTop = size.height - 110
        func pos(_ c: Int, _ r: Int) -> CGPoint {
            CGPoint(x: originX + CGFloat(c) * tile + tile / 2, y: mazeTop - CGFloat(r) * tile - tile / 2)
        }

        for (r, line) in maze.enumerated() {
            for (c, ch) in line.enumerated() {
                let p = pos(c, r)
                switch ch {
                case "#":
                    let w = SKShapeNode(rectOf: CGSize(width: tile - 3, height: tile - 3), cornerRadius: 5)
                    w.fillColor = SKColor(red: 0.16, green: 0.36, blue: 0.95, alpha: 1)
                    w.strokeColor = SKColor(red: 0.3, green: 0.5, blue: 1, alpha: 1); w.lineWidth = 2
                    w.position = p
                    let b = SKPhysicsBody(rectangleOf: CGSize(width: tile, height: tile))
                    b.isDynamic = false; b.categoryBitMask = MazeScene.WALL; b.collisionBitMask = MazeScene.PLAYER
                    w.physicsBody = b; addChild(w)
                case ".":
                    let dot = SKShapeNode(circleOfRadius: 5)
                    dot.fillColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1); dot.strokeColor = .clear
                    dot.position = p
                    let b = SKPhysicsBody(circleOfRadius: 6)
                    b.isDynamic = false; b.isSensor = true
                    b.categoryBitMask = MazeScene.DOT; b.collisionBitMask = MazeScene.PLAYER; b.contactTestBitMask = MazeScene.PLAYER
                    dot.physicsBody = b; addChild(dot); total += 1
                case "P":
                    player = SKShapeNode(circleOfRadius: tile / 2 - 4)
                    player.fillColor = SKColor(red: 0.2, green: 0.85, blue: 1, alpha: 1)
                    player.strokeColor = .white; player.lineWidth = 2; player.position = p
                    let b = SKPhysicsBody(circleOfRadius: tile / 2 - 5)
                    b.categoryBitMask = MazeScene.PLAYER; b.collisionBitMask = MazeScene.WALL | MazeScene.DOT
                    b.contactTestBitMask = MazeScene.DOT; b.allowsRotation = false; b.linearDamping = 0
                    player.physicsBody = b; addChild(player)
                default: break
                }
            }
        }
        scoreLabel.text = "dots: 0/\(total)"
    }

    override func update(_ currentTime: TimeInterval) {
        guard let pb = player?.physicsBody else { return }
        let speed: CGFloat = 220
        var vx: CGFloat = 0, vy: CGFloat = 0
        if skKeyIsDown(SKKey.left)  { vx = -speed }
        if skKeyIsDown(SKKey.right) { vx = speed }
        if skKeyIsDown(SKKey.up)    { vy = speed }
        if skKeyIsDown(SKKey.down)  { vy = -speed }
        pb.velocity = CGVector(dx: vx, dy: vy)
    }

    func didBegin(_ contact: SKPhysicsContact) {
        for b in [contact.bodyA, contact.bodyB] where b.categoryBitMask == MazeScene.DOT {
            let id = ObjectIdentifier(b)
            if collected.contains(id) { continue }
            collected.insert(id)
            b.node?.removeFromParent()
            score += 1
            scoreLabel.text = score >= total ? "all \(total) dots! cleared" : "dots: \(score)/\(total)"
        }
    }
}

nonisolated(unsafe) var skView: SKView? = nil
@_cdecl("boot") func boot() { let v = SKView(); v.presentScene(MazeScene(size: CGSize(width: 1184, height: 666))); skView = v }
@_cdecl("frame") func frame(_ dtMs: Double) { skView?.tick(dtMs) }
