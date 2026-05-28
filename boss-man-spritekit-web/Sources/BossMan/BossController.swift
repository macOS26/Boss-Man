import SpriteKit

// One boss in the maze. Owns a PixelPerson sprite + a TileMover; the mover
// owns the actual position/grid/lerp state, and we drive it from GameScene
// via step(dt:peteGrid:). On each tile arrival the decide() closure asks
// Pathfinder (chase) or fleeStep (frighten) for the neighbour to walk to,
// converts the delta back into a MoveDirection, and hands it to the mover —
// which interpolates one tile over `mover.step` seconds with the lerp
// parameter bounded 0..1. No distance-vs-stepLen comparison, so the boss
// can't vibrate around tile centres the way the old glide loop did.
final class BossController {
    let sprite: PixelPerson
    let blueprintIndex: Int
    let homeGrid: CGPoint
    private weak var map: GridMap?
    let mover: TileMover

    private let chaseStep: TimeInterval     = 0.16    // ~6.25 tiles/s
    private let frightenedStep: TimeInterval = 0.22   // ~4.5 tiles/s

    private(set) var isFrightened: Bool = false
    // Last tile the boss left, so the random-wander fallback doesn't U-turn
    // every step. Matches bossman-apple's BossAI.previousGrid.
    private var previousGrid: CGPoint? = nil

    var grid: CGPoint { mover.grid }

    init(blueprintIndex: Int, spawn: CGPoint, map: GridMap, tileSize: CGFloat,
         containerOriginX: CGFloat) {
        self.blueprintIndex = blueprintIndex
        self.map = map
        self.homeGrid = spawn
        self.sprite = SpriteFactory.bossPersonForBlueprint(blueprintIndex)
        self.sprite.zPosition = 4
        _ = tileSize
        self.mover = TileMover(node: sprite, spawn: spawn, map: map,
                               step: chaseStep, containerOriginX: containerOriginX)
    }

    // Mirrors bossman-apple: mutate the body / tie / tie-outline / eye
    // colors in place so the boss reads as the classic frightened-blue
    // figure with a gold-trimmed yellow tie. Restores the per-blueprint
    // base palette captured by PixelPerson at init when the timer ends.
    func setFrightened(_ on: Bool) {
        if on == isFrightened { return }
        isFrightened = on
        if on {
            sprite.setBodyColor(SpriteFactory.fleeBodyColor)
            sprite.setTieColor(SpriteFactory.fleeTieColor)
            sprite.setTieOutline(color: SpriteFactory.bossShoeGoldColor)
            sprite.setEyeColor(SpriteFactory.fleeEyeColor)
            sprite.setSkinColor(SpriteFactory.fleeSkinColor)
            mover.step = frightenedStep
        } else {
            sprite.setBodyColor(sprite.baseBodyColor)
            sprite.setTieColor(sprite.baseTieColor)
            sprite.setTieOutline(color: nil)
            sprite.setEyeColor(.black)
            sprite.setSkinColor(sprite.baseSkinColor)
            mover.step = chaseStep
        }
    }

    func returnHome() {
        mover.grid    = homeGrid
        mover.dir     = nil
        mover.moving  = false
        mover.moveT   = 0
        sprite.position = mover.centre(of: homeGrid)
        setFrightened(false)
    }

    func install(in scene: SKNode) { scene.addChild(sprite) }

    func step(dt: TimeInterval, peteGrid: CGPoint) {
        guard let map = map else { return }
        let frightened = isFrightened
        let cols = map.columnCount
        let rows = map.rowCount
        mover.advance(dt,
                      decide: { [weak self] e in
                          guard let self else { return nil }
                          // Chase / flee / wander, in that order. When Pete
                          // is unreachable (e.g. sitting in a hideout) BFS
                          // returns nil; we fall back to a random walkable
                          // step so the boss keeps wandering instead of
                          // freezing in place. Matches bossman-apple's
                          // BossAI.planNextStep: shortestStep ?? random.
                          let next: CGPoint?
                          if frightened {
                              next = Self.fleeStep(from: e.grid, away: peteGrid, on: map)
                                  ?? self.randomStep(from: e.grid, on: map)
                          } else {
                              next = Pathfinder.nextStep(from: e.grid, to: peteGrid, on: map)
                                  ?? self.randomStep(from: e.grid, on: map)
                          }
                          guard let nxt = next else { return nil }
                          let dx = Int(nxt.x - e.grid.x)
                          let dy = Int(nxt.y - e.grid.y)
                          // Tunnel wrap: BFS may return the far mouth (delta > 1).
                          // Translate that back into the local direction the boss
                          // must face to step OFF the maze edge; the mover's
                          // tileAfter() converts that into the partner teleport.
                          if abs(dx) > 1 {
                              return e.grid.x < CGFloat(cols) / 2 ? .left : .right
                          }
                          if abs(dy) > 1 {
                              return e.grid.y < CGFloat(rows) / 2 ? .down : .up
                          }
                          return MoveDirection.from(delta: (dx, dy))
                      },
                      onArrive: { [weak self] e in
                          guard let self else { return }
                          self.previousGrid = e.grid
                          if let d = e.dir { self.sprite.setFacing(d) }
                      })
    }

    // Pick a random walkable neighbour, avoiding the cell we just came from
    // when we have a real choice (so the boss doesn't oscillate on the spot).
    private func randomStep(from grid: CGPoint, on map: GridMap) -> CGPoint? {
        var options = map.walkableNeighbors(of: grid)
        if let prev = previousGrid, options.count > 1 {
            options.removeAll { $0 == prev }
        }
        return options.randomElement()
    }

    // Pick the walkable neighbour that maximises BFS distance from Pete.
    private static func fleeStep(from start: CGPoint, away pete: CGPoint, on map: GridMap) -> CGPoint? {
        var best: CGPoint?
        var bestDist = -1
        for n in map.walkableNeighbors(of: start) {
            let d = approxBFSDistance(from: n, to: pete, on: map, cap: 24)
            if d > bestDist { bestDist = d; best = n }
        }
        return best
    }

    // BFS distance capped to keep flee evaluation cheap (one call per boss
    // per tile-centre arrival). cap=24 covers most reasonable maze distances.
    private static func approxBFSDistance(from start: CGPoint, to target: CGPoint, on map: GridMap, cap: Int) -> Int {
        if start == target { return 0 }
        var queue: [(CGPoint, Int)] = [(start, 0)]
        var visited = Set<CGPoint>([start])
        while !queue.isEmpty {
            let (node, dist) = queue.removeFirst()
            if dist >= cap { return cap }
            for n in map.walkableNeighbors(of: node) where !visited.contains(n) {
                if n == target { return dist + 1 }
                visited.insert(n)
                queue.append((n, dist + 1))
            }
        }
        return cap
    }
}

// Grid-delta -> MoveDirection. -1/0/+1 only; tunnel-wrap deltas are caught
// by the caller above before they reach this.
extension MoveDirection {
    static func from(delta: (Int, Int)) -> MoveDirection? {
        switch delta {
        case (-1, 0): return .left
        case ( 1, 0): return .right
        case ( 0,-1): return .down
        case ( 0, 1): return .up
        default: return nil
        }
    }
}
