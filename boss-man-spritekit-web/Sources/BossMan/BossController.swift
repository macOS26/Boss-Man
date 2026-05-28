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
    let ai: BossAI

    // Base step at speed 1.0. Per-personality speed scales this (matches
    // bossman-apple's moveInterval/moveDuration division by blueprint speed).
    private let baseChaseStep: TimeInterval     = 0.16
    private let baseFrightenedStep: TimeInterval = 0.22
    private let speed: Double

    private var chaseStep: TimeInterval     { baseChaseStep / speed }
    private var frightenedStep: TimeInterval { baseFrightenedStep / speed }

    private(set) var isFrightened: Bool = false
    // Mirrors bossman-apple's BossController.Entity.isImmobilized — the
    // boss is fading in from its spawn freeze and shouldn't pursue Pete
    // until the freeze timer ends.
    private(set) var isImmobilized: Bool = false

    var grid: CGPoint { mover.grid }

    init(blueprintIndex: Int, spawn: CGPoint, map: GridMap, pathfinder: Pathfinder,
         tileSize: CGFloat, containerOriginX: CGFloat) {
        self.blueprintIndex = blueprintIndex
        self.map = map
        self.homeGrid = spawn
        let blueprint = BossBlueprint.table[min(blueprintIndex, BossBlueprint.table.count - 1)]
        self.speed = blueprint.speed
        self.ai = BossAI(homeGrid: spawn, detectionRange: 10,
                         personality: blueprint.personality,
                         pathfinder: pathfinder, map: map)
        self.sprite = SpriteFactory.bossPersonForBlueprint(blueprintIndex)
        self.sprite.zPosition = 4
        _ = tileSize
        self.mover = TileMover(node: sprite, spawn: spawn, map: map,
                               step: baseChaseStep / blueprint.speed,
                               containerOriginX: containerOriginX)
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
            sprite.setTieOutline(color: nil)
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
        // Reset AI back to spawn with previousGrid cleared (matches
        // BossAI.teleport semantics in bossman-apple's relocateToSpawn).
        ai.teleport(to: homeGrid)
        setFrightened(false)
        applySpawnFreeze()
    }

    // bossman-apple's BossController.applySpawnFreeze: fades the sprite in
    // over 1.5s, locks AI (isImmobilized) for 2.0s, then a short throb of
    // 3 scale pulses. Pete cannot capture or be caught by the boss while
    // immobilized — GameScene reads isImmobilized to skip contact checks.
    func applySpawnFreeze() {
        isImmobilized = true
        sprite.removeAction(forKey: Strings.ActionKey.spawnFade)
        sprite.removeAction(forKey: Strings.ActionKey.spawnUnfreeze)
        sprite.alpha = 0
        sprite.setScale(1.0)
        sprite.run(.fadeIn(withDuration: 1.5), withKey: Strings.ActionKey.spawnFade)
        sprite.run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in self?.isImmobilized = false }
        ]), withKey: Strings.ActionKey.spawnUnfreeze)
        let pulse = SKAction.sequence([
            .scale(to: 1.18, duration: 0.16),
            .scale(to: 1.0,  duration: 0.17),
        ])
        sprite.run(.sequence([
            .wait(forDuration: 2.0),
            .repeat(pulse, count: 3),
        ]))
    }

    func install(in scene: SKNode) { scene.addChild(sprite) }

    func step(dt: TimeInterval, peteGrid: CGPoint, peteDirection: MoveDirection?, blinkyGrid: CGPoint?) {
        guard let map = map, !isImmobilized else { return }
        let frightened = isFrightened
        let cols = map.columnCount
        let rows = map.rowCount
        mover.advance(dt,
                      decide: { [weak self] e in
                          guard let self else { return nil }
                          // AI owns its grid + previousGrid; do NOT call
                          // teleport here (it would wipe previousGrid every
                          // tile and let randomStep U-turn, which is what
                          // froze the boss when Pete was hiding). AI.grid
                          // tracks naturally because planNextStep advances
                          // it to the same `to` cell the mover targets.
                          guard let move = self.ai.planNextStep(
                              workerGrid: peteGrid,
                              workerDirection: peteDirection,
                              blinkyGrid: blinkyGrid,
                              flee: frightened
                          ) else { return nil }
                          let dx = Int(move.to.x - e.grid.x)
                          let dy = Int(move.to.y - e.grid.y)
                          // Tunnel wrap: planNextStep may return the far
                          // mouth (delta > 1). Convert that into the local
                          // direction the boss must face to step off the
                          // maze edge; mover.tileAfter does the teleport.
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
                          if let d = e.dir { self.sprite.setFacing(d) }
                      })
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
