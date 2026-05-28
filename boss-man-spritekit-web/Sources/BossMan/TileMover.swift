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
    weak var map: GridMap?
    var containerOriginX: CGFloat

    init(node: SKNode, spawn: CGPoint, map: GridMap, step: TimeInterval, containerOriginX: CGFloat) {
        self.node = node
        self.grid = spawn
        self.map = map
        self.step = step
        self.containerOriginX = containerOriginX
        self.node.position = centre(of: spawn)
    }

    func centre(of g: CGPoint) -> CGPoint {
        guard let map = map else { return .zero }
        let local = map.point(for: g)
        return CGPoint(x: local.x + containerOriginX, y: local.y)
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
                moveT = step
                moving = true
            }
            let s = min(rem, moveT)
            moveT -= s
            rem -= s
            let t = CGFloat(max(0, min(1, 1 - moveT / step)))
            node.position = CGPoint(x: fromPos.x + (toPos.x - fromPos.x) * t,
                                    y: fromPos.y + (toPos.y - fromPos.y) * t)
            if moveT <= 1e-6 {
                grid = target
                node.position = toPos
                moving = false
                onArrive(self)
            }
        }
    }
}
