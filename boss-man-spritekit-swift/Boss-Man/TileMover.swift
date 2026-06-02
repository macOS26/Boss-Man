import SpriteKit

// Time-based tile-stepper: interpolates a node one grid cell at a time over a
// fixed `step` duration, with the lerp bounded 0..1 so it can't overshoot (a
// distance-per-frame glide with too small a snap threshold vibrated). Reusable
// movement for any SuperBox64 SpriteKit port — the host game supplies its grid,
// direction, and walk animation by conforming to the three protocols below, so
// the stepping/tunnel-wrap/hold logic never has to be reimplemented per game.
//
//   - When not moving, ask decide(self) for the next direction; if walkable,
//     latch a step from the current tile to the neighbour and start moving.
//   - While moving, drain moveT by dt and lerp position from `from` to `to`.
//     On arrival (moveT <= 0) snap to centre, mark not-moving, fire onArrive.
//   - The 8-step guard loop lets one dt slice cross multiple tiles when the
//     caller has a queued direction lined up.
//   - Tunnel wrap (|dx|>1 || |dy|>1 to the next tile) teleports instead of
//     interpolating across the maze.

// The host maze: tile centre, walkability, and tunnel-partner lookup.
public protocol TileMap: AnyObject {
    func point(for grid: CGPoint) -> CGPoint
    func isWalkable(_ grid: CGPoint) -> Bool
    func tunnelPartner(of grid: CGPoint) -> CGPoint?
}

// A movement direction, expressed as a unit grid delta.
public protocol TileDirection {
    var delta: (dx: Int, dy: Int) { get }
}

// A node that animates a walk cycle while stepping (optional — nodes that
// don't conform just don't animate).
public protocol TileWalkAnimating: AnyObject {
    func startWalking()
    func stopWalking()
}

public final class TileMover<D: TileDirection> {
    deinit {}
    public var grid: CGPoint
    public var dir: D? = nil
    public var moveT: TimeInterval = 0
    public var moving: Bool = false
    public var fromPos = CGPoint.zero
    public var toPos   = CGPoint.zero
    public var target  = CGPoint.zero
    public let node: SKNode
    public var step: TimeInterval
    public var tunnelSlowdown: Double
    public var holdTime: TimeInterval = 0   // > 0 = "square" tracks: pause at each tile centre
    public var directions: [D] = []         // candidate headings for direction(toward:)
    private var prog: CGFloat = 0
    private enum StepKind { case normal, enter, exit }
    private var stepKind: StepKind = .normal
    private var holding = false
    private var holdT: TimeInterval = 0
    public weak var map: TileMap?
    public var containerOriginX: CGFloat

    public init(node: SKNode, spawn: CGPoint, map: TileMap, step: TimeInterval,
                containerOriginX: CGFloat, tunnelSlowdown: Double = 1) {
        self.node = node
        self.grid = spawn
        self.map = map
        self.step = step
        self.tunnelSlowdown = tunnelSlowdown
        self.containerOriginX = containerOriginX
        self.node.position = centre(of: spawn)
    }

    public func centre(of g: CGPoint) -> CGPoint {
        guard let map = map else { return .zero }
        return map.point(for: g)
    }

    // The tile reached by stepping `d` from `g`, honoring tunnel wrap when the
    // straight-line neighbour isn't walkable but a partner exists.
    public func tileAfter(from g: CGPoint, in d: D) -> CGPoint {
        let (dx, dy) = d.delta
        var next = CGPoint(x: g.x + CGFloat(dx), y: g.y + CGFloat(dy))
        if let map = map, !map.isWalkable(next), let partner = map.tunnelPartner(of: g) {
            next = partner
        }
        return next
    }

    public func canStep(_ d: D) -> Bool {
        guard let map = map else { return false }
        let n = tileAfter(from: grid, in: d)
        return map.isWalkable(n)
    }

    // Speed as a fraction of full for the active step. A tunnel-entry step ramps
    // full -> slow over its second half; a tunnel-exit step ramps slow -> full
    // over its first half. Everything else runs at full speed.
    private func tunnelSpeedFraction(_ p: CGFloat) -> CGFloat {
        let lo = 1 / CGFloat(tunnelSlowdown)
        switch stepKind {
        case .enter:  return p < 0.5 ? 1 : 1 + (lo - 1) * (p - 0.5) * 2
        case .exit:   return p < 0.5 ? lo + (1 - lo) * p * 2 : 1
        case .normal: return 1
        }
    }

    // Clear all motion state and re-home to a tile. Used by host games on
    // teleport / respawn / capture so the mover doesn't keep gliding from the
    // old cell after the node is snapped elsewhere.
    public func reset(to g: CGPoint) {
        grid = g
        dir = nil
        moving = false
        moveT = 0
        prog = 0
        stepKind = .normal
        holding = false
        holdT = 0
    }

    // The heading whose single step from the current tile lands on `target`,
    // honoring tunnel wrap (tileAfter resolves the far mouth). Lets a
    // target-cell AI hand the mover a destination instead of reconstructing the
    // direction + maze-edge wrap itself. `directions` must be populated.
    public func direction(toward target: CGPoint) -> D? {
        for d in directions where tileAfter(from: grid, in: d) == target { return d }
        return nil
    }

    public func advance(_ dt: TimeInterval,
                        decide: (TileMover<D>) -> D?,
                        onArrive: (TileMover<D>) -> Void) {
        guard let map = map else { return }
        var rem = dt
        var guardCount = 0
        while rem > 0 && guardCount < 8 {
            guardCount += 1
            if holding {
                let s = min(rem, holdT)
                holdT -= s
                rem  -= s
                if holdT > 1e-6 { return }   // still paused at the tile centre
                holding = false
            }
            if !moving {
                guard let d = decide(self) else {
                    dir = nil
                    (node as? TileWalkAnimating)?.stopWalking()
                    return
                }
                dir = d
                let next = tileAfter(from: grid, in: d)
                guard map.isWalkable(next) else {
                    (node as? TileWalkAnimating)?.stopWalking()
                    return
                }
                (node as? TileWalkAnimating)?.startWalking()
                // Tunnel wrap: jump to the far mouth instead of interpolating.
                if abs(Int(next.x - grid.x)) > 1 || abs(Int(next.y - grid.y)) > 1 {
                    grid = next
                    node.position = centre(of: next)
                    onArrive(self)
                    continue
                }
                target = next
                fromPos = centre(of: grid)
                toPos   = centre(of: next)
                prog = 0
                if tunnelSlowdown > 1 && map.tunnelPartner(of: next) != nil {
                    stepKind = .enter
                } else if tunnelSlowdown > 1 && map.tunnelPartner(of: grid) != nil {
                    stepKind = .exit
                } else {
                    stepKind = .normal
                }
                moving = true
            }
            let v = max(0.001, tunnelSpeedFraction(prog))
            let dp = CGFloat(rem / step) * v
            if prog + dp < 1 {
                prog += dp
                rem = 0
            } else {
                rem = max(0, rem - Double((1 - prog) / v) * step)
                prog = 1
            }
            node.position = CGPoint(x: fromPos.x + (toPos.x - fromPos.x) * prog,
                                    y: fromPos.y + (toPos.y - fromPos.y) * prog)
            if prog >= 1 {
                grid = target
                node.position = toPos
                moving = false
                onArrive(self)
                if holdTime > 0 {
                    holding = true
                    holdT = holdTime
                    (node as? TileWalkAnimating)?.stopWalking()   // idle pose during the beat
                }
            }
        }
    }
}

extension GridMap: TileMap {}
extension MoveDirection: TileDirection {}
extension PixelPerson: TileWalkAnimating {}
