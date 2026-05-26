import AppKit
import SpriteKit

enum TravelerGlyph {
    static func makeNode(for traveler: LevelTraveler, pointSize: CGFloat) -> SKNode {
        let container = SKNode()
        if let imageName = traveler.image,
           let img = NSImage(named: imageName) ?? loadBundleImage(named: imageName) {
            let sprite = SKSpriteNode(texture: SKTexture(image: img))
            let aspect = img.size.width / img.size.height
            sprite.size = CGSize(width: pointSize * aspect * 0.8, height: pointSize)
            container.addChild(sprite)
        } else {
            let label = SKLabelNode(text: traveler.emoji)
            label.fontSize = pointSize
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            container.addChild(label)
        }
        return container
    }

    private static func loadBundleImage(named name: String) -> NSImage? {
        for ext in [Strings.Resource.redStaplerExtension,
                    Strings.Resource.travelerStaplerExtension] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return nil
    }
}
