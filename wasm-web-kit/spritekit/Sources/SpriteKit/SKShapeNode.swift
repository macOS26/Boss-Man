import KitABI

public final class SKShapeNode: SKNode {
    enum Kind { case rect(CGFloat, CGFloat, CGFloat, CGFloat), circle(CGFloat), path }
    var kind: Kind
    public var fillColor: SKColor = .clear
    public var strokeColor: SKColor = .white
    public var lineWidth: CGFloat = 1
    public var isAntialiased = true
    public var glowWidth: CGFloat = 0
    public var path: CGPath? { didSet { kind = .path } }   // reassigning the path re-shapes the node

    public override init() { kind = .rect(0, 0, 0, 0); super.init() }
    public init(rectOf size: CGSize) { kind = .rect(-size.width/2, -size.height/2, size.width, size.height); super.init() }
    public init(rectOf size: CGSize, cornerRadius: CGFloat) { kind = .rect(-size.width/2, -size.height/2, size.width, size.height); super.init() }
    public init(rect: CGRect) { kind = .rect(rect.minX, rect.minY, rect.width, rect.height); super.init() }
    public init(rect: CGRect, cornerRadius: CGFloat) { kind = .rect(rect.minX, rect.minY, rect.width, rect.height); super.init() }
    public init(circleOfRadius r: CGFloat) { kind = .circle(r); super.init() }
    public init(path p: CGPath) { kind = .path; self.path = p; super.init() }
    public static func node(withPath p: CGPath) -> SKShapeNode { SKShapeNode(path: p) }

    override func draw(alpha: CGFloat) {
        gfx_set_alpha(Float(alpha))
        let hasFill = fillColor.a > 0
        let hasStroke = strokeColor.a > 0 && lineWidth > 0
        switch kind {
        case let .rect(x, y, w, h):
            if hasFill { gfx_fill_rect(Float(x), Float(y), Float(w), Float(h), fillColor.rgba) }
            if hasStroke { gfx_stroke_rect(Float(x), Float(y), Float(w), Float(h), Float(lineWidth), strokeColor.rgba) }
        case let .circle(r):
            if hasFill { gfx_fill_circle(0, 0, Float(r), fillColor.rgba) }
            if hasStroke { gfx_stroke_circle(0, 0, Float(r), Float(lineWidth), strokeColor.rgba) }
        case .path:
            guard let p = path else { return }
            for sub in p.resolved where sub.count >= 2 {
                var xy = [Float](); xy.reserveCapacity(sub.count * 2)
                for pt in sub { xy.append(Float(pt.x)); xy.append(Float(pt.y)) }
                xy.withUnsafeBufferPointer { buf in
                    let n = Int32(sub.count)
                    if hasFill && sub.count >= 3 { gfx_fill_poly(buf.baseAddress, n, fillColor.rgba) }
                    if hasStroke { gfx_stroke_poly(buf.baseAddress, n, 1, Float(lineWidth), strokeColor.rgba) }
                }
            }
        }
    }
}
