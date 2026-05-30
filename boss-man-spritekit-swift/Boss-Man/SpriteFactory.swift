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

    // MARK: - Pickups
    // Returns an SKNode containing halo + core + specular. Caller sets position,
    // zPosition, physicsBody, name, and animations.
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
}
