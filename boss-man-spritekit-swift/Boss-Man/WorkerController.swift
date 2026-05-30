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
    #if os(WASI)
    // Pete moves through the kit's continuous TileMover (same stepper the bosses
    // use), so there's no per-tile SKAction restart gap — that gap is what made
    // him stutter. apple keeps the SKAction path below (smooth on real
    // SpriteKit). Driven per frame by GameScene.update -> advance(_:).
    private var mover: TileMover<MoveDirection>!
    #endif

    init(spawnGrid: CGPoint, gridMap: GridMap, sound: SoundManager, containerOriginX: CGFloat = 0) {
        self.grid = spawnGrid
        self.gridMap = gridMap
        self.sound = sound
        self.node = SpriteFactory.petePerson(walkExaggeration: 1)
        configureNode()
        #if os(WASI)
        mover = TileMover<MoveDirection>(node: node, spawn: spawnGrid, map: gridMap,
                                         step: moveDuration, containerOriginX: containerOriginX)
        #endif
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
#if os(macOS)
        node.physicsBody?.isDynamic = true
#elseif os(WASI)
        node.physicsBody?.isDynamic = false
#endif
        node.physicsBody?.affectedByGravity = false
        node.physicsBody?.velocity = CGVector.zero
        node.physicsBody?.categoryBitMask = PhysicsCategory.worker
        node.physicsBody?.contactTestBitMask = PhysicsCategory.dot | PhysicsCategory.boss | PhysicsCategory.machine | PhysicsCategory.tpsBox | PhysicsCategory.goldDisc | PhysicsCategory.fish | PhysicsCategory.waterGun | PhysicsCategory.waterPellet
        node.physicsBody?.collisionBitMask = PhysicsCategory.wall
        node.zPosition = 10
    }

    func queueDirection(_ direction: MoveDirection) {
        queuedDirection = direction
        if self.direction == nil { self.direction = direction }
        #if os(macOS)
        if !isMoving { attemptStep() }
        #endif
        // wasm: the per-frame advance(_:) picks up queuedDirection; no kickoff.
    }

    #if os(WASI)
    // Per-frame continuous stepper (restored from the pre-WorkerController
    // peteMover). decide latches queued > current direction when walkable;
    // onArrive does the tile bookkeeping. No per-tile SKAction => gap-free,
    // exactly like the bosses.
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
    #endif

    func resetMotion() {
        direction = nil
        queuedDirection = nil
        node.stopWalking()
        #if os(macOS)
        isMoving = false
        node.removeAction(forKey: Strings.ActionKey.workerMove)
        #elseif os(WASI)
        mover.dir = nil
        mover.moving = false
        mover.moveT = 0
        #endif
    }

    func teleport(to grid: CGPoint) {
        self.grid = grid
        node.position = gridMap.point(for: grid)
        #if os(macOS)
        node.run(SKAction.move(to: gridMap.point(for: grid), duration: 0.2))
        #elseif os(WASI)
        mover.grid = grid
        mover.dir = nil
        mover.moving = false
        mover.moveT = 0
        #endif
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
