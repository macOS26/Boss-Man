import SpriteKit

// MARK: - Single source of truth for all repeated sprite appearances.
// MazeBuilder, LevelEditorScene, BossController, WorkerController, and HUD
// all call these. Never duplicate sprite construction — add it here.
//
// The wasm port keeps the macOS visual vocabulary but the palette is
// re-grounded on SKColor (no NSColor calibratedRed). Where the original
// shipped a fully-detailed pixel body, the first wasm pass uses a simpler
// stand-in; iterating only changes this file, not the call sites.
// Helper: SpriteKit's macOS API has SKTexture(imageNamed:) returning an
// always-valid (potentially placeholder) texture. We need a nil-returning
// variant for code paths that want to fall back to an SKLabelNode when the
// preloaded image isn't registered. img_by_name returns 0 when unknown,
// so we sniff that via the texture's size (0x0 == not loaded).
func textureNamed(_ name: String) -> SKTexture? {
    let t = SKTexture(imageNamed: name)
    return (t.size.width > 0 && t.size.height > 0) ? t : nil
}

enum SpriteFactory {

    static let bossShoeGoldColor = SKColor(calibratedRed: 0.7, green: 0.5, blue: 0.0, alpha: 1)

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

    // MARK: - Pickups

    static func goldDiscVisual(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let halo = SKShapeNode(circleOfRadius: radius * 1.35)
        halo.fillColor = SKColor.systemYellow.withAlphaComponent(0.30)
        halo.strokeColor = .clear
        node.addChild(halo)
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = SKColor.systemYellow.withAlphaComponent(0.85)
        core.strokeColor = bossShoeGoldColor
        core.lineWidth = 1
        node.addChild(core)
        let specular = SKShapeNode(circleOfRadius: radius * 0.3)
        specular.fillColor = SKColor(calibratedWhite: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.28, y: radius * 0.28)
        node.addChild(specular)
        return node
    }

    static func waterPelletVisual(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let halo = SKShapeNode(circleOfRadius: radius * 1.35)
        halo.fillColor = SKColor.systemCyan.withAlphaComponent(0.25)
        halo.strokeColor = .clear
        node.addChild(halo)
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = SKColor.systemCyan.withAlphaComponent(0.85)
        core.strokeColor = .systemBlue
        core.lineWidth = 1.5
        node.addChild(core)
        let specular = SKShapeNode(circleOfRadius: radius * 0.3)
        specular.fillColor = SKColor(calibratedWhite: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.28, y: radius * 0.28)
        node.addChild(specular)
        return node
    }

    // The basic field dot: a tiny yellow SQUARE (6×6 in the macOS edition,
    // baked into the tilemap texture). No stroke, no halo — these are the
    // pellets Pete sweeps up by walking over them.
    static func dotVisual(size: CGFloat = 6) -> SKShapeNode {
        let n = SKShapeNode(rectOf: CGSize(width: size, height: size))
        n.fillColor = .systemYellow
        n.strokeColor = .clear
        n.isAntialiased = false
        return n
    }

    // MARK: - Walls + floor

    // A single floor tile — a near-black square with a one-pixel darker
    // edge. The two shades alternate by (col+row) parity to produce the
    // checker pattern the macOS edition bakes into its background texture.
    static func floorTile(size: CGFloat, alternate: Bool) -> SKShapeNode {
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let n = SKShapeNode(rect: rect)
        n.fillColor = alternate ? floorTileA : floorTileB
        n.strokeColor = floorTileStroke
        n.lineWidth = 1
        n.isAntialiased = false
        return n
    }

    // A single cubicle wall tile — three stacked shapes:
    //   1. inset 1px fill   (translucent cubicle color, floor reads through)
    //   2. inset 2px stroke (solid cubicle color, 2px lineWidth — panel edge)
    //   3. horizontal gray trim band high on the tile (the cubicle divider)
    // bossman-apple rotates the cubicle color per level (cubicleColors[]);
    // the caller passes whichever palette slot the level lands on.
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

        // Trim band, ~4px tall, top of the cubicle panel. macOS reference:
        //   y = rect.minY + tile/2 + 6,  height = 4
        // which is y in [6, 10] relative to a tile centred at origin.
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

    // MARK: - People

    static func bossPerson(bodyColor: SKColor, tieColor: SKColor, wearsSunglasses: Bool = false) -> PixelPerson {
        PixelPerson(
            bodyColor: bodyColor,
            tieColor: tieColor,
            hairColor: SKColor(calibratedRed: 0.55, green: 0.45, blue: 0.35, alpha: 1),
            shoeOutlineColor: bossShoeGoldColor,
            pantsColor: .darkGray,
            wearsSunglasses: wearsSunglasses,
            headYOffset: -1
        )
    }

    static func petePerson(walkExaggeration: CGFloat = 0) -> PixelPerson {
        PixelPerson(
            bodyColor: .systemBlue,
            tieColor:  .systemOrange,
            hairColor: SKColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: SKColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1),
            walkExaggeration: walkExaggeration
        )
    }

    // MARK: - Boss palette helpers
    // Each maze blueprint character (1..4) maps to one of these color schemes.
    // Boss visual for a blueprint index. Colors are verbatim from bossman-apple's
    // blueprint table. On MIB levels (12, 24) `mib` is true and EVERY boss becomes
    // an all-black suit + black tie with sunglasses (apple's themed() override +
    // wearsSunglasses: isMIBLevel). Sunglasses appear ONLY on MIB levels — they
    // are never a per-boss trait.
    static func bossPersonForBlueprint(_ index: Int, mib: Bool = false) -> PixelPerson {
        if mib {
            return bossPerson(bodyColor: .black, tieColor: .black, wearsSunglasses: true)
        }
        let c = BossBlueprint.colors[min(max(index, 0), BossBlueprint.colors.count - 1)]
        return bossPerson(bodyColor: c.body, tieColor: c.tie)
    }
}
