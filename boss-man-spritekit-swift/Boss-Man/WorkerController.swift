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
    var worldPosition: CGPoint { mover.worldPosition }   // smooth tile-to-tile position (read by render-only scenes like ISOMETRIC)

    private let gridMap: GridMap
    private let sound: SoundManager
    private let moveDuration: TimeInterval = 0.14
    private var mover: TileMover<MoveDirection>!

    init(spawnGrid: CGPoint, gridMap: GridMap, sound: SoundManager, containerOriginX: CGFloat = 0) {
        self.grid = spawnGrid
        self.gridMap = gridMap
        self.sound = sound
        self.node = SpriteFactory.petePerson(walkExaggeration: 1)
        configureNode()
        mover = TileMover<MoveDirection>(node: node, spawn: spawnGrid, map: gridMap,
                                         step: moveDuration, containerOriginX: containerOriginX,
                                         tunnelSlowdown: 4)
    }

    private func configureNode() {
        node.name = Strings.Worker.pete
        node.position = gridMap.point(for: grid)
        let tagScale = SpriteFactory.worldRenderScale
        let tag = SKLabelNode(fontNamed: Strings.Font.menloBold)
        tag.text = Strings.Worker.pete
        tag.fontSize = 9 * tagScale
        tag.fontColor = .white
        tag.setScale(1 / tagScale)
        tag.position = CGPoint(x: 0, y: 24)
        node.addChild(tag)
        node.physicsBody = SKPhysicsBody(circleOfRadius: 10)
        node.physicsBody?.allowsRotation = false
        node.physicsBody?.isDynamic = false
        node.physicsBody?.affectedByGravity = false
        node.physicsBody?.velocity = CGVector.zero
        node.physicsBody?.categoryBitMask = PhysicsCategory.worker
        node.physicsBody?.contactTestBitMask = PhysicsCategory.dot | PhysicsCategory.boss | PhysicsCategory.machine | PhysicsCategory.tpsBox | PhysicsCategory.goldDisc | PhysicsCategory.fish | PhysicsCategory.waterGun | PhysicsCategory.waterPellet
        node.physicsBody?.collisionBitMask = 0 //PhysicsCategory.wall
        node.zPosition = 10
    }

    func queueDirection(_ direction: MoveDirection) {
        queuedDirection = direction
        if self.direction == nil { self.direction = direction }
    }

    func advance(_ dt: TimeInterval) {
        mover.advance(dt, decide: { [weak self] e in
            guard let self else { return nil }
            if let q = self.queuedDirection, e.canStep(q) { return q }
            if let d = self.direction,       e.canStep(d) { return d }
            return nil
        }, onArrive: { [weak self] e in
            guard let self else { return }
            self.grid = e.grid
            if let d = e.dir { self.node.setFacing(d) }
            self.sound.playFootstep()
            self.delegate?.workerDidEnterTile(e.grid)
        })
        self.grid = mover.grid
        self.direction = mover.dir
    }

    func resetMotion() {
        direction = nil
        queuedDirection = nil
        node.stopWalking()
        mover.reset(to: mover.grid)
    }

    func teleport(to grid: CGPoint) {
        self.grid = grid
        node.position = gridMap.point(for: grid)
        mover.reset(to: grid)
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

    // Pete's shield is driven by GameScene from the boss-flashing state (a boss is
    // immobilized while it spawns in), not a standalone timer: invincibility ends
    // the instant the bosses stop flashing. Mirrors the loop-driven boss
    // spawnGrace, avoids the wasm SKAction .run-after-wait that never fired and
    // left Pete permanently shielded.
    func setShielded(_ shielded: Bool) { isShielded = shielded }

    func applySpawnShield() {
        node.removeAction(forKey: Strings.ActionKey.spawnShieldBlink)
        node.setBodyColor(.systemBlue)
        node.setTieColor(.systemOrange)
        node.alpha = 1

        let blinkCycle = SKAction.sequence([
            .fadeAlpha(to: 0.35, duration: 0.6),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ])
        node.run(.sequence([
            .repeat(blinkCycle, count: 1),
            .run { [weak self] in self?.node.alpha = 1 }
        ]), withKey: Strings.ActionKey.spawnShieldBlink)
    }

    private static func lerpColor(from a: NSColor, to b: NSColor, progress t: CGFloat) -> NSColor {
        let aRGB = a.usingColorSpace(.deviceRGB) ?? a
        let bRGB = b.usingColorSpace(.deviceRGB) ?? b
        let r = aRGB.redComponent + (bRGB.redComponent - aRGB.redComponent) * t
        let g = aRGB.greenComponent + (bRGB.greenComponent - aRGB.greenComponent) * t
        let bl = aRGB.blueComponent + (bRGB.blueComponent - aRGB.blueComponent) * t
        return NSColor(calibratedRed: r, green: g, blue: bl, alpha: 1)
    }

}
