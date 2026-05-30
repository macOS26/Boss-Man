import SpriteKit

// Web-only SpriteFactory extras. The wasm port builds the maze from live nodes
// (apple bakes a CoreGraphics texture in MazeBuilder) and centralizes the
// cubicle + flee palette and the per-blueprint boss here; apple keeps those in
// GameScene / LevelEditorScene / BossController. The shared pickups + pixel
// people live in the common SpriteFactory.
extension SpriteFactory {

    static let fleeBodyColor = SKColor.systemBlue.blended(withFraction: 0.20, of: .black) ?? .systemBlue
    static let fleeEyeColor  = SKColor.systemBlue.blended(withFraction: 0.50, of: .black) ?? .systemBlue
    static let fleeSkinColor = SKColor(calibratedRed: 0.62, green: 0.78, blue: 0.96, alpha: 1)
    static let fleeTieColor  = fleeSkinColor

    static let cubicleColors: [SKColor] = [
        .systemBlue,   .systemTeal, .systemIndigo, .systemGreen,  .systemPink, .systemBrown,
        .systemPurple, .systemRed,  .systemOrange, .systemYellow, .systemCyan, .systemGray,
    ]
    static let wallTrimColor     = SKColor.systemGray
    static let mazeBackground    = SKColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)
    static let floorTileA        = SKColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    static let floorTileB        = SKColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 1)
    static let floorTileStroke   = SKColor(calibratedWhite: 0.16, alpha: 1)

    // The basic field dot: a tiny yellow square the pellets Pete sweeps up by
    // walking over them (apple bakes the same square into the tilemap texture).
    static func dotVisual(size: CGFloat = 6) -> SKShapeNode {
        let n = SKShapeNode(rectOf: CGSize(width: size, height: size))
        n.fillColor = .systemYellow
        n.strokeColor = .clear
        n.isAntialiased = false
        return n
    }

    // A single floor tile — a near-black square with a one-pixel darker edge.
    // The two shades alternate by (col+row) parity to produce the checker the
    // macOS edition bakes into its background texture.
    static func floorTile(size: CGFloat, alternate: Bool) -> SKShapeNode {
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let n = SKShapeNode(rect: rect)
        n.fillColor = alternate ? floorTileA : floorTileB
        n.strokeColor = floorTileStroke
        n.lineWidth = 1
        n.isAntialiased = false
        return n
    }

    // A single cubicle wall tile — three stacked shapes: an inset translucent
    // fill, an inset solid-color panel stroke, and a horizontal gray trim band
    // high on the tile. The caller passes whichever per-level cubicle color slot
    // the level lands on.
    static func wallTile(size: CGFloat, color: SKColor = cubicleColors[0]) -> SKNode {
        let n = SKNode()

        let fillRect = CGRect(x: -(size - 2) / 2, y: -(size - 2) / 2,
                              width: size - 2, height: size - 2)
        let fill = SKShapeNode(rect: fillRect)
        fill.fillColor = color.withAlphaComponent(0.55)
        fill.strokeColor = .clear
        fill.isAntialiased = false
        n.addChild(fill)

        let strokeRect = CGRect(x: -(size - 4) / 2, y: -(size - 4) / 2,
                                width: size - 4, height: size - 4)
        let stroke = SKShapeNode(rect: strokeRect)
        stroke.fillColor = .clear
        stroke.strokeColor = color
        stroke.lineWidth = 2
        stroke.isAntialiased = false
        n.addChild(stroke)

        let trimWidth = size - 10
        let trimRect = CGRect(x: -trimWidth / 2, y: 6,
                              width: trimWidth, height: 4)
        let trim = SKShapeNode(rect: trimRect)
        trim.fillColor = wallTrimColor
        trim.strokeColor = .clear
        trim.isAntialiased = false
        n.addChild(trim)

        return n
    }

    // Boss visual for a blueprint index, colors from the shared BossBlueprint.
    // On MIB levels every boss is an all-black suit + tie with sunglasses;
    // sunglasses are never a per-boss trait otherwise.
    static func bossPersonForBlueprint(_ index: Int, mib: Bool = false) -> PixelPerson {
        if mib {
            return bossPerson(bodyColor: .black, tieColor: .black, wearsSunglasses: true)
        }
        let c = BossBlueprint.colors[min(max(index, 0), BossBlueprint.colors.count - 1)]
        return bossPerson(bodyColor: c.body, tieColor: c.tie)
    }
}
