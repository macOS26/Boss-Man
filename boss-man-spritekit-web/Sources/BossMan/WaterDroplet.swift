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
        // Visual: pale blue core + softer halo, matches SpriteFactory's
        // waterPellet vocabulary so the projectile reads as 'water'.
        let halo = SKShapeNode(circleOfRadius: 7)
        halo.fillColor = SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 0.3)
        halo.strokeColor = .clear
        addChild(halo)
        let core = SKShapeNode(circleOfRadius: 4)
        core.fillColor = SKColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 0.95)
        core.strokeColor = .clear
        addChild(core)
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
