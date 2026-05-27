import KitABI

public final class SKSpriteNode: SKNode {
    public var texture: SKTexture?
    public var color: SKColor = .white
    public var colorBlendFactor: CGFloat = 0
    public var size: CGSize
    public var anchorPoint = CGPoint(x: 0.5, y: 0.5)

    public init(color: SKColor, size: CGSize) { self.color = color; self.size = size; super.init() }
    public init(texture: SKTexture?, size: CGSize) { self.texture = texture; self.size = size; super.init() }
    public init(imageNamed name: String) {
        let t = SKTexture(imageNamed: name); self.texture = t; self.size = CGSize(width: 32, height: 32); super.init()
    }

    override func draw(alpha: CGFloat) {
        let w = Float(size.width), h = Float(size.height)
        let ax = Float(anchorPoint.x), ay = Float(anchorPoint.y)
        gfx_set_alpha(Float(alpha))
        if let t = texture, t.handle != 0 {
            // re-flip locally so the bitmap isn't drawn upside down
            gfx_save(); gfx_scale(1, -1)
            gfx_draw_image(t.handle, 0, 0, -1, -1, -w * ax, -h * (1 - ay), w, h, color.rgba)
            gfx_restore()
        } else {
            gfx_fill_rect(-w * ax, -h * ay, w, h, color.rgba)
        }
    }
}
