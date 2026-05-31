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
    let nameTag: SKLabelNode
    let blueprintIndex: Int
    let homeGrid: CGPoint
    private weak var map: GridMap?
    let mover: TileMover<MoveDirection>
    let ai: BossAI
    private let sound: SoundManager

    // bossman-apple BossController uses TWO constants: moveInterval (0.36, the
    // total wall-clock time per tile = decision cadence) and moveDuration (0.22,
    // the glide). The pause at each tile centre is the remainder,
    // moveInterval - moveDuration = 0.14. "Square" tracks reproduce that exact
    // 0.22-glide / 0.14-pause cadence; "smooth" keeps a continuous 0.16 glide.
    private static let baseChaseStep: TimeInterval      = 0.16   // smooth-mode continuous glide
    private static let baseFrightenedStep: TimeInterval = 0.22   // flee glide
    private static let moveInterval: TimeInterval       = 0.36   // apple: total per tile (square)
    private static let moveDuration: TimeInterval       = 0.22   // apple: glide per tile (square)
    private let speed: Double
    private let squareTracks: Bool

    private var chaseStep: TimeInterval      { (squareTracks ? Self.moveDuration : Self.baseChaseStep) / speed }
    private var frightenedStep: TimeInterval { Self.baseFrightenedStep / speed }

    private(set) var isFrightened: Bool = false
    // Mirrors bossman-apple's BossController.Entity.isImmobilized — the
    // boss is fading in from its spawn freeze and shouldn't pursue Pete
    // until the freeze timer ends.
    private(set) var isImmobilized: Bool = false

    var grid: CGPoint { mover.grid }

    init(blueprintIndex: Int, spawn: CGPoint, map: GridMap, pathfinder: Pathfinder,
         tileSize: CGFloat, containerOriginX: CGFloat, sound: SoundManager,
         squareTracks: Bool = false, mib: Bool = false) {
        self.blueprintIndex = blueprintIndex
        self.map = map
        self.sound = sound
        self.homeGrid = spawn
        let blueprint = BossBlueprint.table[min(blueprintIndex, BossBlueprint.table.count - 1)]
        // Square runs 15% faster (x1.15 on speed = 15% less per-tile time) while
        // keeping the clean 0.22-glide / 0.14-dwell cadence.
        self.speed = squareTracks ? (blueprint.speed * 1.15) : blueprint.speed
        self.squareTracks = squareTracks
        self.ai = BossAI(homeGrid: spawn, detectionRange: 10,
                         personality: blueprint.personality,
                         pathfinder: pathfinder, map: map)
        self.sprite = SpriteFactory.bossPersonForBlueprint(blueprintIndex, mib: mib)
        self.sprite.zPosition = 4
        // bossman-apple BossController: a Menlo-Bold 9 name tag floats 24pt
        // above the boss (white name normally; the yellow capture-points value
        // in gold-disc flee mode, set by refreshTag).
        let tag = SKLabelNode(fontNamed: Strings.Font.menloBold)
        tag.text = blueprint.name
        tag.fontSize = 9
        tag.fontColor = .white
        tag.position = CGPoint(x: 0, y: 24)
        self.sprite.addChild(tag)
        self.nameTag = tag
        _ = tileSize
        // Square mode glides for moveDuration (0.22); smooth keeps the continuous
        // 0.16. Both scale by the per-boss speed multiplier, matching bossman-apple.
        let chaseGlide = (squareTracks ? Self.moveDuration : Self.baseChaseStep) / speed
        self.mover = TileMover<MoveDirection>(node: sprite, spawn: spawn, map: map,
                               step: chaseGlide,
                               containerOriginX: containerOriginX,
                               slowInTunnels: true)
        // "Square" tracks (bossman-apple / C++ cadence): glide a tile over
        // moveDuration, then dwell moveInterval - moveDuration (= 0.14 at speed
        // 1.0) at its centre. That 0.22/0.14 split per 0.36 tile is what gives the
        // square-by-square step feel. "Smooth" (default) leaves no pause.
        if squareTracks {
            self.mover.holdTime = (Self.moveInterval - Self.moveDuration) / speed
        }
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
            sprite.setShirtOutlineColor(SKColor(white: 1, alpha: 0.75))
            mover.step = frightenedStep
        } else {
            sprite.setBodyColor(sprite.baseBodyColor)
            sprite.setTieColor(sprite.baseTieColor)
            sprite.setTieOutline(color: sprite.baseTieOutlineColor)
            sprite.setEyeColor(.black)
            sprite.setSkinColor(sprite.baseSkinColor)
            sprite.setShirtOutlineColor(.white)
            mover.step = chaseStep
        }
    }

    // bossman-apple refreshTags: show the next-capture value (yellow) above a
    // boss while it's frightened in the gold-disc window, else its name (white).
    func refreshTag(nextPoints: Int) {
        if isFrightened {
            nameTag.text = "\(nextPoints)"
            nameTag.fontColor = .systemYellow
        } else {
            nameTag.text = BossBlueprint.table[min(blueprintIndex, BossBlueprint.table.count - 1)].name
            nameTag.fontColor = .white
        }
    }

    // Internal: reset BossAI + TileMover back to the spawn cell. Sprite
    // visuals (alpha, scale, position) are managed by each public flow
    // separately so capture / relocate / splash can drive their own
    // animations on top of the same underlying state reset.
    private func resetToSpawn() {
        mover.grid    = homeGrid
        mover.dir     = nil
        mover.moving  = false
        mover.moveT   = 0
        ai.teleport(to: homeGrid)
    }

    // bossman-apple: capture(at:) — Pete eats a frightened boss. Plays the
    // signature scale-up + fade-out, snap to home, scale-down + fade-in
    // animation (~0.45s total), then resumes movement. No spawn freeze
    // because the boss should keep fleeing while the gold-disc window is
    // still open.
    //
    // Source: boss-man-spritekit-swift/Boss-Man/BossController.swift:440-484
    func capture() {
        isImmobilized = true
        sprite.removeAllActions()
        let homePoint = mover.centre(of: homeGrid)
        sprite.run(.sequence([
            .group([
                .scale(to: 1.6, duration: 0.25),
                .fadeOut(withDuration: 0.25),
            ]),
            .run { [weak self] in
                guard let self else { return }
                self.sprite.position = homePoint
                self.resetToSpawn()
            },
            .group([
                .scale(to: 1.0, duration: 0.20),
                .fadeIn(withDuration: 0.20),
            ]),
            .run { [weak self] in
                guard let self else { return }
                self.isImmobilized = false
                // Don't touch the palette here. Capture never changes the boss's
                // colors, and the gold-disc events own them: collect sets the
                // flee palette, the wear-off thaw restores the base palette. So
                // the boss stays blue while the window is open and turns red the
                // instant it wears off, with no re-apply (and no double-set).
            },
        ]))
    }

    // bossman-apple: relocateAfterCatch(boss:) — the boss that actually
    // touched Pete goes alpha=0 and snaps to its home tile so Pete can't
    // be caught twice on the same contact. The full spawn-freeze + throb
    // animation that applies to EVERY boss when Pete is caught is run
    // separately via respawnAfterPeteCaught() below, mirroring apple's
    // bossCaughtWorker -> teleportAllToSpawn -> createAndFreeze chain.
    //
    // Source: boss-man-spritekit-swift/Boss-Man/BossController.swift:320 +
    //         GameScene.swift:201-204.
    func relocateAfterCatch() {
        sprite.removeAllActions()
        sprite.alpha = 0
        let homePoint = mover.centre(of: homeGrid)
        sprite.position = homePoint
        resetToSpawn()
        setFrightened(false)
    }

    // bossman-apple: when Pete is caught, GameScene.bossCaughtWorker
    // calls bossController.teleportAllToSpawn(), which re-runs
    // createAndFreeze on every entity — and createAndFreeze ends with
    // applySpawnFreeze, the 1.5s fade-in + 2s immobilized + 3-pulse
    // throb animation. The boss does NOT chase Pete again until the
    // throb sequence completes, giving Pete a clean respawn window.
    //
    // Source: boss-man-spritekit-swift/Boss-Man/BossController.swift:117-133
    //         (createAndFreeze) + 261-263 (teleportAllToSpawn) + 224-250
    //         (applySpawnFreeze).
    func respawnAfterPeteCaught() {
        sprite.removeAllActions()
        sprite.position = mover.centre(of: homeGrid)
        resetToSpawn()
        setFrightened(false)
        applySpawnFreeze()
    }

    // bossman-apple: splash(boss:) — water droplet hit. Boss disappears
    // (alpha 0) and is immobilized for 5 seconds, then respawns via
    // applySpawnFreeze (fade-in + 2s freeze + throb).
    //
    // bossman-apple actually removes the entity entirely and recreates it
    // through createAndFreeze. bossman-web reuses the same BossController
    // instance (we already own the sprite and AI) but matches the visible
    // behaviour: gone for 5s, then full spawn-freeze sequence.
    //
    // Source: boss-man-spritekit-swift/Boss-Man/BossController.swift:486-510.
    func splash() {
        isImmobilized = true
        sprite.removeAllActions()
        sprite.alpha = 0
        setFrightened(false)
        resetToSpawn()
        sprite.position = mover.centre(of: homeGrid)
        sprite.run(.sequence([
            .wait(forDuration: 5.0),
            .run { [weak self] in self?.applySpawnFreeze() }
        ]))
    }

    // bossman-apple's BossController.applySpawnFreeze: fades the sprite in
    // over 1.5s, locks AI (isImmobilized) for 2.0s, then a short throb of
    // 3 scale pulses. Pete cannot capture or be caught by the boss while
    // immobilized — GameScene reads isImmobilized to skip contact checks.
    func applySpawnFreeze() {
        isImmobilized = true
        sound.playTeleport()
        sprite.removeAction(forKey: Strings.ActionKey.spawnFade)
        sprite.removeAction(forKey: Strings.ActionKey.spawnUnfreeze)
        sprite.removeAction(forKey: "spawnThrob")
        sprite.alpha = 0
        sprite.setScale(1.0)
        // bossman-apple plays this 1.5s fade-in, then 2s of immobilized
        // wait, then a 3-pulse throb at scale 1.18. The wasm port runs
        // the throb CONCURRENTLY with the fade-in (and at a larger 1.35
        // scale) so the player can actually see the boss pulsing as it
        // materializes — the original's subtle late-window throb was too
        // easy to miss on the browser-side render path.
        sprite.run(.fadeIn(withDuration: 1.5), withKey: Strings.ActionKey.spawnFade)
        sprite.run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in self?.isImmobilized = false }
        ]), withKey: Strings.ActionKey.spawnUnfreeze)
        let pulse = SKAction.sequence([
            .scale(to: 1.35, duration: 0.22),
            .scale(to: 1.0,  duration: 0.22),
        ])
        sprite.run(.repeat(pulse, count: 5), withKey: "spawnThrob")
    }

    // bossman-apple applyFleeThawTransition: when gold-disc mode ends, play the
    // teleport sound and blink the boss in place (immobilized during the blink),
    // then resume chase. Restores the base palette via setFrightened(false).
    func applyFleeThaw() {
        setFrightened(false)
        sound.playTeleport()
        isImmobilized = true
        sprite.removeAction(forKey: Strings.ActionKey.fleeThaw)
        let blink = SKAction.sequence([
            .fadeAlpha(to: 0.3, duration: 0.3),
            .fadeAlpha(to: 1.0, duration: 0.3)
        ])
        sprite.run(.sequence([
            .repeat(blink, count: 5),
            .run { [weak self] in
                self?.isImmobilized = false
                self?.sprite.alpha = 1
            }
        ]), withKey: Strings.ActionKey.fleeThaw)
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
