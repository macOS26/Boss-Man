import AppKit
import SpriteKit

@MainActor
final class TravelerSpawner {
    private weak var scene: SKScene?
    private let gridMap: GridMap
    private let sound: SoundManager
    private let spawnGrid = CGPoint(x: 35, y: 8)
    private let exitGrid = CGPoint(x: 0, y: 8)
    private let moveInterval: TimeInterval = 0.22

    private var node: SKNode?
    private var grid = CGPoint(x: 35, y: 8)
    private var previousGrid: CGPoint?
    private var activeTraveler: LevelTraveler?

    // MARK: - Continuous spawn chain
    private var pendingTraveler: LevelTraveler?
    private var keepSpawning: (() -> Bool)?
    private let firstVisitDelay: TimeInterval = 10
    private let respawnDelay:    TimeInterval = 30

    init(scene: SKScene, gridMap: GridMap, sound: SoundManager) {
        self.scene = scene
        self.gridMap = gridMap
        self.sound = sound
    }

    var hasActive: Bool { node != nil }
    var activeNode: SKNode? { node }
    var activeTravelerInfo: LevelTraveler? { activeTraveler }

    func reset() {
        node?.removeFromParent()
        node = nil
        activeTraveler = nil
        pendingTraveler = nil
        keepSpawning = nil
        scene?.removeAction(forKey: Strings.ActionKey.travelerVisit1)
        scene?.removeAction(forKey: Strings.ActionKey.travelerVisit2)
    }

    func scheduleVisits(of traveler: LevelTraveler, whileActive predicate: @escaping () -> Bool) {
        pendingTraveler = traveler
        keepSpawning = predicate
        scheduleNextSpawn(after: firstVisitDelay)
    }

    private func scheduleNextSpawn(after delay: TimeInterval) {
        guard let scene else { return }
        scene.removeAction(forKey: Strings.ActionKey.travelerVisit1)
        scene.run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in
                guard let self = self,
                      let traveler = self.pendingTraveler,
                      self.keepSpawning?() == true,
                      self.node == nil
                else { return }
                self.spawn(traveler)
            }
        ]), withKey: Strings.ActionKey.travelerVisit1)
    }

    private func scheduleStepper(on traveler: SKNode) {
        let stepper = SKAction.repeatForever(.sequence([
            .wait(forDuration: moveInterval),
            .run { [weak self] in self?.stepNode() }
        ]))
        traveler.run(stepper, withKey: Strings.ActionKey.travelerStepper)
    }

    func tryCatch(_ candidate: SKNode?) -> (traveler: LevelTraveler, position: CGPoint, emoji: String)? {
        guard let fish = node, fish === candidate, let traveler = activeTraveler else { return nil }
        let pos = fish.position
        fish.physicsBody = nil
        fish.run(.sequence([
            .group([
                .scale(to: 1.6, duration: 0.25),
                .fadeOut(withDuration: 0.25)
            ]),
            .removeFromParent()
        ]))
        node = nil
        activeTraveler = nil
        scheduleNextSpawn(after: respawnDelay)
        return (traveler, pos, traveler.emoji)
    }

    // MARK: - Private
    private func spawn(_ traveler: LevelTraveler) {
        guard let scene else { return }
        node?.removeFromParent()

        let wrapper = SKNode()
        grid = spawnGrid
        previousGrid = nil
        wrapper.position = gridMap.point(for: grid)
        wrapper.zPosition = 9
        wrapper.physicsBody = SKPhysicsBody(circleOfRadius: 10)
        wrapper.physicsBody?.isDynamic = false
        wrapper.physicsBody?.categoryBitMask = PhysicsCategory.fish
        wrapper.physicsBody?.contactTestBitMask = PhysicsCategory.worker
        wrapper.physicsBody?.collisionBitMask = 0

        let emoji = SKLabelNode()
        emoji.name = Strings.NodeName.travelerEmoji
        emoji.text = traveler.emoji
        emoji.fontSize = 36
        emoji.verticalAlignmentMode = .center
        emoji.horizontalAlignmentMode = .center
        wrapper.addChild(emoji)

        let points = SKLabelNode(fontNamed: Strings.Font.menloBold)
        points.text = "\(traveler.points)"
        points.fontSize = 11
        points.fontColor = .systemYellow
        points.verticalAlignmentMode = .baseline
        points.horizontalAlignmentMode = .center
        points.position = CGPoint(x: 0, y: 24)
        wrapper.addChild(points)

        scene.addChild(wrapper)
        node = wrapper
        activeTraveler = traveler
        scheduleStepper(on: wrapper)
        sound.playTravelerArrive(traveler.sound)
    }

    private func stepNode() {
        guard let fish = node else { return }
        if grid == exitGrid {
            fish.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            node = nil
            activeTraveler = nil
            scheduleNextSpawn(after: respawnDelay)
            return
        }
        var neighbors: [CGPoint] = []
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let next = CGPoint(x: grid.x + CGFloat(dx), y: grid.y + CGFloat(dy))
            if gridMap.isWalkable(next) { neighbors.append(next) }
        }
        var candidates = neighbors
        if let prev = previousGrid, candidates.count > 1 {
            candidates.removeAll { $0 == prev }
        }
        guard !candidates.isEmpty else { return }
        let next: CGPoint
        if Int.random(in: 0..<10) < 6, let towardExit = candidates.min(by: {
            Pathfinder.manhattanDistance($0, exitGrid) < Pathfinder.manhattanDistance($1, exitGrid)
        }) {
            next = towardExit
        } else {
            next = candidates.randomElement()!
        }
        let dx = next.x - grid.x
        if dx != 0, let emoji = fish.childNode(withName: Strings.NodeName.travelerEmoji) {
            emoji.xScale = dx < 0 ? 1 : -1
        }
        previousGrid = grid
        grid = next
        fish.run(.move(to: gridMap.point(for: next), duration: moveInterval))
    }
}
