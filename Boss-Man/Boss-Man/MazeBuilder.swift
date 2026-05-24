import AppKit
import SpriteKit

@MainActor
final class MazeBuilder {
    let map: GridMap
    let goldDiscPositions: [CGPoint]
    let machineNames: [Character: String]
    var cubicleColor: NSColor = .systemBlue
    var debugSkipDots: Bool = false
    private(set) var placedGoldDiscs: Int = 0

    private(set) var workerSpawnFromMap: CGPoint?
    // Ordered list — duplicate blueprintIndex values are allowed so a level can
    // place multiple bosses of the same type, or more than 4 bosses total.
    private(set) var bossSpawnsFromMap: [(blueprintIndex: Int, position: CGPoint)] = []
    private(set) var goldDiscPositionsFromMap: [CGPoint] = []

    private var pelletTexture: SKTexture!
    private var dotTilemap: SKTileMapNode?
    private(set) var dotPresence: [[Bool]] = []

    init(map: GridMap, goldDiscPositions: [CGPoint], machineNames: [Character: String]) {
        self.map = map
        self.goldDiscPositions = goldDiscPositions
        self.machineNames = machineNames
    }

    @discardableResult
    func build(in scene: SKScene) -> Int {
        rebuildTextures()
        var dotCount = 0
        var wallCenters: [CGPoint] = []
        let cols = map.rows.first?.count ?? 0
        let rowCount = map.rows.count
        dotPresence = Array(repeating: Array(repeating: false, count: cols), count: rowCount)
        workerSpawnFromMap = nil
        bossSpawnsFromMap = []
        goldDiscPositionsFromMap = []

        let background = makeBackground()
        scene.addChild(background)

        let dotMap = makeDotTilemap(columns: cols, rows: rowCount)
        scene.addChild(dotMap)
        dotTilemap = dotMap
        let dotGroup = dotMap.tileSet.tileGroups.first!

        for (rowIndex, row) in map.rows.reversed().enumerated() {
            for (columnIndex, char) in row.enumerated() {
                let grid = CGPoint(x: columnIndex, y: rowIndex)
                let position = map.point(for: grid)
                if char == Strings.Tile.wallChar {
                    wallCenters.append(position)
                } else {
                    if (char == Strings.Tile.dotChar || char == Strings.Tile.hideoutChar) && !debugSkipDots {
                        dotPresence[rowIndex][columnIndex] = true
                        dotMap.setTileGroup(dotGroup, forColumn: columnIndex, row: rowIndex)
                        dotCount += 1
                    }
                    if let name = machineNames[char], char != Strings.Tile.brownBoxChar {
                        addMachine(name: name, symbol: String(char), at: position, in: scene)
                    } else if char == Strings.Tile.brownBoxChar {
                        addBrownBox(at: position, in: scene)
                    }
                    switch char {
                    case Strings.Tile.goldDiscChar: goldDiscPositionsFromMap.append(grid)
                    case Strings.Tile.workerChar:   workerSpawnFromMap = grid
                    case Strings.Tile.boss1Char:    bossSpawnsFromMap.append((0, grid))
                    case Strings.Tile.boss2Char:    bossSpawnsFromMap.append((1, grid))
                    case Strings.Tile.boss3Char:    bossSpawnsFromMap.append((2, grid))
                    case Strings.Tile.boss4Char:    bossSpawnsFromMap.append((3, grid))
                    default: break
                    }
                }
            }
        }

        addWallPhysics(centers: wallCenters, in: scene)

        placedGoldDiscs = 0
        let discsToPlace = goldDiscPositionsFromMap.isEmpty
            ? goldDiscPositions
            : goldDiscPositionsFromMap
        for grid in discsToPlace where map.isWalkable(grid) {
            addGoldDisc(at: map.point(for: grid), in: scene)
            placedGoldDiscs += 1
        }
        return dotCount
    }

    @discardableResult
    func collectDot(atColumn column: Int, row: Int) -> Bool {
        guard row >= 0, row < dotPresence.count,
              column >= 0, column < dotPresence[row].count,
              dotPresence[row][column] else { return false }
        dotPresence[row][column] = false
        dotTilemap?.setTileGroup(nil, forColumn: column, row: row)
        return true
    }

