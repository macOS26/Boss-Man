import SpriteKit

// MARK: - Single source of truth for all repeated sprite appearances.
// MazeBuilder, LevelEditorScene, BossController, WorkerController, and HUD
// all call these. Never duplicate sprite construction — add it here.
//
// The wasm port keeps the macOS visual vocabulary but the palette is
// re-grounded on SKColor (no NSColor calibratedRed). Where the original
// shipped a fully-detailed pixel body, the first wasm pass uses a simpler
// stand-in; iterating only changes this file, not the call sites.
enum SpriteFactory {

    static let bossShoeGoldColor = SKColor(red: 0.7, green: 0.5, blue: 0.0, alpha: 1)
    static let wallFillColor     = SKColor(red: 0.16, green: 0.18, blue: 0.34, alpha: 1)
    static let wallStrokeColor   = SKColor(red: 0.30, green: 0.34, blue: 0.62, alpha: 1)
    static let mazeBackground    = SKColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
    static let dotColor          = SKColor(red: 1.0,  green: 0.85, blue: 0.55, alpha: 1)

    // MARK: - Pickups

    static func goldDiscVisual(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let halo = SKShapeNode(circleOfRadius: radius * 1.35)
        halo.fillColor = SKColor(red: 1, green: 0.84, blue: 0.0, alpha: 0.30)
        halo.strokeColor = .clear
        node.addChild(halo)
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = SKColor(red: 1, green: 0.84, blue: 0.0, alpha: 0.85)
        core.strokeColor = bossShoeGoldColor
        core.lineWidth = 1
        node.addChild(core)
        let specular = SKShapeNode(circleOfRadius: radius * 0.3)
        specular.fillColor = SKColor(white: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.28, y: radius * 0.28)
        node.addChild(specular)
        return node
    }

    static func waterPelletVisual(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let halo = SKShapeNode(circleOfRadius: radius * 1.35)
        halo.fillColor = SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 0.25)
        halo.strokeColor = .clear
        node.addChild(halo)
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 0.85)
        core.strokeColor = SKColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1)
        core.lineWidth = 1.5
        node.addChild(core)
        let specular = SKShapeNode(circleOfRadius: radius * 0.3)
        specular.fillColor = SKColor(white: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.28, y: radius * 0.28)
        node.addChild(specular)
        return node
    }

    // Pac-style pellet: yellow disc with a white stroke. Matches the macOS
    // pellet texture (an oval inset inside a 24×24 rect with a 2-wide white
    // stroke) so the maze reads the same across both editions.
    static func dotVisual(radius: CGFloat) -> SKShapeNode {
        let n = SKShapeNode(circleOfRadius: radius)
        n.fillColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)
        n.strokeColor = .white
        n.lineWidth = 2
        n.isAntialiased = true
        return n
    }

    // MARK: - Walls

    // A single wall tile — solid blue rectangle with a thin lighter outline.
    // MazeBuilder lays one of these at each '#' cell.
    static func wallTile(size: CGFloat) -> SKShapeNode {
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let n = SKShapeNode(rect: rect, cornerRadius: 2)
        n.fillColor = wallFillColor
        n.strokeColor = wallStrokeColor
        n.lineWidth = 1
        return n
    }

    // MARK: - People

    static func bossPerson(bodyColor: SKColor, tieColor: SKColor, wearsSunglasses: Bool = false) -> PixelPerson {
        PixelPerson(
            bodyColor: bodyColor,
            tieColor: tieColor,
            hairColor: SKColor(red: 0.55, green: 0.45, blue: 0.35, alpha: 1),
            shoeOutlineColor: bossShoeGoldColor,
            pantsColor: SKColor(white: 0.3, alpha: 1),
            wearsSunglasses: wearsSunglasses,
            headYOffset: -1
        )
    }

    static func petePerson(walkExaggeration: CGFloat = 0) -> PixelPerson {
        PixelPerson(
            bodyColor: SKColor(red: 0.20, green: 0.48, blue: 1.0, alpha: 1),
            tieColor:  SKColor(red: 1.0,  green: 0.55, blue: 0.0, alpha: 1),
            hairColor: SKColor(red: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: SKColor(red: 0.70, green: 0.45, blue: 0.18, alpha: 1),
            walkExaggeration: walkExaggeration
        )
    }

    // MARK: - Boss palette helpers
    // Each maze blueprint character (1..4) maps to one of these color schemes.
    static func bossPersonForBlueprint(_ index: Int) -> PixelPerson {
        switch index {
        case 0:  return bossPerson(bodyColor: SKColor(red: 0.95, green: 0.18, blue: 0.18, alpha: 1),
                                   tieColor:  SKColor(red: 0.2,  green: 0.2,  blue: 0.2,  alpha: 1))
        case 1:  return bossPerson(bodyColor: SKColor(red: 0.95, green: 0.55, blue: 0.18, alpha: 1),
                                   tieColor:  SKColor(red: 0.45, green: 0.25, blue: 0.05, alpha: 1))
        case 2:  return bossPerson(bodyColor: SKColor(red: 0.30, green: 0.60, blue: 0.95, alpha: 1),
                                   tieColor:  SKColor(red: 0.05, green: 0.20, blue: 0.55, alpha: 1),
                                   wearsSunglasses: true)
        default: return bossPerson(bodyColor: SKColor(red: 0.55, green: 0.85, blue: 0.45, alpha: 1),
                                   tieColor:  SKColor(red: 0.15, green: 0.40, blue: 0.10, alpha: 1))
        }
    }
}
