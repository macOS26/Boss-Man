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

    static let bossShoeGoldColor = SKColor(red: 0.7, green: 0.5, blue: 0.0, alpha: 1)
    // Frighten-mode palette. bossman-apple computes these as
    //   systemBlue.blended(0.20 of black)  for body
    //   systemBlue.blended(0.50 of black)  for eyes
    //   systemYellow                       for the tie
    // We bake the same RGB values directly. Gold tie outline reuses
    // bossShoeGoldColor.
    static let fleeBodyColor = SKColor(red: 0.0,  green: 0.384, blue: 0.8,  alpha: 1)
    static let fleeEyeColor  = SKColor(red: 0.0,  green: 0.24,  blue: 0.5,  alpha: 1)
    // Frighten-mode skin AND tie use the same blue tint: R and B swapped
    // from the base skin (0.96, 0.78, 0.62) so per-channel brightness is
    // preserved. The tie just inherits the skin color so the figure reads
    // as monochromatic blue from the chest up.
    static let fleeSkinColor = SKColor(red: 0.62, green: 0.78,  blue: 0.96, alpha: 1)
    static let fleeTieColor  = fleeSkinColor
    // Cubicle palette — bossman-apple cycles through 12 macOS system
    // colors by level, painting each floor's walls a different hue. The
    // RGB values here mirror the equivalent NSColor.system* values.
    static let cubicleColors: [SKColor] = [
        SKColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1),   // systemBlue
        SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1),   // systemTeal
        SKColor(red: 0.34, green: 0.34, blue: 0.84, alpha: 1),   // systemIndigo
        SKColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1),   // systemGreen
        SKColor(red: 1.00, green: 0.18, blue: 0.33, alpha: 1),   // systemPink
        SKColor(red: 0.64, green: 0.52, blue: 0.37, alpha: 1),   // systemBrown
        SKColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1),   // systemPurple
        SKColor(red: 1.00, green: 0.27, blue: 0.23, alpha: 1),   // systemRed
        SKColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),   // systemOrange
        SKColor(red: 1.00, green: 0.80, blue: 0.00, alpha: 1),   // systemYellow
        SKColor(red: 0.32, green: 0.77, blue: 0.93, alpha: 1),   // systemCyan
        SKColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1),   // systemGray
    ]
    static let wallTrimColor     = SKColor(white: 0.55, alpha: 1)
    static let mazeBackground    = SKColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
    // Floor checker: two near-black shades that alternate (rowIndex+columnIndex)
    // so the maze surface has the same subtle texture as the macOS edition.
    static let floorTileA        = SKColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    static let floorTileB        = SKColor(red: 0.09, green: 0.10, blue: 0.11, alpha: 1)
    static let floorTileStroke   = SKColor(white: 0.16, alpha: 1)
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

    // The basic field dot: a tiny yellow SQUARE (6×6 in the macOS edition,
    // baked into the tilemap texture). No stroke, no halo — these are the
    // pellets Pete sweeps up by walking over them.
    static func dotVisual(size: CGFloat = 6) -> SKShapeNode {
        let n = SKShapeNode(rectOf: CGSize(width: size, height: size))
        n.fillColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)   // systemYellow
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
    // Boss visual for a blueprint index. Colors are verbatim from bossman-apple's
    // blueprint table. On MIB levels (12, 24) `mib` is true and EVERY boss becomes
    // an all-black suit + black tie with sunglasses (apple's themed() override +
    // wearsSunglasses: isMIBLevel). Sunglasses appear ONLY on MIB levels — they
    // are never a per-boss trait.
    static func bossPersonForBlueprint(_ index: Int, mib: Bool = false) -> PixelPerson {
        if mib {
            return bossPerson(bodyColor: .black, tieColor: .black, wearsSunglasses: true)
        }
        switch index {
        case 0:  return bossPerson(bodyColor: SKColor(red: 1.00, green: 0.27, blue: 0.23, alpha: 1),     // systemRed
                                   tieColor:  .black)
        case 1:  return bossPerson(bodyColor: SKColor(red: 1.00, green: 0.18, blue: 0.33, alpha: 0.75),  // systemPink @0.75
                                   tieColor:  SKColor(red: 0.414, green: 0.192, blue: 0.522, alpha: 1))  // systemPurple blended .40 black
        case 2:  return bossPerson(bodyColor: SKColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1),     // systemTeal
                                   tieColor:  SKColor(red: 0.00, green: 0.384, blue: 0.80, alpha: 1))    // systemBlue blended .20 black
        default: return bossPerson(bodyColor: SKColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),     // systemOrange
                                   tieColor:  SKColor(red: 0.90, green: 0.243, blue: 0.207, alpha: 1))   // systemRed blended .10 black
        }
    }
}
