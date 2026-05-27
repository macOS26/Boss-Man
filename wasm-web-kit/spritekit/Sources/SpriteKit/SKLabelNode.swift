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
