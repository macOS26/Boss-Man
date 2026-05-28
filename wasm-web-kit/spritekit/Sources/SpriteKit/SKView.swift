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
        // Tear down the outgoing scene first (Apple calls willMove(from:) on
        // it). Without this a scene's teardown never runs — e.g. a per-scene
        // SoundManager's looping music voice lives in the runtime and outlives
        // the Swift object, so the next scene's music stacks on top of it.
        if let old = self.scene, old !== scene { old.willMove(from: self); old.view = nil }
        self.scene = scene
        if let s = scene { s.view = self; s.didMove(to: self) }
    }

    // Transitioning between scenes — the transition itself is a no-op; we just
    // present the new scene immediately. Games using SKTransition keep their
    // call sites intact.
    public func presentScene(_ scene: SKScene, transition: SKTransition) {
        presentScene(scene)
    }

    // Snapshot a node subtree to an SKTexture. Renders the tree into an
    // offscreen canvas sized to the node's accumulated frame, then commits
    // it as an image asset the kit can re-draw via gfx_draw_image.
    public func texture(from node: SKNode) -> SKTexture? {
        let frame = node.calculateAccumulatedFrame()
        let w = max(1, Int(frame.width)), h = max(1, Int(frame.height))
        let handle = gfx_offscreen_begin(Int32(w), Int32(h))
        // Translate so the node's bottom-left sits at origin in the offscreen
        // canvas (Canvas2D is y-down, but our scene-render path flips already).
        gfx_save()
        gfx_translate(Float(-frame.minX), Float(-frame.minY))
        node.renderTree(parentAlpha: 1)
        gfx_restore()
        let img = gfx_offscreen_end_to_image(handle)
        if img <= 0 { return nil }
        let t = SKTexture(handle: img)
        t.size = CGSize(width: CGFloat(w), height: CGFloat(h))
        return t
    }
    public func texture(from node: SKNode, crop: CGRect) -> SKTexture? { texture(from: node) }

    public func tick(_ dtMs: Double) {
        guard let s = scene else { return }
        let dt = dtMs / 1000.0
        elapsed += dt
        SKSpriteNode._setKitClock(Float(elapsed))    // u_time for SKShader binds
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
        // Apply the camera's inverse so the scene appears as if shot through
        // its lens: translate the world so cam.position sits at scene center,
        // then rotate/scale by the camera's inverse. We render the camera node
        // itself (so its children act as UI overlays riding along).
        if let cam = s.camera {
            gfx_translate(Float(s.size.width / 2), Float(s.size.height / 2))
            let sx = cam.xScale == 0 ? 1 : 1 / cam.xScale
            let sy = cam.yScale == 0 ? 1 : 1 / cam.yScale
            gfx_scale(Float(sx), Float(sy))
            if cam.zRotation != 0 { gfx_rotate(Float(cam.zRotation * 180.0 / Double.pi)) }
            gfx_translate(Float(-cam.position.x), Float(-cam.position.y))
        }
        s.renderTree(parentAlpha: 1)
        // Apple-style showsPhysics overlay: strokes every Box2D body's
        // outline on top of the scene. Lives inside the same y-up
        // transform so positions read straight from Box2D coordinates.
        if s.physicsWorld.showsPhysics { s.physicsWorld.renderDebug() }
        gfx_restore()
    }
}
