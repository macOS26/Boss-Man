import SpriteKit
#if os(macOS)
import AppKit
#endif

enum TravelerGlyph {
    static func makeNode(for traveler: LevelTraveler, pointSize: CGFloat) -> SKNode {
        let container = SKNode()
        if let imageName = traveler.image, let sprite = imageSprite(named: imageName, pointSize: pointSize) {
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

    private static func imageSprite(named name: String, pointSize: CGFloat) -> SKSpriteNode? {
        #if os(macOS)
        guard let img = NSImage(named: name) ?? loadBundleImage(named: name) else { return nil }
        let sprite = SKSpriteNode(texture: SKTexture(image: img))
        let aspect = img.size.width / img.size.height
        sprite.size = CGSize(width: pointSize * aspect * 0.8, height: pointSize)
        return sprite
        #elseif os(WASI)
        guard let tex = textureNamed(name) else { return nil }
        let sprite = SKSpriteNode(texture: tex)
        let s = tex.size
        let aspect = s.height > 0 ? s.width / s.height : 1
        sprite.size = CGSize(width: pointSize * aspect * 0.8, height: pointSize)
        return sprite
        #endif
    }

    #if os(macOS)
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
    #endif
}
