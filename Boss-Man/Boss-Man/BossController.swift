import AppKit
import SpriteKit

@MainActor
protocol BossControllerDelegate: AnyObject {
    var workerGrid: CGPoint { get }
    var workerDirection: MoveDirection? { get }
    var isPowerPelletMode: Bool { get }
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
    private(set) var entities: [Entity] = []
    private var captureStreak = 0

    var hasFirstBoss: Bool { !entities.isEmpty }
    var firstBossGrid: CGPoint? { entities.first?.ai.grid }

    init(scene: SKScene, gridMap: GridMap, pathfinder: Pathfinder) {
        self.scene = scene
        self.gridMap = gridMap
        self.pathfinder = pathfinder
    }

    // MARK: - Roster lifecycle

    func spawn(forLevel level: Int) {
        clear()
        guard let scene else { return }
        let activeCount = min(max(level, 1), Self.blueprints.count)
        for blueprint in Self.blueprints.prefix(activeCount) {
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
                pantsColor: blueprint.pants
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
            scheduleStepper(for: entity)
        }
    }

    func clear() {
        for e in entities {
            e.node.removeAllActions()
            e.node.removeFromParent()
        }
        entities.removeAll()
        captureStreak = 0
    }

    func teleportAllToSpawn() {
        for boss in entities {
            boss.ai.teleport(to: boss.spawn)
            // Keep the keyed stepper alive — only cancel the current
            // move animation so the boss snaps home and keeps stepping.
            boss.node.removeAction(forKey: "bossMove")
            boss.node.stopWalking()
            boss.node.run(SKAction.move(to: gridMap.point(for: boss.spawn), duration: 0.2))
        }
    }

    func stopAll() {
        for boss in entities {
            boss.node.removeAllActions()
            boss.node.stopWalking()
        }
    }

    // MARK: - Power pellet

    func setPowerPelletActive(_ active: Bool) {
        if active {
            captureStreak = 0
            for boss in entities { boss.node.setBodyColor(.systemBlue) }
        } else {
            captureStreak = 0
            for boss in entities { boss.node.setBodyColor(boss.baseColor) }
        }
        refreshTags(powerPelletActive: active)
    }

    private func refreshTags(powerPelletActive: Bool) {
        if powerPelletActive {
            let next = 100 * (captureStreak + 1)
            for boss in entities {
                boss.tag.text = "\(next)"
                boss.tag.fontColor = .systemYellow
            }
        } else {
            for boss in entities {
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
        guard let delegate else { return }
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
            if delegate.isPowerPelletMode {
                capture(at: index)
            } else {
                delegate.bossDidCatchWorker()
            }
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
        let points = 100 * captureStreak
        boss.ai.teleport(to: boss.spawn)
        // Cancel the current move only — keep the keyed stepper alive
        // so the boss resumes chasing after the capture animation.
        boss.node.removeAction(forKey: "bossMove")
        boss.node.stopWalking()
        boss.node.physicsBody?.categoryBitMask = 0
        let homePoint = gridMap.point(for: boss.spawn)
        let bossNode = boss.node
        let powerActive = delegate?.isPowerPelletMode ?? false
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
        refreshTags(powerPelletActive: powerActive)
        delegate?.bossDidGetCaptured(name: boss.name, points: points, at: boss.node.position)
    }
}
