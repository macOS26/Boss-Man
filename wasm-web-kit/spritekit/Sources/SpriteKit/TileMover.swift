import KitABI

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
    public var grid: CGPoint
    public var dir: D? = nil
    public var moveT: TimeInterval = 0
    public var moving: Bool = false
    public var fromPos = CGPoint.zero
    public var toPos   = CGPoint.zero
    public var target  = CGPoint.zero
    public let node: SKNode
    public var step: TimeInterval
    public var slowInTunnels: Bool
    public var holdTime: TimeInterval = 0   // > 0 = "square" tracks: pause at each tile centre
    private var moveDur: TimeInterval = 0
    private var holding = false
    private var holdT: TimeInterval = 0
    public weak var map: TileMap?
    public var containerOriginX: CGFloat

    public init(node: SKNode, spawn: CGPoint, map: TileMap, step: TimeInterval,
                containerOriginX: CGFloat, slowInTunnels: Bool = false) {
        self.node = node
        self.grid = spawn
        self.map = map
        self.step = step
        self.slowInTunnels = slowInTunnels
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
                // Tunnel wrap: snap to the far mouth instead of interpolating.
                if abs(Int(next.x - grid.x)) > 1 || abs(Int(next.y - grid.y)) > 1 {
                    grid = next
                    node.position = centre(of: next)
                    onArrive(self)
                    continue
                }
                target = next
                fromPos = centre(of: grid)
                toPos   = centre(of: next)
                // A step touching a doorway takes 2x as long, so movers crawl
                // through the tunnels.
                let touchesDoorway = map.tunnelPartner(of: grid) != nil
                                  || map.tunnelPartner(of: next) != nil
                moveDur = (slowInTunnels && touchesDoorway) ? step * 2 : step
                moveT = moveDur
                moving = true
            }
            let s = min(rem, moveT)
            moveT -= s
            rem -= s
            let t = CGFloat(max(0, min(1, 1 - moveT / moveDur)))
            node.position = CGPoint(x: fromPos.x + (toPos.x - fromPos.x) * t,
                                    y: fromPos.y + (toPos.y - fromPos.y) * t)
            if moveT <= 1e-6 {
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
