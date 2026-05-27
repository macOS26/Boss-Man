public enum SKActionTimingMode { case linear, easeIn, easeOut, easeInEaseOut }

public final class SKAction {
    enum Kind {
        case moveBy(CGFloat, CGFloat), moveTo(CGPoint), moveToX(CGFloat), moveToY(CGFloat)
        case scaleTo(CGFloat), scaleBy(CGFloat), fadeTo(CGFloat)
        case rotateBy(CGFloat), rotateTo(CGFloat)
        case wait, run(() -> Void), custom((SKNode, CGFloat) -> Void)
        case sequence([SKAction]), group([SKAction]), repeatN(SKAction, Int), repeatForever(SKAction)
        case removeFromParent
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
}

final class RunningAction {
    let action: SKAction
    var key: String?
    var elapsed: TimeInterval = 0
    var started = false
    var startPos = CGPoint.zero, targetPos = CGPoint.zero
    var startScale: CGFloat = 1, startAlpha: CGFloat = 1, startRot: CGFloat = 0
    var seqIndex = 0
    var child: RunningAction?
    var groupChildren: [RunningAction] = []
    var repeatRemaining = 0

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
        default:
            if !started {
                started = true
                startPos = node.position; startScale = node.xScale; startAlpha = node.alpha; startRot = node.zRotation
                if case .moveBy(let dx, let dy) = action.kind { targetPos = CGPoint(x: startPos.x + dx, y: startPos.y + dy) }
                if case .moveTo(let p) = action.kind { targetPos = p }
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
        case .fadeTo(let a): node.alpha = startAlpha + (a - startAlpha) * p
        case .rotateBy(let a): node.zRotation = startRot + a * p
        case .rotateTo(let a): node.zRotation = startRot + (a - startRot) * p
        case .custom(let b): b(node, elapsed)
        default: break
        }
    }
}
