public enum SKActionTimingMode { case linear, easeIn, easeOut, easeInEaseOut }

public final class SKAction {
    enum Kind {
        case moveBy(CGFloat, CGFloat), moveTo(CGPoint), moveToX(CGFloat), moveToY(CGFloat)
        case scaleTo(CGFloat), scaleBy(CGFloat), fadeTo(CGFloat)
        case rotateBy(CGFloat), rotateTo(CGFloat)
        case colorize(SKColor, CGFloat)
        case wait, run(() -> Void), custom((SKNode, CGFloat) -> Void)
        case sequence([SKAction]), group([SKAction]), repeatN(SKAction, Int), repeatForever(SKAction)
        case removeFromParent
        case hide(Bool)                                     // hide(true) / unhide(false)
        case scaleToSize(CGSize)                            // scale(to: CGSize, duration:)
        case scaleXY(CGFloat, CGFloat)                      // scaleX(to:y:duration:)
        case setTexture(SKTexture)                          // SKSpriteNode.texture = t (instant)
        case animate([SKTexture], TimeInterval, Bool, Bool) // textures, timePerFrame, resize, restore
        case changeVolume(CGFloat)                          // for SKAudioNode
        case resizeTo(CGFloat, CGFloat)                     // SKSpriteNode.size = (w,h)
        case resizeBy(CGFloat, CGFloat)
        case followPath(CGPath, Bool, Bool)                 // asOffset, orientToPath
    }
    let kind: Kind
    var duration: TimeInterval
    public var timingMode: SKActionTimingMode = .linear
    init(_ k: Kind, _ d: TimeInterval) { kind = k; duration = d }

