import KitABI

public enum SKLineCap { case butt, round, square }
public enum SKLineJoin { case miter, round, bevel }

public final class SKShapeNode: SKNode {
    enum Kind { case rect(CGFloat, CGFloat, CGFloat, CGFloat), circle(CGFloat), path }
    var kind: Kind
    public var fillColor: SKColor = .clear
    public var strokeColor: SKColor = .white
    public var lineWidth: CGFloat = 1
    public var isAntialiased = true
    public var glowWidth: CGFloat = 0
    public var path: CGPath? { didSet { kind = .path } }   // reassigning the path re-shapes the node

    // Line styling — Apple maps these to Canvas2D lineCap/lineJoin almost 1:1.
    public var lineCap: SKLineCap = .butt
    public var lineJoin: SKLineJoin = .miter
    public var miterLimit: CGFloat = 10
    public var fillTexture: SKTexture?
    public var strokeTexture: SKTexture?
    public var fillShader: SKShader?
    public var strokeShader: SKShader?
    public var blendMode: SKBlendMode = .alpha

    public override init() { kind = .rect(0, 0, 0, 0); super.init() }
    public init(rectOf size: CGSize) { kind = .rect(-size.width/2, -size.height/2, size.width, size.height); super.init() }
    public init(rectOf size: CGSize, cornerRadius: CGFloat) { kind = .rect(-size.width/2, -size.height/2, size.width, size.height); super.init() }
    public init(rect: CGRect) { kind = .rect(rect.minX, rect.minY, rect.width, rect.height); super.init() }
    public init(rect: CGRect, cornerRadius: CGFloat) { kind = .rect(rect.minX, rect.minY, rect.width, rect.height); super.init() }
    public init(circleOfRadius r: CGFloat) { kind = .circle(r); super.init() }
    public init(ellipseIn rect: CGRect) {
        let p = CGMutablePath(); p.addEllipse(in: rect)
        kind = .path; super.init(); self.path = p
    }
    public init(ellipseOf size: CGSize) {
        let r = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
        let p = CGMutablePath(); p.addEllipse(in: r)
        kind = .path; super.init(); self.path = p
    }
    public init(path p: CGPath) { kind = .path; self.path = p; super.init() }
    public init(path p: CGPath, centered: Bool) { kind = .path; self.path = p; super.init() }
    // Convenience polyline init (mirrors SKShapeNode(points:count:) on Apple).
    public init(points: UnsafeMutablePointer<CGPoint>, count: Int) {
        let p = CGMutablePath()
        if count > 0 { p.move(to: points[0]); for i in 1..<count { p.addLine(to: points[i]) } }
        kind = .path; super.init(); self.path = p
    }
    public init(splinePoints points: UnsafeMutablePointer<CGPoint>, count: Int) {
        // Spline isn't implemented — fall back to straight polyline.
        let p = CGMutablePath()
        if count > 0 { p.move(to: points[0]); for i in 1..<count { p.addLine(to: points[i]) } }
        kind = .path; super.init(); self.path = p
    }
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
