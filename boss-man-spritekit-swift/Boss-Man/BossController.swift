import AppKit
import SpriteKit

@MainActor
protocol BossControllerDelegate: AnyObject {
    var workerGrid: CGPoint { get }
    var workerDirection: MoveDirection? { get }
    var isGoldDiscMode: Bool { get }
    var isPeteShielded: Bool { get }
    func bossDidCatchWorker()
    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint)
    // Travel axis of a water droplet bearing down on a boss at `grid` (nil if
    // none); the boss steps perpendicular to dodge it.
    func dropletAxisThreatening(_ grid: CGPoint) -> MoveDirection?
}

@MainActor
final class BossController {
    struct Entity {
        let name: String
        let baseColor: NSColor
        let tieColor: NSColor
        let pantsColor: NSColor
        let spawn: CGPoint
        let ai: BossAI
        let node: PixelPerson
        let tag: SKLabelNode
        let moveInterval: TimeInterval
        let moveDuration: TimeInterval
        var lastMove: TimeInterval
        var isInFleeMode: Bool = false
        var captureCount: Int = 0
        var isImmobilized: Bool = false
        let blueprintIndex: Int
        var mover: TileMover<MoveDirection>! = nil
        var frightenedStep: TimeInterval = 0
        var spawnGrace: TimeInterval = 0
    }

    // The `spawn` slot here is a placeholder (.zero) only. A boss's home/spawn
    // position comes exclusively from the level map ('1'..'4' tiles) via
    // spawnOverrides — home lives in level data, never in code. The slot is kept
    // because the override writes the real position into it before each entity is
    // built. (A hardcoded home here once let a tile-less level spawn Bill at a
    // fixed corner.)
    // name/personality/speed + the body/tie palette come from the shared
    // BossBlueprint (common with the wasm port); apple layers the pants color +
    // spawn slot on top.
    private static let blueprints: [(name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double)] =
        BossBlueprint.table.enumerated().map { i, bp in
            (name: bp.name, color: BossBlueprint.colors[i].body, tie: BossBlueprint.colors[i].tie,
             pants: .darkGray, spawn: .zero, personality: bp.personality, speed: bp.speed)
        }

    private let moveInterval: TimeInterval = 0.36
    private let moveDuration: TimeInterval = 0.22
    private let detectionRange: CGFloat = 10

