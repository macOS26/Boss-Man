import AppKit
import SpriteKit

@MainActor
final class MazeBuilder {
    let map: GridMap
    let powerPelletPositions: [CGPoint]
    let machineNames: [Character: String]
    var cubicleColor: NSColor = .systemBlue

    private var pelletTexture: SKTexture!
    private var deskTexture: SKTexture!
    private var dotTilemap: SKTileMapNode?
    private(set) var dotPresence: [[Bool]] = []

    init(map: GridMap, powerPelletPositions: [CGPoint], machineNames: [Character: String]) {
        self.map = map
        self.powerPelletPositions = powerPelletPositions
        self.machineNames = machineNames
    }

    /// Builds the maze contents into the scene and returns the number of dots placed.
    @discardableResult
    func build(in scene: SKScene) -> Int {
        rebuildTextures()
        var dotCount = 0
        var wallCenters: [CGPoint] = []
        let cols = map.rows.first?.count ?? 0
        let rowCount = map.rows.count
        dotPresence = Array(repeating: Array(repeating: false, count: cols), count: rowCount)

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
                if char == "#" {
                    wallCenters.append(position)
                } else {
                    if char == "." || char == "H" {
                        dotPresence[rowIndex][columnIndex] = true
                        dotMap.setTileGroup(dotGroup, forColumn: columnIndex, row: rowIndex)
                        dotCount += 1
                    }
                    if let name = machineNames[char], char != "D" {
                        addMachine(name: name, symbol: String(char), at: position, in: scene)
                    } else if char == "D" {
                        addDesk(at: position, in: scene)
                    }
                }
            }
        }

        addWallPhysics(centers: wallCenters, in: scene)

        for grid in powerPelletPositions where map.isWalkable(grid) {
            addPowerPellet(at: map.point(for: grid), in: scene)
        }
        return dotCount
    }

    /// Returns true if a dot was present (and is now removed) at the given grid cell.
    @discardableResult
    func collectDot(atColumn column: Int, row: Int) -> Bool {
        guard row >= 0, row < dotPresence.count,
              column >= 0, column < dotPresence[row].count,
              dotPresence[row][column] else { return false }
        dotPresence[row][column] = false
        dotTilemap?.setTileGroup(nil, forColumn: column, row: row)
        return true
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
        map.position = .zero
        map.zPosition = 5
        return map
    }

    private func makeBackground() -> SKSpriteNode {
        let cols = map.rows.first?.count ?? 30
        let rows = map.rows.count
        let tile = map.tileSize
        let size = CGSize(width: CGFloat(cols) * tile, height: CGFloat(rows) * tile)
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
                    if char == "#" {
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
        sprite.position = .zero
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
        deskTexture = makeDeskTexture()
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

    private func makeDeskTexture() -> SKTexture {
        let size = CGSize(width: 30, height: 22)
        let image = renderImage(size: size) {
            NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.10, alpha: 1).setFill()
            let body = CGRect(x: 2, y: 2, width: 26, height: 18)
            NSBezierPath(rect: body).fill()
            NSColor.systemOrange.setStroke()
            let stroke = NSBezierPath(rect: body)
            stroke.lineWidth = 1
            stroke.stroke()
        }
        return SKTexture(image: image)
    }

    private func addPowerPellet(at position: CGPoint, in scene: SKScene) {
        let pellet = SKSpriteNode(texture: pelletTexture)
        pellet.position = position
        pellet.physicsBody = SKPhysicsBody(circleOfRadius: 14)
        pellet.physicsBody?.isDynamic = false
        pellet.physicsBody?.categoryBitMask = PhysicsCategory.powerPellet
        pellet.zPosition = 6
        pellet.run(.repeatForever(.sequence([
            .scale(to: 1.25, duration: 0.35),
            .scale(to: 1.0, duration: 0.35)
        ])))
        scene.addChild(pellet)
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
        case "P": return "🖨️"
        case "F": return "📠"
        case "C": return "📄"
        case "M": return "📚"
        case "D": return "📥"
        default: return symbol
        }
    }

    private func addDesk(at position: CGPoint, in scene: SKScene) {
        let desk = SKSpriteNode(texture: deskTexture)
        desk.position = position
        desk.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 24))
        desk.physicsBody?.isDynamic = false
        desk.physicsBody?.categoryBitMask = PhysicsCategory.tpsBox
        desk.zPosition = 4
        scene.addChild(desk)
    }
}
