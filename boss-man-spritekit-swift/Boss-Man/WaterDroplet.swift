import AppKit
import SpriteKit

// Water-shot visual: a cyan core with a systemBlue stroke and a small white
// specular highlight, spinning so it sparkles in flight.
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

// One in-flight water shot. It carries its own velocity and age so GameScene's
// per-frame integrator can step a list of droplets; it despawns after
// maxLifetime so a shot that flies off into nowhere can't leak. Wall hits are
// GameScene's job (it owns the GridMap); a boss hit fires as a physics contact,
// with the droplet as the dynamic body in the pair.
final class WaterDroplet: SKNode {
    let velocity: CGVector
    private(set) var age: TimeInterval = 0
    let maxLifetime: TimeInterval = 2.0

    init(direction: MoveDirection, speed: CGFloat) {
        let (dx, dy) = direction.delta
        self.velocity = CGVector(dx: CGFloat(dx) * speed, dy: CGFloat(dy) * speed)
        super.init()
        addChild(WaterDropletVisual.build())
        let body = SKPhysicsBody(circleOfRadius: WaterDropletVisual.radius)
        body.isDynamic = true
        body.affectedByGravity = false
        body.categoryBitMask = PhysicsCategory.waterDroplet
        body.contactTestBitMask = PhysicsCategory.boss
        body.collisionBitMask = 0
        physicsBody = body
    }

    required init?(coder: NSCoder) { fatalError(Strings.System.initCoderUnsupported) }

    // Advance one frame; returns true when the droplet should be despawned
    // (lifetime exceeded).
    func step(dt: TimeInterval) -> Bool {
        position.x += velocity.dx * CGFloat(dt)
        position.y += velocity.dy * CGFloat(dt)
        age += dt
        return age > maxLifetime
    }
}
