import AppKit
import SpriteKit

@MainActor
final class MazeBuilder {
    let map: GridMap
    let powerPelletPositions: [CGPoint]
    let machineNames: [Character: String]
    var cubicleColor: NSColor = .systemBlue

    init(map: GridMap, powerPelletPositions: [CGPoint], machineNames: [Character: String]) {
        self.map = map
        self.powerPelletPositions = powerPelletPositions
        self.machineNames = machineNames
    }

    /// Builds the maze contents into the scene and returns the number of dots placed.
    @discardableResult
    func build(in scene: SKScene) -> Int {
        var dotCount = 0
        for (rowIndex, row) in map.rows.reversed().enumerated() {
            for (columnIndex, char) in row.enumerated() {
                let grid = CGPoint(x: columnIndex, y: rowIndex)
                let position = map.point(for: grid)
                drawFloorTile(at: position, alternate: (rowIndex + columnIndex).isMultiple(of: 2), in: scene)

                if char == "#" {
                    drawCubicleWall(at: position, in: scene)
                } else {
                    if char == "." || char == "H" {
                        addDot(at: position, in: scene)
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

        for grid in powerPelletPositions where map.isWalkable(grid) {
            addPowerPellet(at: map.point(for: grid), in: scene)
        }
        return dotCount
    }

    private func drawFloorTile(at position: CGPoint, alternate: Bool, in scene: SKScene) {
        let tile = SKShapeNode(rectOf: CGSize(width: map.tileSize, height: map.tileSize))
        tile.position = position
        tile.fillColor = alternate
            ? NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
            : NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 1)
        tile.strokeColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        tile.lineWidth = 1
        tile.zPosition = 0
        scene.addChild(tile)
    }

    private func drawCubicleWall(at position: CGPoint, in scene: SKScene) {
        let tileSize = map.tileSize
        let wall = SKShapeNode(rectOf: CGSize(width: tileSize - 2, height: tileSize - 2))
        wall.position = position
        wall.fillColor = cubicleColor.withAlphaComponent(0.55)
        wall.strokeColor = cubicleColor
        wall.lineWidth = 2
        wall.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: tileSize, height: tileSize))
        wall.physicsBody?.isDynamic = false
        wall.physicsBody?.categoryBitMask = PhysicsCategory.wall
        wall.zPosition = 3
        scene.addChild(wall)

        let trim = SKShapeNode(rectOf: CGSize(width: tileSize - 10, height: 4))
        trim.position = CGPoint(x: 0, y: 8)
        trim.fillColor = .systemGray
        trim.strokeColor = .clear
        wall.addChild(trim)
    }

    private func addDot(at position: CGPoint, in scene: SKScene) {
        let dot = SKShapeNode(rectOf: CGSize(width: 6, height: 6))
        dot.position = position
        dot.fillColor = .systemYellow
        dot.strokeColor = .clear
        dot.physicsBody = SKPhysicsBody(circleOfRadius: 8)
        dot.physicsBody?.isDynamic = false
        dot.physicsBody?.categoryBitMask = PhysicsCategory.dot
        dot.zPosition = 5
        scene.addChild(dot)
    }

    private func addPowerPellet(at position: CGPoint, in scene: SKScene) {
        let pellet = SKShapeNode(circleOfRadius: 10)
        pellet.position = position
        pellet.fillColor = .systemYellow
        pellet.strokeColor = .white
        pellet.lineWidth = 2
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
        let machine = SKShapeNode(rectOf: CGSize(width: 26, height: 22))
        machine.name = name
        machine.position = position
        machine.fillColor = .clear
        machine.strokeColor = .clear
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
        let desk = SKShapeNode(rectOf: CGSize(width: 26, height: 18))
        desk.position = position
        desk.fillColor = NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.10, alpha: 1)
        desk.strokeColor = .systemOrange
        desk.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 24))
        desk.physicsBody?.isDynamic = false
        desk.physicsBody?.categoryBitMask = PhysicsCategory.tpsBox
        desk.zPosition = 4
        scene.addChild(desk)
    }
}
