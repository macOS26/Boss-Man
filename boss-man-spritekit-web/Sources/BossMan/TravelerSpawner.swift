import SpriteKit

// Verbatim-shape port of boss-man-spritekit-swift/Boss-Man/TravelerSpawner.swift.
// One spawner per game; it owns the active traveler node, the spawn/exit
// grid coords, and the SKAction stepper that walks the traveler tile-by-
// tile toward the exit. After firstVisitDelay seconds (or respawnDelay
// after a previous traveler exits/is caught) the next traveler from the
// level's table walks across the floor.
//
// Differences vs bossman-apple:
//   - No SKPhysicsBody. bossman-web uses tile-overlap detection: GameScene
//     compares peteMover.grid to spawner.grid each frame for the catch.
//   - The catch returns the LevelTraveler so the caller can award points.
//   - Image path goes through the runtime's named-image table (red-stapler
//     comes from web/assets/images/red-stapler.png).
final class TravelerSpawner {
    private weak var scene: SKScene?
    private let gridMap: GridMap
    private let sound: SoundManager
    private let containerOriginX: CGFloat
    private let spawnGrid: CGPoint
    private let exitGrid:  CGPoint
    private let moveInterval: TimeInterval = 0.22

    private(set) var node: SKNode?
    private(set) var grid: CGPoint
    private var previousGrid: CGPoint?
    private(set) var activeTraveler: LevelTraveler?

    private var pendingTraveler: LevelTraveler?
    private var keepSpawning: (() -> Bool)?
    private let firstVisitDelay: TimeInterval = 10
    private let respawnDelay:    TimeInterval = 30

    init(scene: SKScene, gridMap: GridMap, sound: SoundManager, containerOriginX: CGFloat,
         spawnGrid: CGPoint? = nil, exitGrid: CGPoint? = nil) {
        self.scene = scene
        self.gridMap = gridMap
        self.sound = sound
        self.containerOriginX = containerOriginX
        // bossman-apple defaults: right-mouth of the row-8 tunnel to the left-mouth.
        // bossman-web's mazes use the row 9 tunnel; allow override.
        let cols = gridMap.columnCount
        let defaultSpawn = CGPoint(x: CGFloat(cols - 1), y: 9)
        let defaultExit  = CGPoint(x: 0,                 y: 9)
        self.spawnGrid = spawnGrid ?? defaultSpawn
        self.exitGrid  = exitGrid  ?? defaultExit
        self.grid      = self.spawnGrid
    }

    var hasActive: Bool { node != nil }

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
                guard let self,
                      let traveler = self.pendingTraveler,
                      self.keepSpawning?() == true,
                      self.node == nil
                else { return }
                self.spawn(traveler)
            }
        ]), withKey: Strings.ActionKey.travelerVisit1)
    }

    // Pete just stepped onto this tile — if a traveler is here, catch it.
    func tryCatch(at peteGrid: CGPoint) -> (traveler: LevelTraveler, position: CGPoint)? {
        guard let fish = node, let traveler = activeTraveler, grid == peteGrid else { return nil }
        let pos = fish.position
        fish.run(.sequence([
            .group([
                .scale(to: 1.6, duration: 0.25),
                .fadeOut(withDuration: 0.25),
            ]),
            .removeFromParent(),
        ]))
        node = nil
        activeTraveler = nil
        scheduleNextSpawn(after: respawnDelay)
        return (traveler, pos)
    }

    private func sceneCoord(forGrid g: CGPoint) -> CGPoint {
        let local = gridMap.point(for: g)
        return CGPoint(x: local.x + containerOriginX, y: local.y)
    }

    private func spawn(_ traveler: LevelTraveler) {
        guard let scene else { return }
        node?.removeFromParent()

        let wrapper = SKNode()
        grid = spawnGrid
        previousGrid = nil
        wrapper.position = sceneCoord(forGrid: grid)
        wrapper.zPosition = 9

        let visual: SKNode
        if let imageName = traveler.image,
           let texture = textureNamed(imageName) {
            let sprite = SKSpriteNode(texture: texture)
            let targetHeight: CGFloat = 36 * 0.75
            let s = texture.size
            let aspect = s.height > 0 ? s.width / s.height : 1
            sprite.size = CGSize(width: targetHeight * aspect, height: targetHeight)
            visual = sprite
        } else {
            let label = SKLabelNode()
            label.text = traveler.emoji
            label.fontSize = 36
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            if traveler.emoji == "\u{2702}\u{FE0F}" {
                label.zRotation = -.pi / 2
            }
            visual = label
        }
        visual.name = Strings.NodeName.travelerEmoji
        wrapper.addChild(visual)

        let points = SKLabelNode(fontNamed: Strings.Font.menloBold)
        points.text = "\(traveler.points)"
        points.fontSize = 11
        points.fontColor = SKColor(red: 1.0, green: 0.91, blue: 0.34, alpha: 1)
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

    private func scheduleStepper(on traveler: SKNode) {
        let stepper = SKAction.repeatForever(.sequence([
            .wait(forDuration: moveInterval),
            .run { [weak self] in self?.stepNode() },
        ]))
        traveler.run(stepper, withKey: Strings.ActionKey.travelerStepper)
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
            let facesRight = activeTraveler?.facesRight ?? false
            if facesRight {
                emoji.xScale = dx < 0 ? -1 : 1
            } else {
                emoji.xScale = dx < 0 ? 1 : -1
            }
        }
        previousGrid = grid
        grid = next
        fish.run(.move(to: sceneCoord(forGrid: next), duration: moveInterval))
    }
}
