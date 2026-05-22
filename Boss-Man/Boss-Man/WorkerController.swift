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
    private let moveDuration: TimeInterval = 0.14
    private var isMoving = false

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
        node.physicsBody = SKPhysicsBody(circleOfRadius: 10)
        node.physicsBody?.allowsRotation = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.worker
        node.physicsBody?.contactTestBitMask = PhysicsCategory.dot | PhysicsCategory.boss | PhysicsCategory.machine | PhysicsCategory.tpsBox | PhysicsCategory.goldDisc | PhysicsCategory.fish
        node.physicsBody?.collisionBitMask = PhysicsCategory.wall
        node.zPosition = 10
    }

    func queueDirection(_ direction: MoveDirection) {
        queuedDirection = direction
        if self.direction == nil { self.direction = direction }
        // Kick off motion immediately from rest — the chained SKAction
        // completion handler self-perpetuates from there, no per-frame
        // update loop required.
        if !isMoving { attemptStep() }
    }

    func resetMotion() {
        direction = nil
        queuedDirection = nil
        isMoving = false
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

    /// True while PETE is wearing the spawn-protection orange shield.
    /// Boss catch paths must skip if this is set.
    private(set) var isShielded = false

    /// Three-second spawn invulnerability:
    ///   • 0.0 – 1.2s  solid orange, single alpha pulse.
    ///   • 0.0 – 1.5s  contacts disabled.
    ///   • 1.5 – 3.0s  body color smoothly interpolates orange → teal.
    ///   • 3.0s        contacts re-armed, isShielded cleared.
    /// Cancels any prior shield in flight by reusing the "spawnShield"
    /// action key.
    func applySpawnShield() {
        node.removeAction(forKey: "spawnShield")
        node.removeAction(forKey: "spawnShieldBlink")
        let orange = NSColor.systemOrange
        let teal = NSColor.systemTeal
        node.setBodyColor(orange)
        node.alpha = 1
        node.physicsBody?.categoryBitMask = 0
        isShielded = true

        // Blink alpha 1.0 ↔ 0.35 for the first 2 seconds. Four
        // half-second cycles is a deliberate, readable pulse rather
        // than a stroboscopic flicker. Ends with an explicit reset to
        // alpha 1 so the subsequent color fade renders at full
        // visibility.
        let blinkCycle = SKAction.sequence([
            .fadeAlpha(to: 0.35, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])
        node.run(.sequence([
            .repeat(blinkCycle, count: 1),
            .run { [weak self] in self?.node.alpha = 1 }
        ]), withKey: "spawnShieldBlink")

        let fadeDuration: TimeInterval = 1.5
        let waitBeforeFade: TimeInterval = 1.5

        let fade = SKAction.customAction(withDuration: fadeDuration) { [weak self] _, elapsed in
            guard let self else { return }
            let t = CGFloat(elapsed) / CGFloat(fadeDuration)
            self.node.setBodyColor(WorkerController.lerpColor(from: orange, to: teal, progress: t))
        }

        node.run(.sequence([
            .wait(forDuration: waitBeforeFade),
            fade,
            .run { [weak self] in
                guard let self else { return }
                self.node.setBodyColor(teal)
                self.node.physicsBody?.categoryBitMask = PhysicsCategory.worker
                self.isShielded = false
            }
        ]), withKey: "spawnShield")
    }

    /// Linear-RGB interpolation between two NSColors. Converts both
    /// to deviceRGB first so .redComponent / .greenComponent /
    /// .blueComponent are safe to read on system colors (which are
    /// otherwise in catalog/named color spaces and throw at access).
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
        ]), withKey: "workerMove")
    }

    private func neighbor(of grid: CGPoint, in direction: MoveDirection) -> CGPoint {
        let d = direction.delta
        return CGPoint(x: Int(grid.x) + d.dx, y: Int(grid.y) + d.dy)
    }
}