    static let baseSkinColor: NSColor = NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.62, alpha: 1)
    static var bossShoeGoldColor: NSColor { SpriteFactory.bossShoeGoldColor }

    weak var delegate: BossControllerDelegate?
    private weak var scene: SKScene?
    private let gridMap: GridMap
    private let pathfinder: Pathfinder
    private let sound: SoundManager
    private let containerOriginX: CGFloat
    private(set) var entities: [Entity] = []
    private var captureStreak = 0
    private var currentLevel = 1

    var hasFirstBoss: Bool { !entities.isEmpty }
    var firstBossGrid: CGPoint? { entities.first?.ai.grid }
    // True while any boss is still flashing in (fading + throbbing during its
    // spawnGrace). Drives Pete's spawn shield so both go live together.
    var isAnyBossSpawning: Bool { entities.contains { $0.spawnGrace > 0 } }

    init(scene: SKScene, gridMap: GridMap, pathfinder: Pathfinder, sound: SoundManager, containerOriginX: CGFloat = 0) {
        self.scene = scene
        self.sound = sound
        self.gridMap = gridMap
        self.pathfinder = pathfinder
        self.containerOriginX = containerOriginX
    }

    // MARK: - Roster lifecycle
    func spawn(forLevel level: Int, spawnOverrides: [(blueprintIndex: Int, position: CGPoint)] = []) {
        clear()
        currentLevel = level
        currentSpawnOverrides = spawnOverrides
        // Boss home positions come exclusively from the level map (the '1'..'4'
        // tiles parsed into spawnOverrides). There is intentionally no hardcoded
        // fallback: a boss with no tile in the level simply does not spawn, and
        // every respawn path reuses the per-entity spawn set here — so home
        // always lives in the level data, never in code.
        for (index, position) in spawnOverrides {
            guard index >= 0, index < Self.blueprints.count else { continue }
            var blueprint = Self.blueprints[index]
            blueprint.spawn = position
            createAndFreeze(from: themed(blueprint, level: level), blueprintIndex: index)
        }
    }

    private var currentSpawnOverrides: [(blueprintIndex: Int, position: CGPoint)] = []

    // Loop-driven respawns for splashed bosses (the C++ master's respawnTimer).
    // An SKAction .wait+.run fires unreliably on wasm — a splashed boss would
    // respawn late, looking spontaneous "from before" — so count down in advance.
    private struct PendingSpawn { let blueprintIndex: Int; let spawn: CGPoint; var timer: TimeInterval }
    private var pendingSpawns: [PendingSpawn] = []

    private func themed(_ blueprint: (name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double), level: Int) -> (name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double) {
        guard isMIBLevel(level) else { return blueprint }
        return (
            name: blueprint.name,
            color: .black,
            tie: .black,
            pants: .black,
            spawn: blueprint.spawn,
            personality: blueprint.personality,
            speed: blueprint.speed
        )
    }

    private func isMIBLevel(_ level: Int) -> Bool { level % 12 == 0 }

    private func createAndFreeze(from blueprint: (name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double), blueprintIndex: Int, goldDiscActive: Bool = false) {
        buildEntity(from: blueprint, blueprintIndex: blueprintIndex)
        let index = entities.count - 1
        if goldDiscActive {
            entities[index].isInFleeMode = true
            let node = entities[index].node
            node.setBodyColor(SpriteFactory.fleeBodyColor)
            node.setTieColor(SpriteFactory.fleeTieColor)
            node.setTieOutline(color: nil)
            node.setShirtOutlineColor(NSColor(calibratedWhite: 1, alpha: 0.75))
            node.setShoeOutlineColor(Self.bossShoeGoldColor)
            node.setEyeColor(SpriteFactory.fleeEyeColor)
            node.setSkinColor(SpriteFactory.fleeSkinColor)
            entities[index].mover?.step = entities[index].frightenedStep
        }
        applySpawnFreeze(at: index)
        if goldDiscActive { refreshTags(goldDiscActive: true) }
    }

    private func buildEntity(from blueprint: (name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double), blueprintIndex: Int) {
        guard let scene else { return }
        let ai = BossAI(
            homeGrid: blueprint.spawn,
            detectionRange: detectionRange,
            personality: blueprint.personality,
            pathfinder: pathfinder,
            map: gridMap
        )
        ai.teleport(to: blueprint.spawn)

        let node = SpriteFactory.bossPerson(
            bodyColor: blueprint.color,
            tieColor: blueprint.tie,
            wearsSunglasses: isMIBLevel(currentLevel)
        )
        node.name = blueprint.name
        node.position = gridMap.point(for: blueprint.spawn)
        // r=5 so a catch needs a deeper overlap with Pete (Pete's body is 10,
        // contact fires at centres ~15px apart), not the barely-touching overlap
        // that r=10 (20px) gave.
        node.physicsBody = SKPhysicsBody(circleOfRadius: 10)
        node.physicsBody?.allowsRotation = false
        // Dynamic sensor: a Box2D contact needs one dynamic body in the pair, so
        // dynamic + collisionBitMask 0 lets boss/worker contacts fire (the catch
        // backup) without any collision response to fight TileMover.
        node.physicsBody?.isDynamic = true
        node.physicsBody?.categoryBitMask = PhysicsCategory.boss
        node.physicsBody?.contactTestBitMask = PhysicsCategory.worker | PhysicsCategory.waterDroplet
        node.physicsBody?.collisionBitMask = 0
        node.zPosition = 11
        scene.addChild(node)

        let tagScale: CGFloat = 8
        let tag = SKLabelNode(fontNamed: Strings.Font.menloBold)
        tag.text = blueprint.name
        tag.fontSize = 9 * tagScale
        tag.fontColor = .white
        tag.setScale(1 / tagScale)
        tag.position = CGPoint(x: 0, y: 24)
        node.addChild(tag)

        // Boss Tracks setting (title screen). "Square" (default) is the classic
        // glide-then-dwell cadence (0.36 interval / 0.22 glide => 0.14 dwell per
        // tile). "Smooth" is a continuous glide with no centre dwell. Absent key
        // defaults to Square.
        let square = Persistence.bool(forKey: Strings.DefaultsKey.bossTracksSquare, default: true)
        // Square runs 15% faster (x1.15 on speed = 15% less per-tile time) while
        // keeping the clean 0.22-glide / 0.14-dwell cadence.
        let speed = square ? (blueprint.speed * 1.15) : blueprint.speed
        let entityInterval = (square ? moveInterval : 0.16) / speed
        let entityDuration = (square ? moveDuration : 0.16) / speed

        let entity = Entity(
            name: blueprint.name,
            baseColor: blueprint.color,
            tieColor: blueprint.tie,
            pantsColor: blueprint.pants,
            spawn: blueprint.spawn,
            ai: ai,
            node: node,
            tag: tag,
            moveInterval: entityInterval,
            moveDuration: entityDuration,
            lastMove: 0,
            blueprintIndex: blueprintIndex
        )
        entities.append(entity)

        let idx = entities.count - 1
        let mover = TileMover<MoveDirection>(node: node, spawn: blueprint.spawn, map: gridMap,
                                             step: entityDuration, containerOriginX: containerOriginX,
                                             tunnelSlowdown: 8)
        mover.directions = MoveDirection.allCases
        let hold = entityInterval - entityDuration
        if hold > 0 { mover.holdTime = hold }
        entities[idx].mover = mover
        entities[idx].frightenedStep = 0.22 / speed
    }

    private func relocateToSpawn(at index: Int) {
        let entity = entities[index]
        let node = entity.node
        node.removeAllActions()
        node.stopWalking()
        entity.ai.teleport(to: entity.spawn)
        node.position = gridMap.point(for: entity.spawn)
        entity.mover?.reset(to: entity.spawn)
        node.setBodyColor(entity.baseColor)
        node.setTieColor(entity.tieColor)
        node.setTieOutline(color: nil)
        node.setShirtOutlineColor(.white)
        node.setShoeOutlineColor(Self.bossShoeGoldColor)
        node.setEyeColor(.black)
        node.setSkinColor(Self.baseSkinColor)
        entities[index].captureCount = 0
        entities[index].isInFleeMode = false
    }

    private func rebuildEntity(at index: Int) {
        let blueprintIndex = entities[index].blueprintIndex
        let spawn = entities[index].spawn
        entities[index].node.alpha = 0
        entities[index].node.removeAllActions()
        entities[index].node.removeFromParent()
        entities.remove(at: index)
        guard blueprintIndex >= 0, blueprintIndex < Self.blueprints.count else { return }
        var blueprint = Self.blueprints[blueprintIndex]
        blueprint.spawn = spawn
        createAndFreeze(from: themed(blueprint, level: currentLevel), blueprintIndex: blueprintIndex)
    }

    private func applySpawnFreeze(at index: Int) {
        entities[index].isImmobilized = true
        // The boss stays immobilized (and harmless: resolveBossContact skips
        // immobilized bosses) until spawnGrace counts down in advance(). Driving
        // the unfreeze from the game loop, not an SKAction .run, keeps the timing
        // reliable on wasm (loop-driven, like the deferred boss spawn). Covers the
        // fade-in plus the throb telegraph.
        entities[index].spawnGrace = 3.0
        let node = entities[index].node
        node.alpha = 0
        node.setScale(1.0)

        sound.playTeleport()
        node.run(.fadeIn(withDuration: 1.5), withKey: Strings.ActionKey.spawnFade)

        let pulse = SKAction.sequence([
            .scale(to: 1.18, duration: 0.16),
            .scale(to: 1.0, duration: 0.17)
        ])
        node.run(.sequence([
            .wait(forDuration: 2.0),
            .repeat(pulse, count: 3)
        ]), withKey: Strings.ActionKey.spawnThrob)
    }

    func clear() {
        for e in entities {
            e.node.removeAllActions()
            e.node.removeFromParent()
        }
        entities.removeAll()
        pendingSpawns.removeAll()
        captureStreak = 0
    }

    func teleportAllToSpawn() {
        spawn(forLevel: currentLevel, spawnOverrides: currentSpawnOverrides)
    }

    func stopAll() {
        for boss in entities {
            boss.node.removeAllActions()
            boss.node.stopWalking()
        }
    }

    // MARK: - Gold disc
    func setGoldDiscActive(_ active: Bool) {
        captureStreak = 0
        for i in entities.indices {
            entities[i].captureCount = 0
            entities[i].isInFleeMode = active
            entities[i].node.setBodyColor(active ? SpriteFactory.fleeBodyColor : entities[i].baseColor)
            entities[i].node.setTieColor(active ? SpriteFactory.fleeTieColor : entities[i].tieColor)
            entities[i].node.setTieOutline(color: nil)
            entities[i].node.setShirtOutlineColor(active ? NSColor(calibratedWhite: 1, alpha: 0.75) : .white)
            entities[i].node.setShoeOutlineColor(Self.bossShoeGoldColor)
            entities[i].node.setEyeColor(active ? SpriteFactory.fleeEyeColor : .black)
            entities[i].node.setSkinColor(active ? SpriteFactory.fleeSkinColor : Self.baseSkinColor)
            entities[i].mover?.step = active ? entities[i].frightenedStep : entities[i].moveDuration
        }
        refreshTags(goldDiscActive: active)
        if !active { applyFleeThawTransition() }
    }

    private func applyFleeThawTransition() {
        sound.playTeleport()
        let blink = SKAction.sequence([
            .fadeAlpha(to: 0.3, duration: 0.3),
            .fadeAlpha(to: 1.0, duration: 0.3)
        ])
        for i in entities.indices {
            entities[i].isImmobilized = true
            let node = entities[i].node
            node.removeAction(forKey: Strings.ActionKey.fleeThaw)
            node.run(.sequence([
                .repeat(blink, count: 5),
                .run { [weak self, weak node] in
                    guard let self, let node,
                          let idx = self.entities.firstIndex(where: { $0.node === node }) else { return }
                    self.entities[idx].isImmobilized = false
                    node.alpha = 1
                }
            ]), withKey: Strings.ActionKey.fleeThaw)
        }
    }

    func isInFleeMode(boss node: PixelPerson) -> Bool {
        entities.first(where: { $0.node === node })?.isInFleeMode ?? false
    }

    func isImmobilized(boss node: PixelPerson) -> Bool {
        entities.first(where: { $0.node === node })?.isImmobilized ?? false
    }

    func relocateAfterCatch(boss node: PixelPerson) {
        guard let index = entities.firstIndex(where: { $0.node === node }) else { return }
        relocateToSpawn(at: index)
    }

    private func refreshTags(goldDiscActive: Bool) {
        let next = 100 * (captureStreak + 1)
        for boss in entities {
            if goldDiscActive && boss.isInFleeMode {
                boss.tag.text = "\(next)"
                boss.tag.fontColor = .systemYellow
            } else {
                boss.tag.text = boss.name
                boss.tag.fontColor = .white
            }
        }
    }

    // MARK: - Stepping
    // Each boss steps through its own TileMover, advanced once per frame from the
    // scene update. The AI plans the next target tile from Pete's position, heading,
    // and the flee state; the mover owns glide, per-tile dwell, tunnel wrap, and
    // slow-in-tunnels.
    func advance(_ dt: TimeInterval) {
        guard let delegate else { return }
        if !pendingSpawns.isEmpty {
            for i in pendingSpawns.indices { pendingSpawns[i].timer -= dt }
            let ready = pendingSpawns.filter { $0.timer <= 0 }
            pendingSpawns.removeAll { $0.timer <= 0 }
            let goldActive = delegate.isGoldDiscMode
            for p in ready where p.blueprintIndex >= 0 && p.blueprintIndex < Self.blueprints.count {
                var blueprint = Self.blueprints[p.blueprintIndex]
                blueprint.spawn = p.spawn
                createAndFreeze(from: themed(blueprint, level: currentLevel), blueprintIndex: p.blueprintIndex, goldDiscActive: goldActive)
            }
        }
        let peteGrid = delegate.workerGrid
        let peteDirection = delegate.workerDirection
        let blinky = firstBossGrid
        let flee = delegate.isGoldDiscMode
        for i in entities.indices {
            if entities[i].spawnGrace > 0 {
                entities[i].spawnGrace -= dt
                if entities[i].spawnGrace <= 0 { entities[i].isImmobilized = false }
                continue
            }
            if entities[i].isImmobilized { continue }
            guard let mover = entities[i].mover else { continue }
            let ai = entities[i].ai
            let node = entities[i].node
            mover.advance(dt, decide: { e in
                guard let move = ai.planNextStep(
                    workerGrid: peteGrid,
                    workerDirection: peteDirection,
                    blinkyGrid: blinky,
                    flee: flee,
                    dodgeAxis: delegate.dropletAxisThreatening(e.grid)
                ) else { return nil }
                return e.direction(toward: move.to)
            }, onArrive: { e in
                if let d = e.dir { node.setFacingSmoothed(d) }
            })
        }
    }

    func capture(boss node: PixelPerson) {
        guard let index = entities.firstIndex(where: { $0.node === node }) else { return }
        capture(at: index)
    }

    private func capture(at index: Int) {
        let boss = entities[index]
        captureStreak += 1
        entities[index].captureCount += 1
        let points = 100 * captureStreak
        let hasEscaped = entities[index].captureCount >= 3
        let powerActive = delegate?.isGoldDiscMode ?? false

        boss.ai.teleport(to: boss.spawn)
        boss.node.stopWalking()
        entities[index].isImmobilized = true
        boss.mover?.reset(to: boss.spawn)
        let homePoint = gridMap.point(for: boss.spawn)
        let bossNode = boss.node

        if hasEscaped {
            rebuildEntity(at: index)
            refreshTags(goldDiscActive: powerActive)
            if powerActive && !entities.contains(where: { $0.isInFleeMode }) {
                sound.stopGoldDiscBass()
            }
            delegate?.bossDidGetCaptured(name: boss.name, points: points, at: homePoint)
            return
        } else {
            var seq: [SKAction] = [
                .group([
                    .scale(to: 1.6, duration: 0.25),
                    .fadeOut(withDuration: 0.25)
                ]),
                .run { [weak bossNode] in bossNode?.position = homePoint },
                .group([
                    .scale(to: 1.0, duration: 0.2),
                    .fadeIn(withDuration: 0.2)
                ])
            ]
            seq.append(.run { [weak self, weak bossNode] in
                guard let self, let bossNode,
                      let i = self.entities.firstIndex(where: { $0.node === bossNode }) else { return }
                self.entities[i].isImmobilized = false
            })
            bossNode.run(.sequence(seq))
            boss.node.setBodyColor(powerActive ? SpriteFactory.fleeBodyColor : boss.baseColor)
            boss.node.setTieColor(powerActive ? SpriteFactory.fleeTieColor : boss.tieColor)
            boss.node.setTieOutline(color: nil)
            boss.node.setShirtOutlineColor(powerActive ? NSColor(calibratedWhite: 1, alpha: 0.75) : .white)
            boss.node.setShoeOutlineColor(Self.bossShoeGoldColor)
            boss.node.setEyeColor(powerActive ? SpriteFactory.fleeEyeColor : .black)
            boss.node.setSkinColor(powerActive ? SpriteFactory.fleeSkinColor : Self.baseSkinColor)
        }
        refreshTags(goldDiscActive: powerActive)
        delegate?.bossDidGetCaptured(name: boss.name, points: points, at: boss.node.position)
    }

    func splash(boss node: PixelPerson) {
        guard let index = entities.firstIndex(where: { $0.node === node }) else { return }
        let boss = entities[index]
        entities[index].isInFleeMode = false

        boss.node.removeAllActions()
        boss.node.removeFromParent()
        entities.remove(at: index)

        // Loop-driven respawn (advance counts it down), not an SKAction timer:
        // .run-after-.wait fires unreliably on wasm and respawned the boss late.
        pendingSpawns.append(PendingSpawn(blueprintIndex: boss.blueprintIndex, spawn: boss.spawn, timer: 5.0))
    }
}
