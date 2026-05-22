import AppKit
import SpriteKit

@MainActor
protocol BossControllerDelegate: AnyObject {
    var workerGrid: CGPoint { get }
    var workerDirection: MoveDirection? { get }
    var isPowerPelletMode: Bool { get }
    /// True while PETE is wearing his spawn-protection orange shield;
    /// boss AI catch logic must short-circuit when this is set.
    var isPeteShielded: Bool { get }
    func bossDidCatchWorker()
    func bossDidGetCaptured(name: String, points: Int, at position: CGPoint)
}

/// Owns the boss roster, per-floor blueprints, and all per-frame
/// chasing / fleeing / capture animation. GameScene tells it when to
/// spawn for a given level, when to step each frame, and when to flip
/// into power-pellet mode; BossController calls back through the
/// delegate when a boss catches PETE or PETE captures a boss.
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
        /// Set to true after a tunnel teleport so the next planned step is
        /// forced toward an interior (non-doorway) neighbor — the boss
        /// "commits" through the doorway and can't whip back in.
        var mustExitDoorway: Bool = false
        /// True while this boss is in scared/blue mode and capturable.
        /// Toggled per-boss so a boss that has "escaped" power-pellet
        /// mode by being captured 3 times can return to dangerous even
        /// while the global power-pellet timer is still running.
        var isInFleeMode: Bool = false
        /// Number of times PETE has captured this boss in the current
        /// power-pellet window. After 3 the boss respawns as a regular
        /// boss (immobile + immune for 3 seconds while fading back in).
        var captureCount: Int = 0
        /// During the 3-second post-escape spawn freeze, the boss can't
        /// step and contacts with PETE are ignored.
        var isImmobilized: Bool = false
    }

    private static let blueprints: [(name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double)] = [
        ("BOSS", .systemRed, .black, .darkGray, CGPoint(x: 34, y: 15), .directChase, 1.0),
        ("LUMBERGH", .systemPurple, .systemYellow, .darkGray, CGPoint(x: 1, y: 1), .ambushAhead(tiles: 4), 0.85),
        ("WADDAMS", .systemOrange, .systemRed, .darkGray, CGPoint(x: 34, y: 1), .timidScatter(scatterGrid: CGPoint(x: 1, y: 1), threshold: 8), 0.70),
        ("BOLTON", .systemPink, .systemTeal, .darkGray, CGPoint(x: 1, y: 15), .flanker(pivotTiles: 2), 0.78)
    ]

    private let moveInterval: TimeInterval = 0.36
    private let moveDuration: TimeInterval = 0.22
    private let detectionRange: CGFloat = 10

    weak var delegate: BossControllerDelegate?
    private weak var scene: SKScene?
    private let gridMap: GridMap
    private let pathfinder: Pathfinder
    private let sound: SoundManager
    private(set) var entities: [Entity] = []
    private var captureStreak = 0
    private var currentLevel = 1

    var hasFirstBoss: Bool { !entities.isEmpty }
    var firstBossGrid: CGPoint? { entities.first?.ai.grid }

    init(scene: SKScene, gridMap: GridMap, pathfinder: Pathfinder, sound: SoundManager) {
        self.scene = scene
        self.sound = sound
        self.gridMap = gridMap
        self.pathfinder = pathfinder
    }

    // MARK: - Roster lifecycle

    func spawn(forLevel level: Int) {
        clear()
        currentLevel = level
        let activeCount = min(max(level, 1), Self.blueprints.count)
        for blueprint in Self.blueprints.prefix(activeCount) {
            createAndFreeze(from: themed(blueprint, level: level))
        }
    }

    /// On the MIB level (every 12th floor) every boss is reskinned in
    /// a black suit, black tie, black slacks. The actual sunglasses
    /// overlay is applied by PixelPerson when `wearsSunglasses == true`,
    /// which buildEntity infers from `isMIBLevel`.
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

    /// Build a fresh entity from `blueprint`, add it to the scene
    /// and run it through the spawn freeze (stepper + fade/throb/arm).
    /// One function used by every respawn-as-boss path: level start,
    /// post-PETE-death tear-down + rebuild, and the 3-strikes
    /// power-pellet escape.
    private func createAndFreeze(from blueprint: (name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double)) {
        buildEntity(from: blueprint)
        let index = entities.count - 1
        scheduleStepper(for: entities[index])
        applySpawnFreeze(at: index)
    }

    private func buildEntity(from blueprint: (name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double)) {
        guard let scene else { return }
        let ai = BossAI(
            homeGrid: blueprint.spawn,
            detectionRange: detectionRange,
            personality: blueprint.personality,
            pathfinder: pathfinder,
            map: gridMap
        )
        ai.teleport(to: blueprint.spawn)

        let node = PixelPerson(
            bodyColor: blueprint.color,
            tieColor: blueprint.tie,
            hairColor: NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.35, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: blueprint.pants,
            wearsSunglasses: isMIBLevel(currentLevel)
        )
        node.name = blueprint.name
        node.position = gridMap.point(for: blueprint.spawn)
        node.physicsBody = SKPhysicsBody(circleOfRadius: 13)
        node.physicsBody?.allowsRotation = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.boss
        node.physicsBody?.contactTestBitMask = PhysicsCategory.worker
        node.physicsBody?.collisionBitMask = PhysicsCategory.wall
        node.zPosition = 11
        scene.addChild(node)

        let tag = SKLabelNode(fontNamed: "Menlo-Bold")
        tag.text = blueprint.name
        tag.fontSize = 9
        tag.fontColor = .white
        tag.position = CGPoint(x: 0, y: 24)
        node.addChild(tag)

        let entity = Entity(
            name: blueprint.name,
            baseColor: blueprint.color,
            tieColor: blueprint.tie,
            pantsColor: blueprint.pants,
            spawn: blueprint.spawn,
            ai: ai,
            node: node,
            tag: tag,
            moveInterval: moveInterval / blueprint.speed,
            moveDuration: moveDuration / blueprint.speed,
            lastMove: 0
        )
        entities.append(entity)
    }

    /// Snaps a boss back to its spawn tile with all per-run state
    /// reset (no fade, no animation, no scheduling). Always called
    /// before applySpawnFreeze so the boss is guaranteed to be at
    /// home before the freeze visual starts.
    private func relocateToSpawn(at index: Int) {
        let entity = entities[index]
        let node = entity.node
        node.removeAllActions()
        node.stopWalking()
        entity.ai.teleport(to: entity.spawn)
        node.position = gridMap.point(for: entity.spawn)
        node.setBodyColor(entity.baseColor)
        entities[index].captureCount = 0
        entities[index].isInFleeMode = false
        entities[index].mustExitDoorway = false
    }

    /// Single source of truth for the full boss spawn cycle:
    ///   1. relocateToSpawn  — snap home + reset state
    ///   2. scheduleStepper  — re-queue the AI tick
    ///   3. applySpawnFreeze — fade / throb / re-arm schedule
    /// Called by level start and post-PETE-death respawn.
    private func respawn(at index: Int) {
        relocateToSpawn(at: index)
        scheduleStepper(for: entities[index])
        applySpawnFreeze(at: index)
    }

    /// Hard rebuild: remove the boss node from the scene, drop the
    /// entity, then funnel through createAndFreeze() — the same path
    /// level-start and post-death respawns use. Used by the 3-strikes
    /// power-pellet escape so no stale SKAction, physics state, or
    /// node residue can leak from PETE's tile.
    private func rebuildEntity(at index: Int) {
        let bossName = entities[index].name
        entities[index].node.alpha = 0
        entities[index].node.removeAllActions()
        entities[index].node.removeFromParent()
        entities.remove(at: index)
        guard let blueprint = Self.blueprints.first(where: { $0.name == bossName }) else { return }
        createAndFreeze(from: themed(blueprint, level: currentLevel))
    }

    /// Three-second boss spawn / respawn freeze:
    ///   • 0.0–1.5s  fade in from invisible.
    ///   • 2.0s       isImmobilized = false (boss starts stepping).
    ///   • 2.0–3.0s   pulse/throb scale as a "danger imminent" tell.
    ///   • 3.0s       physics body re-armed — only now can he kill PETE.
    private func applySpawnFreeze(at index: Int) {
        entities[index].isImmobilized = true
        let node = entities[index].node
        node.alpha = 0
        node.setScale(1.0)
        node.physicsBody?.categoryBitMask = 0

        sound.playTeleport()
        node.run(.fadeIn(withDuration: 1.5), withKey: "spawnFade")

        node.run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in self?.entities[index].isImmobilized = false },
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.entities[index].node.physicsBody?.categoryBitMask = PhysicsCategory.boss
            }
        ]), withKey: "spawnUnfreeze")

        // Three quick pulses in the 2.0–3.0s window — gives the player
        // a visual cue that this boss is about to become dangerous.
        let pulse = SKAction.sequence([
            .scale(to: 1.18, duration: 0.16),
            .scale(to: 1.0, duration: 0.17)
        ])
        node.run(.sequence([
            .wait(forDuration: 2.0),
            .repeat(pulse, count: 3)
        ]), withKey: "spawnThrob")
    }

    func clear() {
        for e in entities {
            e.node.removeAllActions()
            e.node.removeFromParent()
        }
        entities.removeAll()
        captureStreak = 0
    }

    /// Called when PETE dies — fully tear every boss down and respawn
    /// from scratch at the current level. Cleaner than per-boss state
    /// reset because it guarantees zero leftover SKActions, physics
    /// state, or stale node references.
    func teleportAllToSpawn() {
        spawn(forLevel: currentLevel)
    }

    func stopAll() {
        for boss in entities {
            boss.node.removeAllActions()
            boss.node.stopWalking()
        }
    }

    // MARK: - Power pellet

    func setPowerPelletActive(_ active: Bool) {
        captureStreak = 0
        for i in entities.indices {
            entities[i].captureCount = 0
            entities[i].isInFleeMode = active
            entities[i].node.setBodyColor(active ? .systemBlue : entities[i].baseColor)
        }
        refreshTags(powerPelletActive: active)
    }

    /// True only when this specific boss is currently capturable. After
    /// 3 captures in a single power-pellet window the boss flips back
    /// to dangerous even while the global timer keeps running.
    func isInFleeMode(boss node: PixelPerson) -> Bool {
        entities.first(where: { $0.node === node })?.isInFleeMode ?? false
    }

    /// True while a boss is in its post-escape freeze — can't move,
    /// can't catch PETE.
    func isImmobilized(boss node: PixelPerson) -> Bool {
        entities.first(where: { $0.node === node })?.isImmobilized ?? false
    }

    /// Snap a specific boss back to its spawn tile immediately. Used
    /// the moment a boss catches PETE so the boss isn't sitting on
    /// top of PETE's respawn point while bossCaughtWorker runs.
    func relocateAfterCatch(boss node: PixelPerson) {
        guard let index = entities.firstIndex(where: { $0.node === node }) else { return }
        relocateToSpawn(at: index)
    }

    private func refreshTags(powerPelletActive: Bool) {
        let next = 100 * (captureStreak + 1)
        for boss in entities {
            if powerPelletActive && boss.isInFleeMode {
                boss.tag.text = "\(next)"
                boss.tag.fontColor = .systemYellow
            } else {
                boss.tag.text = boss.name
                boss.tag.fontColor = .white
            }
        }
    }

    // MARK: - Stepping (SKAction-driven per boss)

    private func scheduleStepper(for entity: Entity) {
        let bossName = entity.name
        let stepper = SKAction.repeatForever(.sequence([
            .wait(forDuration: entity.moveInterval),
            .run { [weak self] in
                guard let self,
                      let index = self.entities.firstIndex(where: { $0.name == bossName })
                else { return }
                self.stepOne(at: index)
            }
        ]))
        entity.node.run(stepper, withKey: "bossStepper")
    }

    private func stepOne(at index: Int) {
        guard let delegate, !entities[index].isImmobilized else { return }
        let boss = entities[index]
        let blinkyGrid = firstBossGrid

        let move: BossAI.Move
        if entities[index].mustExitDoorway, let exit = forcedExit(from: boss.ai.grid) {
            // Commit: after a tunnel teleport, the boss must step out to a
            // non-doorway interior neighbor regardless of what the AI would
            // otherwise pick. Clear the flag so subsequent steps planned
            // normally.
            let from = boss.ai.grid
            boss.ai.teleport(to: exit)
            entities[index].mustExitDoorway = false
            move = BossAI.Move(from: from, to: exit)
        } else if let planned = boss.ai.planNextStep(
            workerGrid: delegate.workerGrid,
            workerDirection: delegate.workerDirection,
            blinkyGrid: blinkyGrid,
            flee: delegate.isPowerPelletMode
        ) {
            move = planned
        } else {
            boss.node.stopWalking()
            return
        }

        boss.node.startWalking()
        let isPartnerEdge = abs(move.to.x - move.from.x) + abs(move.to.y - move.from.y) > 1
        if isPartnerEdge {
            boss.node.removeAction(forKey: "bossMove")
            boss.node.position = gridMap.point(for: move.to)
        } else {
            // Slow down both entering AND exiting a tunnel doorway; full
            // speed for plain interior steps.
            let touchesDoorway =
                gridMap.tunnelPartner(of: move.from) != nil ||
                gridMap.tunnelPartner(of: move.to) != nil
            let stepDuration = touchesDoorway ? boss.moveDuration * 2.0 : boss.moveDuration

            boss.node.run(.sequence([
                SKAction.move(to: gridMap.point(for: move.to), duration: stepDuration),
                .run { [weak self] in
                    guard let self else { return }
                    if let partner = self.gridMap.tunnelPartner(of: move.to),
                       self.gridMap.isWalkable(partner) {
                        self.entities[index].node.position = self.gridMap.point(for: partner)
                        self.entities[index].ai.teleport(to: partner)
                        // Next step must exit the doorway — no reversal allowed.
                        self.entities[index].mustExitDoorway = true
                    }
                }
            ]), withKey: "bossMove")
        }
        if Pathfinder.manhattanDistance(move.to, delegate.workerGrid) < 0.5 {
            if entities[index].isInFleeMode {
                capture(at: index)
            } else if !delegate.isPeteShielded {
                // Instantly hide + disable + clear the catching boss
                // so it can't render or collide while bossCaughtWorker
                // tears everything down and respawns fresh.
                let catcher = entities[index].node
                catcher.alpha = 0
                catcher.physicsBody?.categoryBitMask = 0
                catcher.removeAllActions()
                relocateToSpawn(at: index)
                delegate.bossDidCatchWorker()
            }
            // PETE is shielded → ignore. He's invulnerable until the
            // 5-second spawn shield expires.
        }
    }

    /// Returns the first walkable non-doorway neighbor of `grid`, used
    /// to force a boss to exit a tunnel mouth without reversing.
    private func forcedExit(from grid: CGPoint) -> CGPoint? {
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let next = CGPoint(x: grid.x + CGFloat(dx), y: grid.y + CGFloat(dy))
            if gridMap.isWalkable(next), gridMap.tunnelPartner(of: next) == nil {
                return next
            }
        }
        return nil
    }

    /// Public capture entry point: also handles the case where the
    /// physics contact handler detects the catch before our per-frame
    /// stepping does. Looks up by PixelPerson node.
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
        let powerActive = delegate?.isPowerPelletMode ?? false

        boss.ai.teleport(to: boss.spawn)
        boss.node.removeAction(forKey: "bossMove")
        boss.node.stopWalking()
        boss.node.physicsBody?.categoryBitMask = 0
        let homePoint = gridMap.point(for: boss.spawn)
        let bossNode = boss.node

        if hasEscaped {
            // 3 captures in this power-pellet window → tear this boss
            // off the board and rebuild it fresh in its corner. Same
            // path used elsewhere via rebuildEntity(at:).
            rebuildEntity(at: index)
            refreshTags(powerPelletActive: powerActive)
            // Once every boss has escaped (none left in flee mode),
            // kill the global power-pellet bassline — nothing on the
            // board is capturable anymore.
            if powerActive && !entities.contains(where: { $0.isInFleeMode }) {
                sound.stopPowerPelletBass()
            }
            delegate?.bossDidGetCaptured(name: boss.name, points: points, at: homePoint)
            return
        } else {
            bossNode.run(.sequence([
                .group([
                    .scale(to: 1.6, duration: 0.25),
                    .fadeOut(withDuration: 0.25)
                ]),
                .run { [weak bossNode] in bossNode?.position = homePoint },
                .group([
                    .scale(to: 1.0, duration: 0.2),
                    .fadeIn(withDuration: 0.2)
                ]),
                .run { [weak bossNode] in
                    bossNode?.physicsBody?.categoryBitMask = PhysicsCategory.boss
                }
            ]))
            boss.node.setBodyColor(powerActive ? .systemBlue : boss.baseColor)
        }
        refreshTags(powerPelletActive: powerActive)
        delegate?.bossDidGetCaptured(name: boss.name, points: points, at: boss.node.position)
    }
}
