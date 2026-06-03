import KitABI

public enum SKLineCap { case butt, round, square
    var abiCode: Int32 { switch self { case .butt: return 0; case .round: return 1; case .square: return 2 } }
}
public enum SKLineJoin { case miter, round, bevel
    var abiCode: Int32 { switch self { case .miter: return 0; case .round: return 1; case .bevel: return 2 } }
}

public final class SKShapeNode: SKNode {
    enum Kind { case rect(CGFloat, CGFloat, CGFloat, CGFloat), circle(CGFloat), path }
    var kind: Kind
    public var fillColor: SKColor = .clear
    public var strokeColor: SKColor = .white
    public var lineWidth: CGFloat = 1
    public var isAntialiased = true
    public var glowWidth: CGFloat = 0
    // Drop shadow. shadowBlur > 0 activates a Canvas2D shadowBlur pass that
    // renders a real Gaussian halo behind the shape. shadowOffset is in
    // scene y-up coords (positive dy = above); the render path negates dy
    // for the underlying Canvas2D y-down shadowOffsetY.
    public var shadowBlur: CGFloat = 0
    public var shadowOffset: CGVector = .zero
    public var shadowColor: SKColor = SKColor(red: 0, green: 0, blue: 0, alpha: 0.4)
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
    public init(rectOf size: CGSize, cornerRadius: CGFloat) {
        let rect = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
        if cornerRadius > 0 {
            let p = CGMutablePath(); p.addRoundedRect(in: rect, cornerRadius: cornerRadius)
            kind = .path; super.init(); self.path = p
        } else {
            kind = .rect(rect.minX, rect.minY, rect.width, rect.height); super.init()
        }
    }
    public init(rect: CGRect) { kind = .rect(rect.minX, rect.minY, rect.width, rect.height); super.init() }
    public init(rect: CGRect, cornerRadius: CGFloat) {
        if cornerRadius > 0 {
            let p = CGMutablePath(); p.addRoundedRect(in: rect, cornerRadius: cornerRadius)
            kind = .path; super.init(); self.path = p
        } else {
            kind = .rect(rect.minX, rect.minY, rect.width, rect.height); super.init()
        }
    }
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

    public override var frame: CGRect {
        let local: CGRect
        switch kind {
        case let .rect(x, y, w, h):
            local = CGRect(x: x, y: y, width: w, height: h)
        case let .circle(r):
            local = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
        case .path:
            guard let pts = path?.flattenedPoints, !pts.isEmpty else {
                return CGRect(x: position.x, y: position.y, width: 0, height: 0)
            }
            var minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y
            for p in pts.dropFirst() {
                if p.x < minX { minX = p.x } ; if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y } ; if p.y > maxY { maxY = p.y }
            }
            local = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return CGRect(x: position.x + local.minX, y: position.y + local.minY,
                      width: local.width, height: local.height)
    }

    override func draw(alpha: CGFloat) {
        gfx_set_alpha(Float(alpha))
        let hasFill = fillColor.a > 0
        let hasStroke = strokeColor.a > 0 && lineWidth > 0
        // Honor lineJoin/lineCap so the game's stroke styling is identical to
        // Apple's (set inside the per-node gfx_save/restore, so it can't leak).
        if hasStroke { gfx_set_line_style(lineJoin.abiCode, lineCap.abiCode, Float(miterLimit)) }
        // Activate Canvas2D shadowBlur for this draw if the node opted in. dy
        // is negated because SpriteKit's y-up shadow offset (positive = above)
        // maps to Canvas2D's y-down shadowOffsetY (positive = below). Cleared
        // after the draw so siblings don't inherit it.
        let hasShadow = shadowBlur > 0 && shadowColor.a > 0
        if hasShadow {
            gfx_set_shadow(Float(shadowBlur),
                           Float(shadowOffset.dx),
                           Float(-shadowOffset.dy),
                           shadowColor.rgba)
        }
        defer { if hasShadow { gfx_clear_shadow() } }
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
