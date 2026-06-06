import SpriteKit
import AppKit

// One spawner per game: owns the active traveler node, the spawn/exit grid
// coords, and the self-chaining stepper that walks the traveler tile-by-tile
// toward the exit. After firstVisitDelay (or respawnDelay after one exits/is
// caught) the next traveler from the level table walks across the floor.
// Shared by both ports; the only platform branch is loading the traveler image.
@MainActor
final class TravelerSpawner {
    private weak var scene: SKScene?
    private let gridMap: GridMap
    private let sound: SoundManager
    private let containerOriginX: CGFloat
    private let spawnOverride: CGPoint?
    private let exitOverride:  CGPoint?
    private var spawnGrid = CGPoint.zero
    private var exitGrid  = CGPoint.zero
    private let moveInterval: TimeInterval = 0.22

    private(set) var node: SKNode?
    private(set) var grid = CGPoint.zero
    private var previousGrid: CGPoint?
    private(set) var activeTraveler: LevelTraveler?
    // The traveler's OWN PRNG, reseeded from a persisted counter every spawn, so each visit roams a fresh
    // random path that still drifts toward the exit (the shared game RNG is fixed-seed/deterministic).
    private var rng = Xoshiro256(seed: 0)
    private static func nextSeed() -> UInt64 {
        let n = Persistence.int(forKey: Strings.DefaultsKey.travelerSeed) &+ 1
        Persistence.set(n, forKey: Strings.DefaultsKey.travelerSeed)
        return UInt64(bitPattern: Int64(n))
    }

    private var pendingTraveler: LevelTraveler?
    private var keepSpawning: (() -> Bool)?
    private let firstVisitDelay: TimeInterval = 10
    private let respawnDelay:    TimeInterval = 30

