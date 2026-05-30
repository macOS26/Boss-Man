import KitABI

// Per-frame completion callbacks for one-shot audio. Web Audio finishes a
// buffer source asynchronously with no callback into wasm, so the AVFoundation
// shim registers a snd_play voice + handler here and tick() polls snd_status
// each frame, firing the handler once the voice goes idle. This lets
// AVAudioPlayerNode.scheduleBuffer's completionHandler behave like the apple
// engine (e.g. BossMan's teleport one-shot guard).
nonisolated(unsafe) var _kitAudioCompletions: [(voice: Int32, handler: () -> Void)] = []

public func _kitRegisterAudioCompletion(_ voice: Int32, _ handler: @escaping () -> Void) {
    _kitAudioCompletions.append((voice, handler))
}

func _kitDrainAudioCompletions() {
    guard !_kitAudioCompletions.isEmpty else { return }
    var pending: [(voice: Int32, handler: () -> Void)] = []
    for entry in _kitAudioCompletions {
        if snd_status(entry.voice) == 0 { entry.handler() }
        else { pending.append(entry) }
    }
    _kitAudioCompletions = pending
}

// Drives a presented SKScene from the kit's frame(dtMs): advances actions,
// calls scene.update, steps physics, renders the tree (flipping y-up to the
// Canvas y-down surface).
public final class SKView {
    public private(set) var scene: SKScene?
    private var elapsed: TimeInterval = 0
    // Wall-clock accrued toward the next render. Seeded large so the first tick
    // after presentScene always draws; reset on each render. Lets the title
    // screen idle at 1 fps (preferredFramesPerSecond) without skipping startup.
    private var renderAccum: Double = 1e9

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
        renderAccum = 1e9   // draw the incoming scene on the very next tick
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
        // Replicate the main render's y-up -> y-down flip (SKView.render does
        // translate(0,h)+scale(1,-1) before drawing the tree). Without it the
        // baked bitmap is vertically mirrored — invisible on symmetric content
        // (a dot) but it flips an asymmetric maze onto the wrong rows. Then
        // translate so the node's frame origin maps to the offscreen origin.
        gfx_save()
        gfx_translate(0, Float(h))
        gfx_scale(1, -1)
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
        // Clamp the frame delta to one 60 Hz step. On the web a dropped frame,
        // GC pause, or tab refocus hands us a large delta that makes
        // SKAction-driven movement (Pete) lurch forward more than a step, while
        // the fixed-1/60 game logic (the bosses) does not — so only the hero
        // skips. Capping at 1/60 means Pete advances at most one frame per
        // render: real-time on a steady 60 Hz+ display, degrading to slow-mo
        // (never a jump) under sustained drops, in lockstep with the bosses.
        let dt = min(dtMs / 1000.0, 1.0 / 60.0)
        elapsed += dt
        SKSpriteNode._setKitClock(Float(elapsed))    // u_time for SKShader binds
        _kitDrainAudioCompletions()
        let hadInput = pollEvents(s)
        s.stepActions(dt)
        s.update(elapsed)
        s.physicsWorld.step(dt, scene: s)
        s.didSimulatePhysics()
        s.didFinishUpdate()
        // Throttle rendering to preferredFramesPerSecond. The title screen sets
        // this to 1: nothing on it animates, so re-rasterizing it (incl. the
        // leaderboard blur) 60x/s is wasted work + canvas churn. Input forces an
        // immediate redraw so clicks/toggles still feel instant.
        let interval = 1.0 / Double(max(1, preferredFramesPerSecond))
        renderAccum += dt
        if hadInput || renderAccum >= interval {
            renderAccum = 0
            render(s)
        }
    }

    @discardableResult
    private func pollEvents(_ s: SKScene) -> Bool {
        var type: Int32 = 0, a: Int32 = 0, b: Int32 = 0, c: Int32 = 0, d: Int32 = 0
        var handled = false
        while evt_poll(&type, &a, &b, &c, &d) != 0 {
            handled = true
            switch type {
            case 5:  s.keyDown(Int(a))
            case 6:  s.keyUp(Int(a))
            case 9:  a == 1 ? s.rightMouseDown(at: scenePoint(b, c, s)) : s.mouseDown(at: scenePoint(b, c, s))
            case 10: a == 1 ? s.rightMouseUp(at: scenePoint(b, c, s))   : s.mouseUp(at: scenePoint(b, c, s))
            case 11: s.mouseMoved(to: scenePoint(a, b, s))
            default: break
            }
        }
        return handled
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
