import AppKit
import SpriteKit

// MARK: - Single source of truth for the sprite appearances shared by both
// ports: the gold-disc / water-pellet pickups and the Pete / boss pixel people.
// Never duplicate sprite construction — add shared visuals here. Platform-only
// visuals live in a per-platform extension: the wasm port builds the maze from
// live nodes (cubicle / flee palette, floor + wall tiles, per-blueprint boss),
// while apple bakes those into textures in MazeBuilder and keeps its palette in
// GameScene / LevelEditorScene / BossController.
enum SpriteFactory {

    static let bossShoeGoldColor = SKColor(calibratedRed: 0.7, green: 0.5, blue: 0.0, alpha: 1)

    // Supersample factor for camera-magnified pickups/glyphs (see RenderScale).
    static let worldRenderScale = RenderScale.factor

    // MARK: - Pickups
    // Returns an SKNode containing halo + core + specular. Caller sets position,
    // zPosition, physicsBody, name, and animations.
    static func goldDiscVisual(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let inner = SKNode()
        inner.setScale(1 / worldRenderScale)
        node.addChild(inner)
        let r = radius * worldRenderScale
        let halo = SKShapeNode(circleOfRadius: r * 1.35)
        halo.fillColor = SKColor.systemYellow.withAlphaComponent(0.30)
        halo.strokeColor = .clear
        inner.addChild(halo)
        let core = SKShapeNode(circleOfRadius: r)
        core.fillColor = SKColor.systemYellow.withAlphaComponent(0.85)
        core.strokeColor = bossShoeGoldColor
        core.lineWidth = 1 * worldRenderScale
        inner.addChild(core)
        let specular = SKShapeNode(circleOfRadius: r * 0.3)
        specular.fillColor = SKColor(calibratedWhite: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -r * 0.28, y: r * 0.28)
        inner.addChild(specular)
        return node
    }