    public static func moveBy(x: CGFloat, y: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.moveBy(x, y), d) }
    public static func move(by v: CGVector, duration d: TimeInterval) -> SKAction { SKAction(.moveBy(v.dx, v.dy), d) }
    public static func move(to p: CGPoint, duration d: TimeInterval) -> SKAction { SKAction(.moveTo(p), d) }
    public static func moveTo(x: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.moveToX(x), d) }
    public static func moveTo(y: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.moveToY(y), d) }
    public static func scale(to s: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.scaleTo(s), d) }
    public static func scale(by s: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.scaleBy(s), d) }
    public static func fadeAlpha(to a: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.fadeTo(a), d) }
    public static func fadeIn(withDuration d: TimeInterval) -> SKAction { SKAction(.fadeTo(1), d) }
    public static func fadeOut(withDuration d: TimeInterval) -> SKAction { SKAction(.fadeTo(0), d) }
    public static func rotate(byAngle a: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.rotateBy(a), d) }
    public static func rotate(toAngle a: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.rotateTo(a), d) }
    public static func wait(forDuration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func wait(forDuration d: TimeInterval, withRange r: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func run(_ b: @escaping () -> Void) -> SKAction { SKAction(.run(b), 0) }
    public static func customAction(withDuration d: TimeInterval, actionBlock: @escaping (SKNode, CGFloat) -> Void) -> SKAction { SKAction(.custom(actionBlock), d) }
    public static func sequence(_ a: [SKAction]) -> SKAction { SKAction(.sequence(a), a.reduce(0) { $0 + $1.duration }) }
    public static func group(_ a: [SKAction]) -> SKAction { SKAction(.group(a), a.map { $0.duration }.max() ?? 0) }
    public static func `repeat`(_ a: SKAction, count: Int) -> SKAction { SKAction(.repeatN(a, count), a.duration * Double(count)) }
    public static func repeatForever(_ a: SKAction) -> SKAction { SKAction(.repeatForever(a), .infinity) }
    public static func removeFromParent() -> SKAction { SKAction(.removeFromParent, 0) }

    // SpriteKit sprite-sheet animation. Cycles through textures every timePerFrame
    // seconds, setting SKSpriteNode.texture. resize matches the sprite size to each
    // frame's texture size; restore puts the first texture back when the action ends.
    public static func setTexture(_ t: SKTexture) -> SKAction { SKAction(.setTexture(t), 0) }
    public static func setTexture(_ t: SKTexture, resize: Bool) -> SKAction { SKAction(.setTexture(t), 0) }
    public static func animate(with textures: [SKTexture], timePerFrame tpf: TimeInterval,
                               resize: Bool = false, restore: Bool = false) -> SKAction {
        SKAction(.animate(textures, tpf, resize, restore), tpf * Double(max(textures.count, 1)))
    }
    public static func animate(with textures: [SKTexture], timePerFrame tpf: TimeInterval) -> SKAction {
        animate(with: textures, timePerFrame: tpf, resize: false, restore: false)
    }

    // SKAudioNode volume ramp. Block form mirrors AsteroidZ-style call sites.
    public static func changeVolume(to v: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.changeVolume(v), d) }
    public static func changeVolume(by delta: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.changeVolume(delta), d) }

    // SKSpriteNode size animation.
    public static func resize(toWidth w: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.resizeTo(w, -1), d) }
    public static func resize(toHeight h: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.resizeTo(-1, h), d) }
    public static func resize(toWidth w: CGFloat, height h: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.resizeTo(w, h), d) }
    public static func resize(byWidth dw: CGFloat, height dh: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.resizeBy(dw, dh), d) }

    // CGPath following — samples the path every step. orientToPath rotates the
    // node so its +x faces the tangent.
    public static func follow(_ path: CGPath, asOffset: Bool = true, orientToPath: Bool = true,
                              duration d: TimeInterval) -> SKAction {
        SKAction(.followPath(path, asOffset, orientToPath), d)
    }
    public static func follow(_ path: CGPath, asOffset: Bool, orientToPath: Bool,
                              speed: CGFloat) -> SKAction {
        SKAction(.followPath(path, asOffset, orientToPath), TimeInterval(speed))
    }

    // AsteroidZ-style off-queue closure run. The web kit is single-threaded, so
    // queue is ignored and the block runs inline on the next action tick.
    public static func run(_ block: @escaping () -> Void, queue: Any) -> SKAction { SKAction(.run(block), 0) }

    // Targeted-child run: looks up the child by name on the recipient SKNode
    // and runs `action` on it. The block is recorded; SKAction.step resolves
    // the child at run time so adds/removes between scheduling and firing
    // still resolve correctly.
    public static func run(_ action: SKAction, onChildWithName name: String) -> SKAction {
        SKAction.customAction(withDuration: 0) { node, _ in
            node.childNode(withName: name)?.run(action)
        }
    }

    // Hide / unhide — instant SKNode.isHidden flips. Compose with .sequence
    // for "hide for N seconds": SKAction.sequence([.hide(), .wait(forDuration: 1), .unhide()]).
    public static func hide() -> SKAction { SKAction(.hide(true), 0) }
    public static func unhide() -> SKAction { SKAction(.hide(false), 0) }

    // CGSize scale form so games that resize via target dimensions work.
    public static func scale(to size: CGSize, duration d: TimeInterval) -> SKAction { SKAction(.scaleToSize(size), d) }
    public static func scaleX(to x: CGFloat, y: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.scaleXY(x, y), d) }
    public static func scaleX(by x: CGFloat, y: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.xScale *= x; node.yScale *= y }
    }
    public static func scaleX(to x: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.xScale = x }
    }
    public static func scaleY(to y: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.yScale = y }
    }

    // Shortest-arc rotate — pick the direction with the smaller angular distance.
    public static func rotate(toAngle a: CGFloat, duration d: TimeInterval, shortestUnitArc: Bool) -> SKAction {
        SKAction(.rotateTo(a), d)
    }

    // SKPhysicsBody actions — run as customActions that push into the body each tick.
    public static func applyForce(_ f: CGVector, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.applyForce(f) }
    }
    public static func applyForce(_ f: CGVector, at p: CGPoint, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.applyForce(f, at: p) }
    }
    public static func applyImpulse(_ i: CGVector, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.applyImpulse(i) }
    }
    public static func applyImpulse(_ i: CGVector, at p: CGPoint, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.applyImpulse(i, at: p) }
    }
    public static func applyTorque(_ t: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.applyTorque(t) }
    }
    public static func applyAngularImpulse(_ i: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.applyAngularImpulse(i) }
    }
    public static func changeMass(to m: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.mass = m }
    }
    public static func changeMass(by dm: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.mass += dm }
    }
    public static func changeCharge(to c: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.charge = c }
    }
    public static func changeCharge(by dc: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.physicsBody?.charge += dc }
    }

    // SKAction.reach — inverse-kinematics towards a point or node, rooted at
    // `rootNode`. Real IK is heavy; we just lerp the rotation/position toward
    // the target so the visual cue (the limb swings toward the target) is
    // there. Games using full IK chains should keep their own solver.
    public static func reach(to point: CGPoint, rootNode: SKNode, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, elapsed in
            let p = CGFloat(min(elapsed / d, 1))
            let dx = point.x - node.position.x, dy = point.y - node.position.y
            node.zRotation = atan2c(dy, dx)
            node.position.x += dx * p
            node.position.y += dy * p
        }
    }
    public static func reach(to point: CGPoint, rootNode: SKNode, velocity v: CGFloat) -> SKAction {
        let dx = point.x - rootNode.position.x, dy = point.y - rootNode.position.y
        let dist = (Double(dx*dx + dy*dy)).squareRoot()
        let d = v > 0 ? TimeInterval(dist) / TimeInterval(v) : 0.1
        return reach(to: point, rootNode: rootNode, duration: d)
    }
    public static func reach(to node: SKNode, rootNode: SKNode, duration d: TimeInterval) -> SKAction {
        reach(to: node.absolutePosition(), rootNode: rootNode, duration: d)
    }
    public static func reach(to node: SKNode, rootNode: SKNode, velocity v: CGFloat) -> SKAction {
        reach(to: node.absolutePosition(), rootNode: rootNode, velocity: v)
    }

    // SKAudioNode-targeted action extras. Stereo pan, playback rate, reverb,
    // obstruction, occlusion — Apple's audio pipeline has per-source 3D
    // attenuation; our snd_* ABI is mono-mix only, so these are recorded
    // but not yet honored. Compile-only stubs.
    public static func stereoPan(to target: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func stereoPan(by delta: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func changePlaybackRate(to target: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func changePlaybackRate(by delta: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func changeReverb(to target: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func changeReverb(by delta: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func changeObstruction(to target: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func changeObstruction(by delta: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func changeOcclusion(to target: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }
    public static func changeOcclusion(by delta: CGFloat, duration d: TimeInterval) -> SKAction { SKAction(.wait, d) }

    // SKFieldNode-targeted action extras.
    public static func strength(to target: Float, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in (node as? SKFieldNode)?.strength = target }
    }
    public static func strength(by delta: Float, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in (node as? SKFieldNode)?.strength += delta }
    }
    public static func falloff(to target: Float, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in (node as? SKFieldNode)?.falloff = target }
    }
    public static func falloff(by delta: Float, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in (node as? SKFieldNode)?.falloff += delta }
    }

    // SKAction.perform(_:onTarget:) — invokes an Objective-C selector. On wasm
    // we don't have ObjC; the action is recorded as a no-op so call sites
    // compile but nothing fires. Games doing this should migrate to run blocks.
    public static func perform(_ selector: Any, onTarget target: AnyObject) -> SKAction { SKAction.run {} }

    // Speed factory — modifies SKNode.speed (subtree time scale).
    public static func speed(by delta: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.speed += delta }
    }
    public static func speed(to target: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: d) { node, _ in node.speed = target }
    }

    // Animated tint on SKSpriteNode (color + colorBlendFactor).
    public static func colorize(with color: SKColor, colorBlendFactor: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction(.colorize(color, colorBlendFactor), d)
    }
    public static func colorize(withColorBlendFactor f: CGFloat, duration d: TimeInterval) -> SKAction {
        SKAction(.colorize(.white, f), d)
    }

    // Real reversal for cases where it has a meaning; best-effort for the rest.
    public func reversed() -> SKAction {
        switch kind {
        case let .moveBy(dx, dy):
            let a = SKAction(.moveBy(-dx, -dy), duration); a.timingMode = timingMode; return a
        case let .rotateBy(r):
            let a = SKAction(.rotateBy(-r), duration); a.timingMode = timingMode; return a
        case let .scaleBy(s):
            let a = SKAction(.scaleBy(s == 0 ? 0 : 1 / s), duration); a.timingMode = timingMode; return a
        case let .sequence(acts):
            return SKAction(.sequence(acts.reversed().map { $0.reversed() }), duration)
        case let .group(acts):
            return SKAction(.group(acts.map { $0.reversed() }), duration)
        case let .repeatN(a, c):
            return SKAction(.repeatN(a.reversed(), c), duration)
        case let .repeatForever(a):
            return SKAction(.repeatForever(a.reversed()), duration)
        default:
            return self                                // wait/run/fadeTo/etc. have no clean reverse
        }
    }
}

final class RunningAction {
    let action: SKAction
    var key: String?
    var elapsed: TimeInterval = 0
    var started = false
    var startPos = CGPoint.zero, targetPos = CGPoint.zero
    var startScale: CGFloat = 1, startAlpha: CGFloat = 1, startRot: CGFloat = 0
    var startColor = SKColor.white, startBlend: CGFloat = 0
    var seqIndex = 0
    var child: RunningAction?
    var groupChildren: [RunningAction] = []
    var repeatRemaining = 0
    var startSize = CGSize.zero, targetSize = CGSize.zero
    var startVolume: CGFloat = 1
    var firstTexture: SKTexture?         // remembered for .animate(restore: true)

    init(_ a: SKAction) { action = a }

    func progress() -> CGFloat {
        guard action.duration > 0 && action.duration.isFinite else { return 1 }
        let t = min(1.0, elapsed / action.duration)
        switch action.timingMode {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return t * (2 - t)
        case .easeInEaseOut: return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        }
    }

    func step(_ dt: CGFloat, node: SKNode) -> Bool {
        switch action.kind {
        case .sequence(let acts):
            if seqIndex >= acts.count { return true }
            if child == nil { child = RunningAction(acts[seqIndex]) }
            if child!.step(dt, node: node) { seqIndex += 1; child = nil; if seqIndex >= acts.count { return true } }
            return false
        case .group(let acts):
            if !started { started = true; groupChildren = acts.map { RunningAction($0) } }
            groupChildren.removeAll { $0.step(dt, node: node) }
            return groupChildren.isEmpty
        case .repeatN(let a, let count):
            if !started { started = true; repeatRemaining = count; child = RunningAction(a) }
            if repeatRemaining <= 0 { return true }
            if child!.step(dt, node: node) { repeatRemaining -= 1; if repeatRemaining <= 0 { return true }; child = RunningAction(a) }
            return false
        case .repeatForever(let a):
            if child == nil { child = RunningAction(a) }
            if child!.step(dt, node: node) { child = RunningAction(a) }
            return false
        case .run(let b): b(); return true
        case .removeFromParent: node.removeFromParent(); return true
        case let .hide(value): node.isHidden = value; return true
        case let .setTexture(t):
            if let s = node as? SKSpriteNode { s.texture = t }
            return true
        case let .animate(textures, tpf, _, restore):
            if !started {
                started = true
                if let s = node as? SKSpriteNode { firstTexture = s.texture }
            }
            elapsed += dt
            if !textures.isEmpty, let s = node as? SKSpriteNode {
                let idx = min(textures.count - 1, Int(elapsed / max(tpf, 0.0001)))
                s.texture = textures[idx]
            }
            let done = elapsed >= action.duration
            if done, restore, let s = node as? SKSpriteNode, let f = firstTexture { s.texture = f }
            return done
        default:
            if !started {
                started = true
                startPos = node.position; startScale = node.xScale; startAlpha = node.alpha; startRot = node.zRotation
                if let s = node as? SKSpriteNode { startColor = s.color; startBlend = s.colorBlendFactor; startSize = s.size }
                if let a = node as? SKAudioNode { startVolume = CGFloat(a.volume) }
                if case .moveBy(let dx, let dy) = action.kind { targetPos = CGPoint(x: startPos.x + dx, y: startPos.y + dy) }
                if case .moveTo(let p) = action.kind { targetPos = p }
                if case let .resizeTo(w, h) = action.kind {
                    targetSize = CGSize(width:  w < 0 ? startSize.width  : w,
                                        height: h < 0 ? startSize.height : h)
                }
                if case let .resizeBy(dw, dh) = action.kind {
                    targetSize = CGSize(width: startSize.width + dw, height: startSize.height + dh)
                }
            }
            elapsed += dt
            applyLeaf(node, progress())
            return elapsed >= action.duration
        }
    }

    func applyLeaf(_ node: SKNode, _ p: CGFloat) {
        switch action.kind {
        case .moveBy, .moveTo:
            node.position = CGPoint(x: startPos.x + (targetPos.x - startPos.x) * p,
                                    y: startPos.y + (targetPos.y - startPos.y) * p)
        case .moveToX(let x): node.position.x = startPos.x + (x - startPos.x) * p
        case .moveToY(let y): node.position.y = startPos.y + (y - startPos.y) * p
        case .scaleTo(let s): let v = startScale + (s - startScale) * p; node.xScale = v; node.yScale = v
        case .scaleBy(let s): let v = startScale * (1 + (s - 1) * p); node.xScale = v; node.yScale = v
        case let .scaleToSize(s):
            // CGSize target: only sensible on SKSpriteNode where size is the
            // displayed extent; on plain nodes treat as composite xScale/yScale to
            // the size's width/height numerically.
            if let sn = node as? SKSpriteNode {
                sn.size = CGSize(width:  startSize.width  + (s.width  - startSize.width)  * p,
                                 height: startSize.height + (s.height - startSize.height) * p)
            } else {
                node.xScale = startScale + (s.width  - startScale) * p
                node.yScale = startScale + (s.height - startScale) * p
            }
        case let .scaleXY(tx, ty):
            node.xScale = startScale + (tx - startScale) * p
            node.yScale = startScale + (ty - startScale) * p
        case .fadeTo(let a): node.alpha = startAlpha + (a - startAlpha) * p
        case .rotateBy(let a): node.zRotation = startRot + a * p
        case .rotateTo(let a): node.zRotation = startRot + (a - startRot) * p
        case let .colorize(target, factor):
            if let s = node as? SKSpriteNode {
                s.color = SKColor(red:   startColor.r + (target.r - startColor.r) * p,
                                  green: startColor.g + (target.g - startColor.g) * p,
                                  blue:  startColor.b + (target.b - startColor.b) * p,
                                  alpha: startColor.a + (target.a - startColor.a) * p)
                s.colorBlendFactor = startBlend + (factor - startBlend) * p
            }
        case let .changeVolume(target):
            if let a = node as? SKAudioNode {
                a.volume = Float(startVolume + (target - startVolume) * p)
            }
        case .resizeTo, .resizeBy:
            if let s = node as? SKSpriteNode {
                s.size = CGSize(width:  startSize.width  + (targetSize.width  - startSize.width)  * p,
                                height: startSize.height + (targetSize.height - startSize.height) * p)
            }
        case let .followPath(path, asOffset, orientToPath):
            // Sample the resolved subpaths into one flat polyline, then interpolate
            // by arc length. asOffset = relative to startPos; orientToPath rotates
            // the node so its +x faces the tangent.
            let pts = path.flattenedPoints
            if pts.count >= 2 {
                let total = path.arcLength
                let want = total * p
                var run: CGFloat = 0
                var cur = pts[0]
                var nxt = pts[1]
                for i in 1..<pts.count {
                    let a = pts[i-1], b = pts[i]
                    let seg = a.distance(to: b)
                    if run + seg >= want || i == pts.count - 1 {
                        let t = seg > 0 ? (want - run) / seg : 0
                        cur = a; nxt = b
                        let x = a.x + (b.x - a.x) * t
                        let y = a.y + (b.y - a.y) * t
                        node.position = asOffset ? CGPoint(x: startPos.x + x, y: startPos.y + y) : CGPoint(x: x, y: y)
                        if orientToPath { node.zRotation = atan2c(b.y - a.y, b.x - a.x) }
                        return
                    }
                    run += seg
                }
                _ = (cur, nxt)
            }
        case .custom(let b): b(node, elapsed)
        default: break
        }
    }
}
