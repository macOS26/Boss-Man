import SpriteKit

// Water-shot visual shared by both ports: a cyan core with a systemBlue stroke
// plus a small white specular highlight, spinning 0.4s/rev so it sparkles in
// flight. Movement + collision differ per platform and live behind #if: apple
// glides the node with SKAction and detects hits via an SKPhysics contact body;
// the wasm port integrates position by hand each frame and lets GameScene test
// the GridMap, because Box2D contacts need a dynamic body in the pair and both
// the boss and the droplet are non-dynamic on wasm.
enum WaterDropletVisual {
    static let radius: CGFloat = 5
    static func build() -> SKNode {
        let node = SKNode()
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = SKColor.systemCyan.withAlphaComponent(0.85)
        core.strokeColor = .systemBlue
        core.lineWidth = 1
        node.addChild(core)
        let specular = SKShapeNode(circleOfRadius: radius * 0.35)
        specular.fillColor = SKColor(calibratedWhite: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.3, y: radius * 0.3)
        node.addChild(specular)
        node.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.4)))
        return node
    }
}

#if os(macOS)
enum WaterDroplet {
    private static let radius = WaterDropletVisual.radius
    private static let speed: CGFloat = 320
    private static let maxDistance: CGFloat = 576

    static func fire(from position: CGPoint, direction: MoveDirection, tileSize: CGFloat) -> SKNode {
        let node = SKNode()
        node.name = "waterDroplet"
        node.zPosition = 12
        node.addChild(WaterDropletVisual.build())
        node.alpha = 1.0
        // Stash the travel delta so the boss dodge logic can read each droplet's
        // axis (the SKAction bakes direction into its target, not the node).
        let dirData = NSMutableDictionary()
        dirData["wdx"] = direction.delta.dx
        dirData["wdy"] = direction.delta.dy
        node.userData = dirData

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.isDynamic = false
        body.affectedByGravity = false
        body.categoryBitMask = PhysicsCategory.waterDroplet
        body.contactTestBitMask = PhysicsCategory.boss | PhysicsCategory.wall
        body.collisionBitMask = 0
        body.usesPreciseCollisionDetection = true
        node.physicsBody = body

        let dx = CGFloat(direction.delta.dx)
        let dy = CGFloat(direction.delta.dy)
        let target = CGPoint(x: position.x + dx * maxDistance,
                             y: position.y + dy * maxDistance)
        let duration = TimeInterval(maxDistance / speed)

        node.position = CGPoint(x: position.x + dx * (tileSize / 2 + radius + 2),
                                y: position.y + dy * (tileSize / 2 + radius + 2))

        let move = SKAction.move(to: target, duration: duration)
        let remove = SKAction.removeFromParent()
        node.run(.sequence([move, remove]), withKey: Strings.ActionKey.waterDropletMove)

        return node
    }
}
#elseif os(WASI)
// One in-flight water shot. Carries its own velocity + spawn time so the
// GameScene's per-frame integrator can step a list of droplets without keeping
// per-droplet state on the side. Removes itself after maxLifetime so a shot
// that flies off into nowhere doesn't leak.
final class WaterDroplet: SKNode {
    let velocity: CGVector
    private(set) var age: TimeInterval = 0
    let maxLifetime: TimeInterval = 2.0

    init(direction: MoveDirection, speed: CGFloat) {
        let (dx, dy) = direction.delta
        self.velocity = CGVector(dx: CGFloat(dx) * speed, dy: CGFloat(dy) * speed)
        super.init()
        addChild(WaterDropletVisual.build())
    }

    // Advance one frame; return true if the droplet should be despawned
    // (lifetime exceeded — wall collision is the GameScene's responsibility
    // since it knows the GridMap).
    func step(dt: TimeInterval) -> Bool {
        position.x += velocity.dx * CGFloat(dt)
        position.y += velocity.dy * CGFloat(dt)
        age += dt
        return age > maxLifetime
    }
}
#endif