    init(scene: SKScene, gridMap: GridMap, sound: SoundManager,
         containerOriginX: CGFloat = 0, spawnGrid: CGPoint? = nil, exitGrid: CGPoint? = nil) {
        self.scene = scene
        self.gridMap = gridMap
        self.sound = sound
        self.containerOriginX = containerOriginX
        self.spawnOverride = spawnGrid
        self.exitOverride  = exitGrid
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
                guard let self, let traveler = self.pendingTraveler, self.node == nil else { return }
                if self.keepSpawning?() == true { self.spawn(traveler) }
                else { self.scheduleNextSpawn(after: 1.0) }   // blocked (paused/dying): retry, don't give up forever
            }
        ]), withKey: Strings.ActionKey.travelerVisit1)
    }

    // MARK: - Catch
    // Physics-contact catch (the contacted node is the candidate).
    func tryCatch(_ candidate: SKNode?) -> (traveler: LevelTraveler, position: CGPoint)? {
        guard let fish = node, fish === candidate, let traveler = activeTraveler else { return nil }
        return consumeCatch(fish: fish, traveler: traveler)
    }
    // Tile-overlap catch (Pete snapped to the traveler's tile).
    func tryCatch(at peteGrid: CGPoint) -> (traveler: LevelTraveler, position: CGPoint)? {
        guard let fish = node, let traveler = activeTraveler, grid == peteGrid else { return nil }
        return consumeCatch(fish: fish, traveler: traveler)
    }
    // Position-overlap catch (Pete ran THROUGH a moving traveler between tiles).
    func tryCatchByOverlap(petePosition: CGPoint, radius: CGFloat) -> (traveler: LevelTraveler, position: CGPoint)? {
        guard let fish = node, let traveler = activeTraveler else { return nil }
        let dx = fish.position.x - petePosition.x
        let dy = fish.position.y - petePosition.y
        guard dx * dx + dy * dy < radius * radius else { return nil }
        return consumeCatch(fish: fish, traveler: traveler)
    }
    @discardableResult
    func consumeCatch(fish: SKNode, traveler: LevelTraveler) -> (traveler: LevelTraveler, position: CGPoint) {
        let pos = fish.position
        fish.removeAllActions()
        fish.physicsBody = nil
        fish.run(.sequence([
            .group([.scale(to: 1.6, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent(),
        ]))
        node = nil
        activeTraveler = nil
        scheduleNextSpawn(after: respawnDelay)
        return (traveler, pos)
    }

    // MARK: - Spawn + walk
    // The doorway can sit on any row; resolve it from the current maze each
    // spawn. Right mouth spawns, left mouth exits; fall back to the row-8 mouths.
    private func resolveDoorway() {
        let cols = gridMap.columnCount
        let doorway = gridMap.horizontalDoorway()
        spawnGrid = spawnOverride ?? doorway?.spawn ?? CGPoint(x: CGFloat(cols - 1), y: 8)
        exitGrid  = exitOverride  ?? doorway?.exit  ?? CGPoint(x: 0, y: 8)
    }

    // gridMap.point(for:) already includes the maze offset; containerOriginX is
    // 0 on apple and the legacy origin on wasm.
    private func sceneCoord(forGrid g: CGPoint) -> CGPoint {
        let local = gridMap.point(for: g)
        return CGPoint(x: local.x + containerOriginX, y: local.y)
    }

    private func spawn(_ traveler: LevelTraveler) {
        guard let scene else { return }
        node?.removeFromParent()

        let wrapper = SKNode()
        rng = Xoshiro256(seed: TravelerSpawner.nextSeed())   // fresh random walk every visit
        resolveDoorway()
        grid = spawnGrid
        previousGrid = nil
        wrapper.position = sceneCoord(forGrid: grid)
        wrapper.zPosition = 9
        // Static circle (r=10), category=fish, contact-test against worker. The
        // fish is the dynamic side so Box2D emits the contact even though Pete's
        // body is non-dynamic on wasm (and it is harmless on apple).
        let body = SKPhysicsBody(circleOfRadius: 10)
        body.isDynamic = true
        body.affectedByGravity = false   // the SKAction walk owns its position; default scene gravity would otherwise drift node.position off its aisle (the iso/3D mirrors read node.position)
        body.categoryBitMask = PhysicsCategory.fish
        body.contactTestBitMask = PhysicsCategory.worker
        body.collisionBitMask = 0
        wrapper.physicsBody = body

        let visual = travelerVisual(for: traveler)
        visual.name = Strings.NodeName.travelerEmoji
        wrapper.addChild(visual)

        let points = SKLabelNode(fontNamed: Strings.Font.menloBold)
        points.text = "\(traveler.points)"
        points.fontSize = 11 * SpriteFactory.worldRenderScale
        points.fontColor = .systemYellow
        points.verticalAlignmentMode = .baseline
        points.horizontalAlignmentMode = .center
        points.setScale(1 / SpriteFactory.worldRenderScale)
        points.position = CGPoint(x: 0, y: 24)
        wrapper.addChild(points)

        scene.addChild(wrapper)
        node = wrapper
        activeTraveler = traveler
        sound.playTravelerArrive(traveler.sound)
        stepNode()
    }

    // Traveler glyph: an aspect-correct image sprite when the asset is loaded,
    // otherwise the emoji label (scissors stand upright). Image loading is the
    // one platform branch.
    private func travelerVisual(for traveler: LevelTraveler) -> SKNode {
        let targetHeight: CGFloat = 36 * 0.75
        if let imageName = traveler.image, let sprite = imageSprite(named: imageName, height: targetHeight) {
            return sprite
        }
        let wrap = SKNode()
        let label = SKLabelNode()
        label.text = traveler.emoji
        label.fontSize = 36 * SpriteFactory.worldRenderScale
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.setScale(1 / SpriteFactory.worldRenderScale)
        if traveler.emoji == "\u{2702}\u{FE0F}" { label.zRotation = -.pi / 2 }
        wrap.addChild(label)
        return wrap
    }

    private func imageSprite(named name: String, height: CGFloat) -> SKSpriteNode? {
        guard let img = NSImage(named: name) ?? loadBundleImage(named: name) else { return nil }
        let sprite = SKSpriteNode(texture: SKTexture(image: img))
        let s = img.size
        let aspect = s.height > 0 ? s.width / s.height : 1
        sprite.size = CGSize(width: height * aspect, height: height)
        return sprite
    }

    private func loadBundleImage(named name: String) -> NSImage? {
        for ext in [Strings.Resource.redStaplerExtension,
                    Strings.Resource.travelerStaplerExtension] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return nil
    }

    // Self-chaining walk: pick the next tile, animate one move, re-fire at
    // completion — no inter-tile gap. Biased random walk over 4-dir walkable
    // neighbours, 60% toward the exit by Manhattan distance, never backtracking
    // when an alternative exists (ignores the side-tunnel wrap).
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
        if Int.random(in: 0..<10, using: &rng) < 6, let towardExit = candidates.min(by: {
            Pathfinder.manhattanDistance($0, exitGrid) < Pathfinder.manhattanDistance($1, exitGrid)
        }) {
            next = towardExit
        } else {
            next = candidates.randomElement(using: &rng)!
        }
        let dx = next.x - grid.x
        if dx != 0, let emoji = fish.childNode(withName: Strings.NodeName.travelerEmoji) {
            let facesRight = activeTraveler?.facesRight ?? false
            emoji.xScale = facesRight ? (dx < 0 ? -1 : 1) : (dx < 0 ? 1 : -1)
        }
        previousGrid = grid
        grid = next
        fish.run(.sequence([
            .move(to: sceneCoord(forGrid: next), duration: moveInterval),
            .run { [weak self] in self?.stepNode() },
        ]))
    }
}
