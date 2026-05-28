import SpriteKit

// One in-flight water shot. Carries its own velocity + spawn time so the
// GameScene's per-frame integrator can step a list of droplets without
// keeping per-droplet state on the side. Removes itself from the scene
// after maxLifetime so a shot that flies off into nowhere doesn't leak.
final class WaterDroplet: SKNode {
    let velocity: CGVector
    private(set) var age: TimeInterval = 0
    let maxLifetime: TimeInterval = 2.0

    init(direction: MoveDirection, speed: CGFloat) {
        let (dx, dy) = direction.delta
        self.velocity = CGVector(dx: CGFloat(dx) * speed, dy: CGFloat(dy) * speed)
        super.init()
        // Visuals ported from bossman-apple's WaterDroplet.fire: cyan core
        // with a systemBlue stroke + a small white specular highlight in
        // the upper-left, and a 0.4s full rotation so the droplet sparkles
        // as it flies.
        let radius: CGFloat = 5
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = SKColor(red: 0.03, green: 0.80, blue: 0.94, alpha: 0.85)
        core.strokeColor = SKColor(red: 0.0,  green: 0.48, blue: 1.0,  alpha: 1)
        core.lineWidth = 1
        addChild(core)
        let specular = SKShapeNode(circleOfRadius: radius * 0.35)
        specular.fillColor = SKColor(white: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.3, y: radius * 0.3)
        addChild(specular)
        run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.4)))
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