    static func waterPelletVisual(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let inner = SKNode()
        inner.setScale(1 / worldRenderScale)
        node.addChild(inner)
        let r = radius * worldRenderScale
        let halo = SKShapeNode(circleOfRadius: r * 1.35)
        halo.fillColor = SKColor.systemCyan.withAlphaComponent(0.25)
        halo.strokeColor = .clear
        inner.addChild(halo)
        let core = SKShapeNode(circleOfRadius: r)
        core.fillColor = SKColor.systemCyan.withAlphaComponent(0.85)
        core.strokeColor = .systemBlue
        core.lineWidth = 1.5 * worldRenderScale
        inner.addChild(core)
        let specular = SKShapeNode(circleOfRadius: r * 0.3)
        specular.fillColor = SKColor(calibratedWhite: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -r * 0.28, y: r * 0.28)
        inner.addChild(specular)
        return node
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
            tieColor: .systemOrange,
            hairColor: SKColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: SKColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1),
            walkExaggeration: walkExaggeration
        )
    }

    // Pete seen from behind (back of the head, no face/tie) for the 3D chase view.
    static func petePersonBack(walkExaggeration: CGFloat = 0) -> PixelPerson {
        PixelPerson(
            bodyColor: .systemBlue,
            tieColor: .systemOrange,
            hairColor: SKColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: SKColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1),
            walkExaggeration: walkExaggeration,
            backView: true
        )
    }

    // MARK: - Cubicle + frighten palette
    static let fleeBodyColor = SKColor.systemBlue.blended(withFraction: 0.20, of: .black) ?? .systemBlue
    static let fleeEyeColor  = SKColor.systemBlue.blended(withFraction: 0.50, of: .black) ?? .systemBlue
    static let fleeSkinColor = SKColor(calibratedRed: 0.62, green: 0.78, blue: 0.96, alpha: 1)
    static let fleeTieColor  = fleeSkinColor

    static let cubicleColors: [SKColor] = [
        .systemBlue,   .systemTeal, .systemIndigo, .systemGreen,  .systemPink, .systemBrown,
        .systemPurple, .systemRed,  .systemOrange, .systemYellow, .systemCyan, .systemGray,
    ]
    static let wallTrimColor   = SKColor.systemGray
    static let mazeBackground  = SKColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)
    static let floorTileA      = SKColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    static let floorTileB      = SKColor(calibratedRed: 0.09, green: 0.10, blue: 0.11, alpha: 1)
    static let floorTileStroke = SKColor(calibratedWhite: 0.16, alpha: 1)

    // Deterministic 0..1 noise (pure-Swift LCG, no system RNG so it works on
    // WASI). Advances across wall-tile builds so each cubicle gets its own grain.
    private static var noiseState: UInt64 = 0x9E3779B97F4A7C15
    private static func nextNoise() -> CGFloat {
        noiseState = noiseState &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((noiseState >> 40) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }

    // MARK: - Maze tiles
    // Live-node maze pieces. The wasm port builds the maze from these; apple
    // bakes the same shapes into one texture in MazeBuilder, so on apple these
    // helpers are available but unused (the color constants above are shared).

    // A tiny yellow field-dot square — the pellets Pete sweeps up.
    static func dotVisual(size: CGFloat = 6) -> SKShapeNode {
        let n = SKShapeNode(rectOf: CGSize(width: size, height: size))
        n.fillColor = .systemYellow
        n.strokeColor = .clear
        n.isAntialiased = false
        return n
    }

    // A solid box in head-on 1-point perspective for the 3D bonus pellets: the
    // front is a true square (yellow) and the only other visible face is the top,
    // a symmetric trapezoid (gold) whose side edges converge straight up to a single
    // vanishing point centered above the box. No side faces, no open interior.
    static func pelletCube(size: CGFloat) -> SKNode {
        let n = SKNode()
        let h = size / 2
        let topH = size * 0.24       // height of the visible top face (shortened)
        let backHalf = h * 0.5       // back-top edge half-width — converges to the VP above center
        let fbl = CGPoint(x: -h, y: -h), fbr = CGPoint(x: h, y: -h)
        let ftl = CGPoint(x: -h, y: h),  ftr = CGPoint(x: h, y: h)
        let btl = CGPoint(x: -backHalf, y: h + topH), btr = CGPoint(x: backHalf, y: h + topH)
        func face(_ pts: [CGPoint], _ color: SKColor, _ z: CGFloat) {
            let p = CGMutablePath()
            p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }; p.closeSubpath()
            let sh = SKShapeNode(path: p)
            sh.fillColor = color; sh.strokeColor = .clear; sh.isAntialiased = false; sh.zPosition = z
            n.addChild(sh)
        }
        face([ftl, ftr, btr, btl], SKColor(calibratedRed: 0.82, green: 0.62, blue: 0.08, alpha: 1), 0)
        face([fbl, fbr, ftr, ftl], .systemYellow, 1)
        return n
    }

    // A near-black floor tile with a one-pixel darker edge; the two shades
    // alternate by (col+row) parity for the checker pattern.
    static func floorTile(size: CGFloat, alternate: Bool) -> SKShapeNode {
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let n = SKShapeNode(rect: rect)
        n.fillColor = alternate ? floorTileA : floorTileB
        n.strokeColor = floorTileStroke
        n.lineWidth = 1
        n.lineJoin = .miter
        n.lineCap = .square
        n.miterLimit = 1
        n.isAntialiased = false
        return n
    }

    // A cubicle wall tile: inset translucent fill, inset solid panel stroke, and
    // a horizontal gray trim band high on the tile. Caller passes the per-level
    // cubicle color.
    static func wallTile(size: CGFloat, color: SKColor = cubicleColors[0], textured: Bool = true) -> SKNode {
        let n = SKNode()

        let fillRect = CGRect(x: -(size - 2) / 2, y: -(size - 2) / 2,
                              width: size - 2, height: size - 2)
        let fill = SKShapeNode(rect: fillRect)
        fill.fillColor = color.withAlphaComponent(0.55)
        fill.strokeColor = .clear
        fill.isAntialiased = false
        n.addChild(fill)

        // The grain is 11 extra nodes per tile; skip it where the tiles are tiny
        // (the minimap) so we keep the cubicle look without the draw-call blow-up.
        if textured {
            let grain = size - 5
            for _ in 0..<11 {
                let gx = (nextNoise() - 0.5) * grain
                let gy = (nextNoise() - 0.5) * grain
                let gs = 1 + nextNoise() * 1.5
                let speck = SKShapeNode(rect: CGRect(x: gx, y: gy, width: gs, height: gs))
                speck.fillColor = nextNoise() < 0.5
                    ? SKColor(calibratedWhite: 0, alpha: 0.16)
                    : SKColor(calibratedWhite: 1, alpha: 0.09)
                speck.strokeColor = .clear
                speck.isAntialiased = false
                n.addChild(speck)
            }
        }

        let strokeRect = CGRect(x: -(size - 4) / 2, y: -(size - 4) / 2,
                                width: size - 4, height: size - 4)
        let stroke = SKShapeNode(rect: strokeRect)
        stroke.fillColor = .clear
        stroke.strokeColor = color
        stroke.lineWidth = 2
        stroke.lineJoin = .miter
        stroke.lineCap = .square
        stroke.miterLimit = 1
        stroke.isAntialiased = false
        n.addChild(stroke)

        let trimWidth = size - 10
        let trimRect = CGRect(x: -trimWidth / 2, y: 6, width: trimWidth, height: 4)
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
