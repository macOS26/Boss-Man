import AppKit
import SpriteKit

@MainActor
protocol WorkerControllerDelegate: AnyObject {
    var isGameOver: Bool { get }
    func workerDidEnterTile(_ grid: CGPoint)
}

@MainActor
final class WorkerController {
    weak var delegate: WorkerControllerDelegate?
    let node: PixelPerson
    private(set) var grid: CGPoint
    private(set) var direction: MoveDirection?
    private(set) var queuedDirection: MoveDirection?

    private let gridMap: GridMap
    private let sound: SoundManager
    private let moveDuration: TimeInterval = 0.14
    private var isMoving = false

    init(spawnGrid: CGPoint, gridMap: GridMap, sound: SoundManager) {
        self.grid = spawnGrid
        self.gridMap = gridMap
        self.sound = sound
        self.node = PixelPerson(
            bodyColor: .systemBlue,
            tieColor: .systemOrange,
            hairColor: NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1),
            walkExaggeration: 1
        )
        configureNode()
    }

    private func configureNode() {
        node.name = Strings.Worker.pete
        node.position = gridMap.point(for: grid)
        let tag = SKLabelNode(fontNamed: Strings.Font.menloBold)
        tag.text = Strings.Worker.pete
        tag.fontSize = 9
        tag.fontColor = .white
        tag.position = CGPoint(x: 0, y: 24)
        node.addChild(tag)
        node.physicsBody = SKPhysicsBody(circleOfRadius: 10)
        node.physicsBody?.allowsRotation = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.worker
        node.physicsBody?.contactTestBitMask = PhysicsCategory.dot | PhysicsCategory.boss | PhysicsCategory.machine | PhysicsCategory.tpsBox | PhysicsCategory.goldDisc | PhysicsCategory.fish | PhysicsCategory.waterGun | PhysicsCategory.waterPellet
        node.physicsBody?.collisionBitMask = PhysicsCategory.wall
        node.zPosition = 10
    }

    func queueDirection(_ direction: MoveDirection) {
        queuedDirection = direction
        if self.direction == nil { self.direction = direction }
        if !isMoving { attemptStep() }
    }

    func resetMotion() {
        direction = nil
        queuedDirection = nil
        isMoving = false
        node.removeAction(forKey: Strings.ActionKey.workerMove)
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

    private(set) var isShielded = false

    func applySpawnShield() {
        node.removeAction(forKey: Strings.ActionKey.spawnShield)
        node.removeAction(forKey: Strings.ActionKey.spawnShieldBlink)
        node.setBodyColor(.systemBlue)
        node.setTieColor(.systemOrange)
        node.alpha = 1
        isShielded = true

        let blinkCycle = SKAction.sequence([
            .fadeAlpha(to: 0.35, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])
        node.run(.sequence([
            .repeat(blinkCycle, count: 1),
            .run { [weak self] in self?.node.alpha = 1 }
        ]), withKey: Strings.ActionKey.spawnShieldBlink)

        let waitBeforeUnshield: TimeInterval = 3.0

        node.run(.sequence([
            .wait(forDuration: waitBeforeUnshield),
            .run { [weak self] in self?.isShielded = false }
        ]), withKey: Strings.ActionKey.spawnShield)
    }

    private static func lerpColor(from a: NSColor, to b: NSColor, progress t: CGFloat) -> NSColor {
        let aRGB = a.usingColorSpace(.deviceRGB) ?? a
        let bRGB = b.usingColorSpace(.deviceRGB) ?? b
        let r = aRGB.redComponent + (bRGB.redComponent - aRGB.redComponent) * t
        let g = aRGB.greenComponent + (bRGB.greenComponent - aRGB.greenComponent) * t
        let bl = aRGB.blueComponent + (bRGB.blueComponent - aRGB.blueComponent) * t
        return NSColor(calibratedRed: r, green: g, blue: bl, alpha: 1)
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
        startStep(toward: next, direction: direction)
    }

    private func startStep(toward next: CGPoint, direction: MoveDirection) {
        isMoving = true
        grid = next
        node.startWalking()
        switch direction {
        case .left:  node.face(left: true)
        case .right: node.face(left: false)
        case .up, .down: break
        }
        node.setLookDirection(direction)
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
                if self.delegate?.isGameOver == false {
                    self.attemptStep()
                }
            }
        ]), withKey: Strings.ActionKey.workerMove)
    }

    private func neighbor(of grid: CGPoint, in direction: MoveDirection) -> CGPoint {
        let d = direction.delta
        return CGPoint(x: Int(grid.x) + d.dx, y: Int(grid.y) + d.dy)
    }
}
