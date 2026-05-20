import AppKit
import SpriteKit

@MainActor
protocol WorkerControllerDelegate: AnyObject {
    var isGameOver: Bool { get }
    func workerDidEnterTile(_ grid: CGPoint)
}

/// Owns PETE, his grid position, and his Pac-Man-style turn-buffer
/// movement. GameScene feeds it direction intents from any input
/// source (keyboard / gamepad / pointer) via queueDirection, and it
/// calls back through WorkerControllerDelegate whenever PETE actually
/// finishes stepping into a new tile (so the scene can collect dots,
/// trigger level-completes, etc.).
@MainActor
final class WorkerController {
    weak var delegate: WorkerControllerDelegate?
    let node: PixelPerson
    private(set) var grid: CGPoint
    private(set) var direction: MoveDirection?
    private(set) var queuedDirection: MoveDirection?

    private let gridMap: GridMap
    private let sound: SoundManager
    private let moveInterval: TimeInterval = 0.14
    private let moveDuration: TimeInterval = 0.14
    /// Small extra delay added to the next step when PETE eats a dot,
    /// matching the original Pac-Man's ~15% chomp slowdown.
    private let chompPenalty: TimeInterval = 0.025
    private var isMoving = false
    private var lastMove: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0

    init(spawnGrid: CGPoint, gridMap: GridMap, sound: SoundManager) {
        self.grid = spawnGrid
        self.gridMap = gridMap
        self.sound = sound
        self.node = PixelPerson(
            bodyColor: .systemTeal,
            tieColor: .systemBlue,
            hairColor: NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1),
            walkExaggeration: 1
        )
        configureNode()
    }

    private func configureNode() {
        node.name = "PETE"
        node.position = gridMap.point(for: grid)
        let tag = SKLabelNode(fontNamed: "Menlo-Bold")
        tag.text = "PETE"
        tag.fontSize = 9
        tag.fontColor = .white
        tag.position = CGPoint(x: 0, y: 24)
        node.addChild(tag)
        node.physicsBody = SKPhysicsBody(circleOfRadius: 12)
        node.physicsBody?.allowsRotation = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.worker
        node.physicsBody?.contactTestBitMask = PhysicsCategory.dot | PhysicsCategory.boss | PhysicsCategory.machine | PhysicsCategory.tpsBox | PhysicsCategory.powerPellet | PhysicsCategory.fish
        node.physicsBody?.collisionBitMask = PhysicsCategory.wall
        node.zPosition = 10
    }

    func queueDirection(_ direction: MoveDirection) {
        queuedDirection = direction
        if self.direction == nil { self.direction = direction }
    }

    /// Pushes the next-step gate forward by the chomp penalty so PETE
    /// briefly slows after eating a dot.
    func applyChompDelay() {
        lastMove += chompPenalty
    }

    func resetMotion() {
        direction = nil
        queuedDirection = nil
        isMoving = false
        lastMove = 0
        node.removeAction(forKey: "workerMove")
        node.stopWalking()
    }

    func teleport(to grid: CGPoint) {
        self.grid = grid
        node.position = gridMap.point(for: grid)
        node.run(SKAction.move(to: gridMap.point(for: grid), duration: 0.2))
    }

    func flashColor(_ color: NSColor, restoringTo restoreColor: NSColor, after seconds: TimeInterval) {
        node.setBodyColor(color)
        let restore = restoreColor
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.node.setBodyColor(restore)
        }
    }

    /// Called each scene `update`. Honors the turn buffer: tries the
    /// queued direction first (and consumes it only when walkable);
    /// otherwise continues in the current direction. Queue persists
    /// until honored or replaced by new input.
    func update(currentTime: TimeInterval) {
        lastUpdateTime = currentTime
        guard !isMoving, currentTime - lastMove > moveInterval else { return }
        attemptStep()
    }

    private func attemptStep() {
        if let queued = queuedDirection,
           gridMap.isWalkable(neighbor(of: grid, in: queued)) {
            direction = queued
            queuedDirection = nil
        }
        guard let direction else { return }
        let next = neighbor(of: grid, in: direction)
        guard gridMap.isWalkable(next) else {
            node.stopWalking()
            return
        }
        lastMove = lastUpdateTime
        startStep(toward: next, direction: direction)
    }

    private func startStep(toward next: CGPoint, direction: MoveDirection) {
        isMoving = true
        grid = next
        node.startWalking()
        sound.playFootstep()
        node.run(.sequence([
            SKAction.move(to: gridMap.point(for: next), duration: moveDuration),
            .run { [weak self] in
                guard let self else { return }
                self.delegate?.workerDidEnterTile(next)
                if let partner = self.gridMap.tunnelPartner(of: next),
                   self.gridMap.isWalkable(partner) {
                    self.node.position = self.gridMap.point(for: partner)
                    self.grid = partner
                    self.delegate?.workerDidEnterTile(partner)
                }
                self.isMoving = false
                self.lastMove = self.lastUpdateTime
                if self.delegate?.isGameOver == false {
                    self.attemptStep()
                }
            }
        ]), withKey: "workerMove")
    }

    private func neighbor(of grid: CGPoint, in direction: MoveDirection) -> CGPoint {
        let d = direction.delta
        return CGPoint(x: Int(grid.x) + d.dx, y: Int(grid.y) + d.dy)
    }
}
