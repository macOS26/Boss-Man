import AppKit
import SpriteKit

// MARK: - Single source of truth for all repeated sprite appearances.
// MazeBuilder, LevelEditorScene, BossController, WorkerController, and HUD
// all call these. Never duplicate sprite construction — add it here instead.
enum SpriteFactory {

    static let bossShoeGoldColor = NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.0, alpha: 1)

    // Returns an SKNode containing halo + core + specular.
    // Caller sets position, zPosition, physicsBody, name, and animations.
    static func goldDiscVisual(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let halo = SKShapeNode(circleOfRadius: radius * 1.35)
        halo.fillColor = NSColor.systemYellow.withAlphaComponent(0.30)
        halo.strokeColor = .clear
        node.addChild(halo)
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = NSColor.systemYellow.withAlphaComponent(0.85)
        core.strokeColor = bossShoeGoldColor
        core.lineWidth = 1
        node.addChild(core)
        let specular = SKShapeNode(circleOfRadius: radius * 0.3)
        specular.fillColor = NSColor(calibratedWhite: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.28, y: radius * 0.28)
        node.addChild(specular)
        return node
    }

    static func waterPelletVisual(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let halo = SKShapeNode(circleOfRadius: radius * 1.35)
        halo.fillColor = NSColor.systemCyan.withAlphaComponent(0.25)
        halo.strokeColor = .clear
        node.addChild(halo)
        let core = SKShapeNode(circleOfRadius: radius)
        core.fillColor = NSColor.systemCyan.withAlphaComponent(0.85)
        core.strokeColor = .systemBlue
        core.lineWidth = 1.5
        node.addChild(core)
        let specular = SKShapeNode(circleOfRadius: radius * 0.3)
        specular.fillColor = NSColor(calibratedWhite: 1, alpha: 0.75)
        specular.strokeColor = .clear
        specular.position = CGPoint(x: -radius * 0.28, y: radius * 0.28)
        node.addChild(specular)
        return node
    }

    static func bossPerson(bodyColor: NSColor, tieColor: NSColor, wearsSunglasses: Bool = false) -> PixelPerson {
        PixelPerson(
            bodyColor: bodyColor,
            tieColor: tieColor,
            hairColor: NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.35, alpha: 1),
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
            hairColor: NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.08, alpha: 1),
            shoeOutlineColor: .white,
            pantsColor: NSColor(calibratedRed: 0.70, green: 0.45, blue: 0.18, alpha: 1),
            walkExaggeration: walkExaggeration
        )
    }
}
