import KitABI

// Drives a presented SKScene from the kit's frame(dtMs): advances actions,
// calls scene.update, steps physics, renders the tree (flipping y-up to the
// Canvas y-down surface).
public final class SKView {
    public private(set) var scene: SKScene?
    private var elapsed: TimeInterval = 0

    // No-op rendering knobs (so SpriteKit games drop in unchanged). The kit always
    // renders top-down via Canvas2D and doesn't expose these debug overlays.
    public var showsFPS = false
    public var showsNodeCount = false
    public var showsPhysics = false
    public var showsDrawCount = false
    public var showsFields = false
    public var showsQuadCount = false
    public var ignoresSiblingOrder = false
    public var allowsTransparency = false
    public var shouldCullNonVisibleNodes = true
    public var preferredFramesPerSecond: Int = 60
    public var isAsynchronous = true
    public var isPaused = false
    public var bounds: CGRect = .zero

    public init() {}

    public func presentScene(_ scene: SKScene?) {
        self.scene = scene
        if let s = scene { s.view = self; s.didMove(to: self) }
    }

    // Transitioning between scenes — the transition itself is a no-op; we just
    // present the new scene immediately. Games using SKTransition keep their
    // call sites intact.
    public func presentScene(_ scene: SKScene, transition: SKTransition) {
        presentScene(scene)
    }

    public func tick(_ dtMs: Double) {
        guard let s = scene else { return }
        let dt = dtMs / 1000.0
        elapsed += dt
        pollEvents(s)
        s.stepActions(dt)
        s.update(elapsed)
        s.physicsWorld.step(dt, scene: s)
        s.didSimulatePhysics()
        s.didFinishUpdate()
        render(s)
    }

    private func pollEvents(_ s: SKScene) {
        var type: Int32 = 0, a: Int32 = 0, b: Int32 = 0, c: Int32 = 0, d: Int32 = 0
        while evt_poll(&type, &a, &b, &c, &d) != 0 {
            switch type {
            case 5:  s.keyDown(Int(a))
            case 6:  s.keyUp(Int(a))
            case 9:  s.mouseDown(at: scenePoint(b, c, s))
            case 10: s.mouseUp(at: scenePoint(b, c, s))
            case 11: s.mouseMoved(to: scenePoint(a, b, s))
            default: break
            }
        }
    }

    private func scenePoint(_ x: Int32, _ y: Int32, _ s: SKScene) -> CGPoint {
        CGPoint(x: CGFloat(x), y: s.size.height - CGFloat(y))   // runtime gives y-down logical px
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
