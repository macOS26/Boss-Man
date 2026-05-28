import SpriteKit

// One boss in the maze. Spawns a PixelPerson at the assigned tile and walks
// tile-by-tile through the grid, asking Pathfinder for the next step toward
// Pete on every tile-centre arrival. Movement is interpolated between tile
// centres at a constant speed (slightly slower than Pete so the player has a
// fighting chance).
//
// First wasm pass keeps the behaviour single-mode (always chase). The macOS
// original switches between scatter / chase / frightened on the power-pellet
// timer; that lands once the gold-disc shield loop ships.
final class BossController {
    let sprite: PixelPerson
    let blueprintIndex: Int
    let homeGrid: CGPoint
    private weak var map: GridMap?

    private(set) var grid: CGPoint
    private var heading: MoveDirection? = nil
    private var moveSpeed: CGFloat = 6.5    // tiles per second; <= Pete's 8.0
    private let tileSize: CGFloat
    private let containerOriginX: CGFloat

    // Frighten mode: when true, the boss runs AWAY from Pete and renders
    // with a blue tint. The flag is owned by GameScene and pushed in via
    // setFrightened(_:); BossController doesn't keep its own timer so the
    // GameScene can apply one window across every boss at once.
    private(set) var isFrightened: Bool = false
    private var frightenedTint: SKShapeNode? = nil

    init(blueprintIndex: Int, spawn: CGPoint, map: GridMap, tileSize: CGFloat,
         containerOriginX: CGFloat) {
        self.blueprintIndex = blueprintIndex
        self.map = map
        self.grid = spawn
        self.homeGrid = spawn
        self.tileSize = tileSize
        self.containerOriginX = containerOriginX
        self.sprite = SpriteFactory.bossPersonForBlueprint(blueprintIndex)
        self.sprite.position = scenePosition(for: spawn)
        self.sprite.zPosition = 4
    }

    func setFrightened(_ on: Bool) {
        if on == isFrightened { return }
        isFrightened = on
        if on {
            let tint = SKShapeNode(circleOfRadius: 9)
            tint.fillColor = SKColor(red: 0.15, green: 0.35, blue: 0.95, alpha: 0.65)
            tint.strokeColor = .clear
            tint.zPosition = 1
            sprite.addChild(tint)
            frightenedTint = tint
            moveSpeed = 4.5
        } else {
            frightenedTint?.removeFromParent()
            frightenedTint = nil
            moveSpeed = 6.5
        }
    }

    func returnHome() {
        grid = homeGrid
        sprite.position = scenePosition(for: homeGrid)
        heading = nil
        setFrightened(false)
    }

    func install(in scene: SKNode) { scene.addChild(sprite) }

    // Move toward the current tile centre; on arrival, ask the pathfinder for
    // the next step toward Pete and update the heading. Returns the boss's
    // updated scene-space position so the caller can run contact checks.
    func step(dt: TimeInterval, peteGrid: CGPoint) {
        guard let map else { return }
        let stepLen = moveSpeed * tileSize * CGFloat(dt)
        let target = scenePosition(for: grid)
        let dx = target.x - sprite.position.x
        let dy = target.y - sprite.position.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist < 0.5 {
            sprite.position = target
            // Tunnel wrap.
            if let partner = map.tunnelPartner(of: grid) {
                grid = partner
                sprite.position = scenePosition(for: partner)
            }
            // Pick the next direction. Chase mode uses BFS toward Pete; in
            // frighten mode we still BFS, but choose the neighbour that
            // maximises BFS distance from Pete so the boss flees.
            let next: CGPoint?
            if isFrightened {
                next = fleeStep(from: grid, away: peteGrid, on: map)
            } else {
                next = Pathfinder.nextStep(from: grid, to: peteGrid, on: map)
            }
            if let nxt = next {
                let (gx, gy) = (Int(nxt.x - grid.x), Int(nxt.y - grid.y))
                heading = MoveDirection.from(delta: (gx, gy))
                if let h = heading { sprite.setFacing(h) }
                grid = nxt
            } else {
                heading = nil
            }
        } else {
            let invDist = 1.0 / dist
            sprite.position.x += dx * invDist * stepLen
            sprite.position.y += dy * invDist * stepLen
        }
    }

    // Pick the walkable neighbour that maximises BFS distance from Pete.
    // Falls back to any walkable neighbour when no path data is available.
    private func fleeStep(from start: CGPoint, away pete: CGPoint, on map: GridMap) -> CGPoint? {
        var best: CGPoint?
        var bestDist = -1
        for n in map.walkableNeighbors(of: start) {
            let d = approxBFSDistance(from: n, to: pete, on: map, cap: 24)
            if d > bestDist { bestDist = d; best = n }
        }
        return best
    }
    // BFS distance capped at `cap` to keep flee evaluation cheap (we run it
    // per boss per tile-centre arrival). cap=24 covers most reasonable maze
    // distances; anything farther is "definitely safe".
    private func approxBFSDistance(from start: CGPoint, to target: CGPoint, on map: GridMap, cap: Int) -> Int {
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

    private func scenePosition(for g: CGPoint) -> CGPoint {
        guard let map else { return .zero }
        let local = map.point(for: g)
        return CGPoint(x: local.x + containerOriginX, y: local.y)
    }
}

// Small helper because MoveDirection's init(keyCode:) is the only public
// constructor on the user-facing side; bosses need to convert grid deltas
// (potentially -1, 0, +1) back to a MoveDirection.
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