    func grayOutMachine(_ body: SKPhysicsBody, cooldown: TimeInterval = 15) {
        let machineNode = body.node
        machineNode?.alpha = 0.55
        body.contactTestBitMask = 0
        machineNode?.removeAction(forKey: Strings.ActionKey.machineCooldown)
        machineNode?.run(.sequence([
            .wait(forDuration: cooldown),
            .run { [weak machineNode] in
                machineNode?.alpha = 1
                machineNode?.physicsBody?.contactTestBitMask = PhysicsCategory.worker
            }
        ]), withKey: Strings.ActionKey.machineCooldown)
    }

    func resetGrayedMachines(in scene: SKScene, names: [String]) {
        for child in scene.children {
            guard let n = child.name, names.contains(n) else { continue }
            child.removeAction(forKey: Strings.ActionKey.machineCooldown)
            child.alpha = 1
            child.physicsBody?.contactTestBitMask = PhysicsCategory.worker
        }
    }

    private func makeDotTilemap(columns: Int, rows: Int) -> SKTileMapNode {
        let tile = map.tileSize
        let dotSize: CGFloat = 6
        let textureImage = renderImage(size: CGSize(width: tile, height: tile)) {
            NSColor.systemYellow.setFill()
            let rect = CGRect(x: (tile - dotSize) / 2,
                              y: (tile - dotSize) / 2,
                              width: dotSize, height: dotSize)
            NSBezierPath(rect: rect).fill()
        }
        let texture = SKTexture(image: textureImage)
        let definition = SKTileDefinition(texture: texture, size: CGSize(width: tile, height: tile))
        let group = SKTileGroup(tileDefinition: definition)
        let tileSet = SKTileSet(tileGroups: [group])
        let map = SKTileMapNode(tileSet: tileSet,
                                columns: columns,
                                rows: rows,
                                tileSize: CGSize(width: tile, height: tile))
        map.anchorPoint = .zero
        map.position = CGPoint(x: -1, y: 0)
        map.zPosition = 5
        return map
    }

