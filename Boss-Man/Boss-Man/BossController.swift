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
        var mustExitDoorway: Bool = false
        var isInFleeMode: Bool = false
        var captureCount: Int = 0
        var isImmobilized: Bool = false
        let blueprintIndex: Int
    }

    private static let blueprints: [(name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double)] = [
        (Strings.Boss.boss,     .systemRed,    .black,        .darkGray, CGPoint(x: 34, y: 15), .directChase,                                                          1.00),
        (Strings.Boss.lumbergh, NSColor.systemPink.withAlphaComponent(0.75), NSColor.systemPurple.blended(withFraction: 0.40, of: .black) ?? .systemPurple, .darkGray, CGPoint(x: 1,  y: 1),  .ambushAhead(tiles: 4),                    0.85),
        (Strings.Boss.waddams,  .systemTeal,   NSColor.systemBlue.blended(withFraction: 0.20, of: .black) ?? .systemBlue,   .darkGray, CGPoint(x: 34, y: 1),  .flanker(pivotTiles: 2),                                               0.78),
        (Strings.Boss.bolton,   .systemOrange, NSColor.systemRed.blended(withFraction: 0.10, of: .black) ?? .systemRed,    .darkGray, CGPoint(x: 1,  y: 15), .timidScatter(scatterGrid: CGPoint(x: 1, y: 1), threshold: 8),         0.70)
    ]

    private let moveInterval: TimeInterval = 0.36
    private let moveDuration: TimeInterval = 0.22
    private let detectionRange: CGFloat = 10

    static let fleeBodyColor: NSColor = NSColor.systemBlue.blended(withFraction: 0.20, of: .black) ?? .systemBlue
    static let fleeTieColor:  NSColor = .systemYellow
    static let fleeEyeColor:  NSColor = NSColor.systemBlue.blended(withFraction: 0.50, of: .black) ?? .systemBlue

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
    func spawn(forLevel level: Int, spawnOverrides: [(blueprintIndex: Int, position: CGPoint)] = []) {
        clear()
        currentLevel = level
        currentSpawnOverrides = spawnOverrides
        if spawnOverrides.isEmpty {
            let count = min(max(level, 1), Self.blueprints.count)
            for index in 0..<count {
                let blueprint = Self.blueprints[index]
                createAndFreeze(from: themed(blueprint, level: level), blueprintIndex: index)
            }
        } else {
            for (index, position) in spawnOverrides {
                guard index >= 0, index < Self.blueprints.count else { continue }
                var blueprint = Self.blueprints[index]
                blueprint.spawn = position
                createAndFreeze(from: themed(blueprint, level: level), blueprintIndex: index)
            }
        }
    }

    private var currentSpawnOverrides: [(blueprintIndex: Int, position: CGPoint)] = []

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

    private func createAndFreeze(from blueprint: (name: String, color: NSColor, tie: NSColor, pants: NSColor, spawn: CGPoint, personality: BossPersonality, speed: Double), blueprintIndex: Int) {
        buildEntity(from: blueprint, blueprintIndex: blueprintIndex)
        let index = entities.count - 1
        scheduleStepper(for: entities[index])
        applySpawnFreeze(at: index)
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

        let node = PixelPerson(
            bodyColor: blueprint.color,
            tieColor: blueprint.tie,
            hairColor: NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.35, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: blueprint.pants,
            wearsSunglasses: isMIBLevel(currentLevel),
            headYOffset: -1
        )
        node.name = blueprint.name
        node.position = gridMap.point(for: blueprint.spawn)
        node.physicsBody = SKPhysicsBody(circleOfRadius: 10)
        node.physicsBody?.allowsRotation = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.boss
        node.physicsBody?.contactTestBitMask = PhysicsCategory.worker
        node.physicsBody?.collisionBitMask = PhysicsCategory.wall
        node.zPosition = 11
        scene.addChild(node)

        let tag = SKLabelNode(fontNamed: Strings.Font.menloBold)
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
            lastMove: 0,
            blueprintIndex: blueprintIndex
        )
        entities.append(entity)
    }

    private func relocateToSpawn(at index: Int) {
        let entity = entities[index]
        let node = entity.node
        node.removeAllActions()
        node.stopWalking()
        entity.ai.teleport(to: entity.spawn)
        node.position = gridMap.point(for: entity.spawn)
        node.setBodyColor(entity.baseColor)
        node.setTieColor(entity.tieColor)
        node.setTieOutline(color: nil)
        node.setEyeColor(.black)
        entities[index].captureCount = 0
        entities[index].isInFleeMode = false
        entities[index].mustExitDoorway = false
    }

    private func respawn(at index: Int) {
        relocateToSpawn(at: index)
        scheduleStepper(for: entities[index])
        applySpawnFreeze(at: index)
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
        let node = entities[index].node
        node.alpha = 0
        node.setScale(1.0)
        node.physicsBody?.categoryBitMask = 0

        sound.playTeleport()
        node.run(.fadeIn(withDuration: 1.5), withKey: Strings.ActionKey.spawnFade)

        node.run(.sequence([
            .wait(forDuration: 2.0),
            .run { [weak self] in self?.entities[index].isImmobilized = false },
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.entities[index].node.physicsBody?.categoryBitMask = PhysicsCategory.boss
            }
        ]), withKey: Strings.ActionKey.spawnUnfreeze)

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
            entities[i].node.setBodyColor(active ? Self.fleeBodyColor : entities[i].baseColor)
            entities[i].node.setTieColor(active ? Self.fleeTieColor : entities[i].tieColor)
            entities[i].node.setTieOutline(color: active ? .yellow : nil)
            entities[i].node.setEyeColor(active ? Self.fleeEyeColor : .black)
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

    // MARK: - Stepping (SKAction-driven per boss)
    private func scheduleStepper(for entity: Entity) {
        let bossNode = entity.node
        let stepper = SKAction.repeatForever(.sequence([
            .wait(forDuration: entity.moveInterval),
            .run { [weak self, weak bossNode] in
                guard let self, let bossNode,
                      let index = self.entities.firstIndex(where: { $0.node === bossNode })
                else { return }
                self.stepOne(at: index)
            }
        ]))
        entity.node.run(stepper, withKey: Strings.ActionKey.bossStepper)
    }

    private func stepOne(at index: Int) {
        guard let delegate, !entities[index].isImmobilized else { return }
        let boss = entities[index]
        let blinkyGrid = firstBossGrid

        let move: BossAI.Move
        if entities[index].mustExitDoorway, let exit = forcedExit(from: boss.ai.grid) {
            let from = boss.ai.grid
            boss.ai.teleport(to: exit)
            entities[index].mustExitDoorway = false
            move = BossAI.Move(from: from, to: exit)
        } else if let planned = boss.ai.planNextStep(
            workerGrid: delegate.workerGrid,
            workerDirection: delegate.workerDirection,
            blinkyGrid: blinkyGrid,
            flee: delegate.isGoldDiscMode
        ) {
            move = planned
        } else {
            boss.node.stopWalking()
            return
        }

        boss.node.startWalking()
        let dx = move.to.x - move.from.x
        let dy = move.to.y - move.from.y
        let look: MoveDirection? = {
            if abs(dx) > abs(dy) { return dx < 0 ? .left : .right }
            if dy != 0 { return dy > 0 ? .up : .down }
            return nil
        }()
        if look == .left  { boss.node.face(left: true)  }
        if look == .right { boss.node.face(left: false) }
        boss.node.setLookDirection(look)
        let isPartnerEdge = abs(move.to.x - move.from.x) + abs(move.to.y - move.from.y) > 1
        if isPartnerEdge {
            boss.node.removeAction(forKey: Strings.ActionKey.bossMove)
            boss.node.position = gridMap.point(for: move.to)
        } else {
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
                        self.entities[index].mustExitDoorway = true
                    }
                }
            ]), withKey: Strings.ActionKey.bossMove)
        }
        if Pathfinder.manhattanDistance(move.to, delegate.workerGrid) < 0.5 {
            if entities[index].isInFleeMode {
                capture(at: index)
            } else if !delegate.isPeteShielded {
                let catcher = entities[index].node
                catcher.alpha = 0
                catcher.physicsBody?.categoryBitMask = 0
                catcher.removeAllActions()
                relocateToSpawn(at: index)
                delegate.bossDidCatchWorker()
            }
        }
    }

    private func forcedExit(from grid: CGPoint) -> CGPoint? {
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let next = CGPoint(x: grid.x + CGFloat(dx), y: grid.y + CGFloat(dy))
            if gridMap.isWalkable(next), gridMap.tunnelPartner(of: next) == nil {
                return next
            }
        }
        return nil
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
        boss.node.removeAction(forKey: Strings.ActionKey.bossMove)
        boss.node.stopWalking()
        boss.node.physicsBody?.categoryBitMask = 0
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
            boss.node.setBodyColor(powerActive ? Self.fleeBodyColor : boss.baseColor)
            boss.node.setTieColor(powerActive ? Self.fleeTieColor : boss.tieColor)
            boss.node.setTieOutline(color: powerActive ? .yellow : nil)
            boss.node.setEyeColor(powerActive ? Self.fleeEyeColor : .black)
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

        let blueprintIndex = boss.blueprintIndex
        let spawn = boss.spawn
        let timer = SKNode()
        scene?.addChild(timer)
        timer.run(.sequence([
            .wait(forDuration: 5.0),
            .run { [weak self, weak timer] in
                timer?.removeFromParent()
                guard let self, blueprintIndex >= 0, blueprintIndex < Self.blueprints.count else { return }
                var blueprint = Self.blueprints[blueprintIndex]
                blueprint.spawn = spawn
                self.createAndFreeze(from: self.themed(blueprint, level: self.currentLevel), blueprintIndex: blueprintIndex)
            }
        ]))
    }
}
