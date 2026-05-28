import KitABI

public enum SKLabelHorizontalAlignmentMode { case center, left, right }
public enum SKLabelVerticalAlignmentMode { case baseline, center, top, bottom }

public final class SKLabelNode: SKNode {
    public var text: String = "" { didSet { fontHandleNeedsRebind = true } }
    public var fontSize: CGFloat = 32
    public var fontColor: SKColor? = .white
    public var fontName: String = "JetBrainsMono-Bold" { didSet { fontHandleNeedsRebind = true } }
    public var horizontalAlignmentMode: SKLabelHorizontalAlignmentMode = .center
    public var verticalAlignmentMode: SKLabelVerticalAlignmentMode = .baseline
    public var numberOfLines: Int = 1
    public var preferredMaxLayoutWidth: CGFloat = 0
    public var lineBreakMode: Int = 0
    public var attributedText: String? = nil
    public var color: SKColor = .white
    public var colorBlendFactor: CGFloat = 0
    public var blendMode: SKBlendMode = .alpha

    // Cached font handle (looked up once from fontName via font_by_name, then
    // reused across frames). Reset when fontName changes; recomputed lazily
    // because asset preloading is asynchronous and an early init() may run
    // before the font face has registered.
    private var cachedFontHandle: Int32 = 0
    private var fontHandleNeedsRebind: Bool = true

    public init(attributedText: String) { self.text = attributedText; super.init() }
    public override init() { super.init() }
    public init(text: String) { self.text = text; super.init() }
    public init(fontNamed name: String) { self.fontName = name; super.init() }

    // Resolve the font handle through font_by_name, retrying until the asset
    // loader has registered it (preload races scene init; first frame may see
    // handle 0, second frame the real one).
    private func resolvedFontHandle() -> Int32 {
        if !fontHandleNeedsRebind && cachedFontHandle != 0 { return cachedFontHandle }
        let h = withUTF8Ptr(fontName) { font_by_name($0, $1) }
        if h > 0 { cachedFontHandle = h; fontHandleNeedsRebind = false }
        return h
    }

    override func draw(alpha: CGFloat) {
        guard !text.isEmpty, let c = fontColor else { return }
        let px = Int32(fontSize)
        let font = resolvedFontHandle()
        gfx_set_alpha(Float(alpha))
        gfx_save(); gfx_scale(1, -1)   // un-flip: text must not be mirrored
        withUTF8Ptr(text) { p, n in
            let w = Float(txt_width(font, p, n, px, 0))
            let x: Float
            switch horizontalAlignmentMode {
            case .center: x = -w / 2
            case .left:   x = 0
            case .right:  x = -w
            }
            let s = Float(fontSize)
            let y: Float
            switch verticalAlignmentMode {
            case .center:   y = -s * 0.5
            case .top:      y = 0
            case .bottom:   y = -s
            case .baseline: y = -s * 0.8
            }
            gfx_draw_text(font, p, n, x, y, px, c.rgba, 0)
        }
        gfx_restore()
    }
}