    private func makeBackground() -> SKSpriteNode {
        let cols = map.rows.first?.count ?? 30
        let rows = map.rows.count
        let tile = map.tileSize
        // +1 on width: the maze visual is shifted 1px left elsewhere,
        // so the background grows 1px to the right to keep its right
        // edge aligned with the scene.
        let size = CGSize(width: CGFloat(cols) * tile + 1, height: CGFloat(rows) * tile)
        let color = cubicleColor
        let image = renderImage(size: size) {
            for (rowIndex, row) in self.map.rows.reversed().enumerated() {
                for (columnIndex, char) in row.enumerated() {
                    let rect = CGRect(x: CGFloat(columnIndex) * tile,
                                      y: CGFloat(rowIndex) * tile,
                                      width: tile, height: tile)
                    let alternate = (rowIndex + columnIndex).isMultiple(of: 2)
                    let floorColor: NSColor = alternate
                        ? NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
                        : NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 1)
                    floorColor.setFill()
                    NSBezierPath(rect: rect).fill()
                    NSColor(calibratedWhite: 0.16, alpha: 1).setStroke()
                    let edge = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
                    edge.lineWidth = 1
                    edge.stroke()
                    if char == Strings.Tile.wallChar {
                        let fillRect = rect.insetBy(dx: 1, dy: 1)
                        color.withAlphaComponent(0.55).setFill()
                        NSBezierPath(rect: fillRect).fill()
                        color.setStroke()
                        let strokePath = NSBezierPath(rect: fillRect.insetBy(dx: 1, dy: 1))
                        strokePath.lineWidth = 2
                        strokePath.stroke()
                        NSColor.systemGray.setFill()
                        let trimRect = CGRect(x: rect.minX + 5, y: rect.minY + tile / 2 + 6,
                                              width: tile - 10, height: 4)
                        NSBezierPath(rect: trimRect).fill()
                    }
                }
            }
        }
        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = .zero
        sprite.position = CGPoint(x: -1, y: 0)
        sprite.zPosition = 0
        return sprite
    }

    private func addWallPhysics(centers: [CGPoint], in scene: SKScene) {
        guard !centers.isEmpty else { return }
        let tile = map.tileSize
        let bodySize = CGSize(width: tile, height: tile)
        let parts = centers.map { SKPhysicsBody(rectangleOf: bodySize, center: $0) }
        let compound = SKPhysicsBody(bodies: parts)
        compound.isDynamic = false
        compound.categoryBitMask = PhysicsCategory.wall
        let node = SKNode()
        node.physicsBody = compound
        scene.addChild(node)
    }

    private func rebuildTextures() {
        pelletTexture = makePelletTexture()
    }

    private func renderImage(size: CGSize, draw: @escaping () -> Void) -> NSImage {
        return NSImage(size: size, flipped: false) { _ in
            draw()
            return true
        }
    }

    private func makePelletTexture() -> SKTexture {
        let size = CGSize(width: 24, height: 24)
        let image = renderImage(size: size) {
            NSColor.systemYellow.setFill()
            NSBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)).fill()
            NSColor.white.setStroke()
            let stroke = NSBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
            stroke.lineWidth = 2
            stroke.stroke()
        }
        return SKTexture(image: image)
    }

    private func addGoldDisc(at position: CGPoint, in scene: SKScene) {
        let disc = SKNode()
        disc.position = position
        disc.zPosition = 6
        let radius = map.tileSize * 0.28
        let halo = SKShapeNode(circleOfRadius: radius * 1.35)
        halo.fillColor = NSColor.systemYellow.withAlphaComponent(0.30)
        halo.strokeColor = .clear
        disc.addChild(halo)
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = .systemYellow
        core.strokeColor = NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.0, alpha: 1)
        core.lineWidth = 1
        disc.addChild(core)
        disc.physicsBody = SKPhysicsBody(circleOfRadius: 11)
        disc.physicsBody?.isDynamic = false
        disc.physicsBody?.categoryBitMask = PhysicsCategory.goldDisc
        disc.run(.repeatForever(.sequence([
            .scale(to: 1.25, duration: 0.35),
            .scale(to: 1.0, duration: 0.35)
        ])))
        scene.addChild(disc)
    }

    private func addMachine(name: String, symbol: String, at position: CGPoint, in scene: SKScene) {
        let machine = SKNode()
        machine.name = name
        machine.position = position
        machine.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 28))
        machine.physicsBody?.isDynamic = false
        machine.physicsBody?.categoryBitMask = PhysicsCategory.machine
        machine.zPosition = 6
        scene.addChild(machine)

        let label = SKLabelNode()
        label.text = MazeBuilder.emoji(forSymbol: symbol)
        label.fontSize = 26
        label.verticalAlignmentMode = .center
        label.position = .zero
        machine.addChild(label)
    }

    static func emoji(forSymbol symbol: String) -> String {
        switch symbol {
        case Strings.Tile.printer:    return Strings.Emoji.printer
        case Strings.Tile.fax:        return Strings.Emoji.fax
        case Strings.Tile.coverSheet: return Strings.Emoji.coverSheet
        case Strings.Tile.bookBinder: return Strings.Emoji.bookBinder
        case Strings.Tile.brownBox:   return Strings.Emoji.brownBox
        default: return symbol
        }
    }

    private func addBrownBox(at position: CGPoint, in scene: SKScene) {
        let box = SKNode()
        box.name = Strings.Machine.brownBox
        box.position = position
        box.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 28))
        box.physicsBody?.isDynamic = false
        box.physicsBody?.categoryBitMask = PhysicsCategory.tpsBox
        box.zPosition = 4
        scene.addChild(box)

        let label = SKLabelNode()
        label.text = Strings.Emoji.brownBox
        label.fontSize = 28
        label.verticalAlignmentMode = .center
        label.position = .zero
        box.addChild(label)
    }
}
