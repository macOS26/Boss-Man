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

    public init(attributedText: String) { self.text = attributedText
    super.init() }
    public override init() { super.init() }
    public init(text: String) { self.text = text
    super.init() }
    public init(fontNamed name: String) { self.fontName = name
    super.init() }

    // Resolve the font handle through font_by_name, retrying until the asset
    // loader has registered it (preload races scene init; first frame may see
    // handle 0, second frame the real one).
    private func resolvedFontHandle() -> Int32 {
        if !fontHandleNeedsRebind && cachedFontHandle != 0 { return cachedFontHandle }
        let h = withUTF8Ptr(fontName) { font_by_name($0, $1) }
        if h > 0 { cachedFontHandle = h
        fontHandleNeedsRebind = false }
        return h
    }

    // Measured bounding box in the PARENT's coordinate space, honoring the
    // alignment modes the way SpriteKit does (draw() uses the same -w/2 / 0 / -w
    // rule). Consumers position sibling nodes off a label's frame (the HUD's
    // water-gun ammo dots + crop overlay), so the zero-size rect SKNode returns
    // would stack them on top of the label.
    public override var frame: CGRect {
        // Frame is in the parent's coordinate space, so fold in the node's own
        // scale (Apple does this). A supersampled label (big fontSize, setScale
        // 1/N) must report its true on-screen size or frame-based hit-tests miss.
        let w = measuredWidth() * abs(xScale)
        let h = fontSize * abs(yScale)
        let minX: CGFloat
        switch horizontalAlignmentMode {
        case .center: minX = position.x - w / 2
        case .left:   minX = position.x
        case .right:  minX = position.x - w
        }
        let minY: CGFloat
        switch verticalAlignmentMode {
        case .center:            minY = position.y - h / 2
        case .top:               minY = position.y - h
        case .bottom, .baseline: minY = position.y
        }
        return CGRect(x: minX, y: minY, width: w, height: h)
    }

    // Public glyph-run width measurement so consumers can position a
    // sibling node (caret, divider, etc.) at the end of the text without
    // duplicating the txt_width call.
    public func measuredWidth() -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let px = Int32(fontSize)
        let font = resolvedFontHandle()
        var w: Int32 = 0
        withUTF8Ptr(text) { p, n in w = txt_width(font, p, n, px, 0) }
        return CGFloat(w)
    }

    override func draw(alpha: CGFloat) {
        guard !text.isEmpty, let c = fontColor else { return }
        let px = Int32(fontSize)
        let font = resolvedFontHandle()
        gfx_set_alpha(Float(alpha))
        gfx_save()
        gfx_scale(1, -1)  // un-flip: text must not be mirrored
        withUTF8Ptr(text) { p, n in
            let w = Float(txt_width(font, p, n, px, 0))
            let x: Float
            switch horizontalAlignmentMode {
            case .center: x = -w / 2
            case .left:   x = 0
            case .right:  x = -w
            }
            // Let Canvas2D pick the textBaseline directly so the y anchor
            // matches what each alignment mode means visually. The legacy
            // hand-rolled offsets (y = -s * 0.5, etc.) gave the right answer
            // for the em-box's geometric centre but emojis don't sit dead
            // centre in the em-box; setting textBaseline = 'middle' lets the
            // canvas use the actual glyph centre, which is what SpriteKit's
            // .center alignment promises.
            let baselineMode: Int32
            switch verticalAlignmentMode {
            case .baseline: baselineMode = 0       // alphabetic
            case .center:   baselineMode = 1       // middle
            case .top:      baselineMode = 2
            case .bottom:   baselineMode = 3
            }
            gfx_set_text_baseline(baselineMode)
            gfx_draw_text(font, p, n, x, 0, px, c.rgba, 0)
            gfx_set_text_baseline(2)               // restore default 'top'
        }
        gfx_restore()
    }
}


