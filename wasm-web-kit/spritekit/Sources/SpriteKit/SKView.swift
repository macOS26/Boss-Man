import KitABI

// Drives a presented SKScene from the kit's frame(dtMs): advances actions,
// calls scene.update, steps physics, renders the tree (flipping y-up to the
// Canvas y-down surface).
public final class SKView {
    public private(set) var scene: SKScene?
    private var elapsed: TimeInterval = 0

    public init() {}

    public func presentScene(_ scene: SKScene?) {
        self.scene = scene
        if let s = scene { s.view = self; s.didMove(to: self) }
    }

    public func tick(_ dtMs: Double) {
        guard let s = scene else { return }
        let dt = dtMs / 1000.0
        elapsed += dt
        s.stepActions(dt)
        s.update(elapsed)
        s.physicsWorld.step(dt, scene: s)
        s.didSimulatePhysics()
        s.didFinishUpdate()
        render(s)
    }

    private func render(_ s: SKScene) {
        gfx_clear(s.backgroundColor.rgba)
        gfx_save()
        gfx_translate(0, Float(s.size.height))   // map world y-up -> screen y-down
        gfx_scale(1, -1)
        s.renderTree(parentAlpha: 1)
        gfx_restore()
    }
}
