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
    private weak var map: GridMap?

    private(set) var grid: CGPoint
    private var heading: MoveDirection? = nil
    private var moveSpeed: CGFloat = 6.5    // tiles per second; <= Pete's 8.0
    private let tileSize: CGFloat
    private let containerOriginX: CGFloat

    init(blueprintIndex: Int, spawn: CGPoint, map: GridMap, tileSize: CGFloat,
         containerOriginX: CGFloat) {
        self.blueprintIndex = blueprintIndex
        self.map = map
        self.grid = spawn
        self.tileSize = tileSize
        self.containerOriginX = containerOriginX
        self.sprite = SpriteFactory.bossPersonForBlueprint(blueprintIndex)
        self.sprite.position = scenePosition(for: spawn)
        self.sprite.zPosition = 4
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
            // Pick the next direction via BFS.
            if let next = Pathfinder.nextStep(from: grid, to: peteGrid, on: map) {
                let (gx, gy) = (Int(next.x - grid.x), Int(next.y - grid.y))
                heading = MoveDirection.from(delta: (gx, gy))
                if let h = heading { sprite.setFacing(h) }
                grid = next
            } else {
                heading = nil
            }
        } else {
            let invDist = 1.0 / dist
            sprite.position.x += dx * invDist * stepLen
            sprite.position.y += dy * invDist * stepLen
        }
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
