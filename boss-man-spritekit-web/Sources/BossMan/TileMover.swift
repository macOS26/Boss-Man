import SpriteKit

// Time-based tile-stepper shared by Pete and the bosses. Each step takes a
// fixed `step` duration; the lerp parameter is bounded 0..1 so overshoot is
// impossible (which is what produced the vibration when we used a
// distance-per-frame glide with too small a snap threshold).
//
// The pattern mirrors boss-man-spritekit-web-simple's Entity/advance:
//   - When not moving, ask `decide(self)` for the next direction; if walkable,
//     latch a step from current tile to neighbour and start moving.
//   - While moving, drain `moveT` by dt; lerp position from `from` to `to`.
//     On arrival (moveT <= 0) snap to centre, mark not-moving, fire onArrive.
//   - A 8-step guard loop lets one `dt` slice cross multiple tiles when the
//     caller has a queued direction lined up.
//
// Tunnel wrap is detected by the |dx|>1 || |dy|>1 condition on the next tile
// — when GridMap.tunnelPartner returns a coord more than one cell away, we
// teleport instead of interpolating across that distance.
final class TileMover {
    var grid: CGPoint
    var dir: MoveDirection? = nil
    var moveT: TimeInterval = 0
    var moving: Bool = false
    var fromPos = CGPoint.zero
    var toPos   = CGPoint.zero
    var target  = CGPoint.zero
    let node: SKNode
    var step: TimeInterval
    var slowInTunnels: Bool
    var holdTime: TimeInterval = 0   // > 0 = "square" tracks: pause at each tile centre
    private var moveDur: TimeInterval = 0
    private var holding = false
    private var holdT: TimeInterval = 0
    weak var map: GridMap?
    var containerOriginX: CGFloat

    init(node: SKNode, spawn: CGPoint, map: GridMap, step: TimeInterval,
         containerOriginX: CGFloat, slowInTunnels: Bool = false) {
        self.node = node
        self.grid = spawn
        self.map = map
        self.step = step
        self.slowInTunnels = slowInTunnels
        self.containerOriginX = containerOriginX
        self.node.position = centre(of: spawn)
    }

    func centre(of g: CGPoint) -> CGPoint {
        guard let map = map else { return .zero }
        // gridMap.point(for:) already includes the maze's xOffset; the legacy
        // containerOriginX param is kept for call-site compatibility but no
        // longer added here (it would double-offset).
        return map.point(for: g)
    }

    // The same tile after stepping in `d` from `g`, honoring tunnel wrap
    // when the straight-line neighbour isn't walkable but a partner exists.
    func tileAfter(from g: CGPoint, in d: MoveDirection) -> CGPoint {
        let (dx, dy) = d.delta
        var next = CGPoint(x: g.x + CGFloat(dx), y: g.y + CGFloat(dy))
        if let map = map, !map.isWalkable(next), let partner = map.tunnelPartner(of: g) {
            next = partner
        }
        return next
    }

    func canStep(_ d: MoveDirection) -> Bool {
        guard let map = map else { return false }
        let n = tileAfter(from: grid, in: d)
        return map.isWalkable(n)
    }

    func advance(_ dt: TimeInterval,
                 decide: (TileMover) -> MoveDirection?,
                 onArrive: (TileMover) -> Void) {
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
                    (node as? PixelPerson)?.stopWalking()
                    return
                }
                dir = d
                let next = tileAfter(from: grid, in: d)
                guard map.isWalkable(next) else {
                    (node as? PixelPerson)?.stopWalking()
                    return
                }
                (node as? PixelPerson)?.startWalking()
                // Tunnel wrap: snap to the far mouth instead of interpolating
                // across the maze.
                if abs(Int(next.x - grid.x)) > 1 || abs(Int(next.y - grid.y)) > 1 {
                    grid = next
                    node.position = centre(of: next)
                    onArrive(self)
                    continue
                }
                target = next
                fromPos = centre(of: grid)
                toPos   = centre(of: next)
                // bossman-apple BossController: a step that touches a doorway
                // takes 2x as long, so bosses crawl through the tunnels.
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
                    (node as? PixelPerson)?.stopWalking()   // idle pose during the beat
                }
            }
        }
    }
}
