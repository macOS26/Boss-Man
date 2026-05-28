import KitABI

public enum SKLabelHorizontalAlignmentMode { case center, left, right }
public enum SKLabelVerticalAlignmentMode { case baseline, center, top, bottom }

public final class SKLabelNode: SKNode {
    public var text: String = ""
    public var fontSize: CGFloat = 32
    public var fontColor: SKColor? = .white
    public var fontName: String = "JetBrainsMono-Bold"
    public var horizontalAlignmentMode: SKLabelHorizontalAlignmentMode = .center
    public var verticalAlignmentMode: SKLabelVerticalAlignmentMode = .baseline
    public var numberOfLines: Int = 1                  // no-op: single-line render only
    public var preferredMaxLayoutWidth: CGFloat = 0    // no-op: hint for wrapping (unused)
    public var lineBreakMode: Int = 0                  // no-op (NSLineBreakMode enum stand-in)
    public var attributedText: String? = nil           // stored as plain text on wasm
    public var color: SKColor = .white                 // mirrors SKSpriteNode.color (tint)
    public var colorBlendFactor: CGFloat = 0           // no-op on text rendering
    public var blendMode: SKBlendMode = .alpha

    // SpriteKit also accepts: init(attributedText: NSAttributedString). We
    // accept a plain String form so games using attributed strings compile;
    // formatting attributes drop on the floor (text content survives).
    public init(attributedText: String) { self.text = attributedText; super.init() }

    public override init() { super.init() }
    public init(text: String) { self.text = text; super.init() }
    public init(fontNamed name: String) { self.fontName = name; super.init() }

    override func draw(alpha: CGFloat) {
        guard !text.isEmpty, let c = fontColor else { return }
        let px = Int32(fontSize)
        gfx_set_alpha(Float(alpha))
        gfx_save(); gfx_scale(1, -1)   // un-flip: text must not be mirrored
        withUTF8Ptr(text) { p, n in
            let w = Float(txt_width(0, p, n, px, 0))
            let x: Float
            switch horizontalAlignmentMode {
            case .center: x = -w / 2
            case .left:   x = 0
            case .right:  x = -w
            }
            // gfx_draw_text draws downward from y (textBaseline top) in this local y-down space
            let s = Float(fontSize)
            let y: Float
            switch verticalAlignmentMode {
            case .center:   y = -s * 0.5
            case .top:      y = 0
            case .bottom:   y = -s
            case .baseline: y = -s * 0.8
            }
            gfx_draw_text(0, p, n, x, y, px, c.rgba, 0)
        }
        gfx_restore()
    }
}
