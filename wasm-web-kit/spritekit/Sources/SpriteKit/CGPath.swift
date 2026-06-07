import KitABI

// Minimal CGPath/CGMutablePath: records subpaths of points for SKShapeNode.
public final class CGMutablePath {
    var subpaths: [[CGPoint]] = []
    var current: [CGPoint] = []
    public init() {}
    public func move(to p: CGPoint) { flush()
    current = [p] }
    public func addLine(to p: CGPoint) { if current.isEmpty { current = [p] } else { current.append(p) } }
    public func addRect(_ r: CGRect) {
        flush()
        subpaths.append([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)])
    }
    // Coarse ellipse flattening (16-point polygon) so addEllipse(in:) keeps shape
    // games working without pulling in trig — uses the unit-circle table.
    public func addEllipse(in r: CGRect) {
        flush()
        let cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2
        var pts: [CGPoint] = []
        for i in 0..<32 {
            let (c, s) = unitCircle(i, of: 32)
            pts.append(CGPoint(x: cx + CGFloat(c) * rx, y: cy + CGFloat(s) * ry))
        }
        subpaths.append(pts)
    }
    public func addArc(center c: CGPoint, radius r: CGFloat, startAngle s: CGFloat,
                       endAngle e: CGFloat, clockwise cw: Bool) {
        let steps = 24
        var pts: [CGPoint] = []
        let span = (e - s) * (cw ? -1 : 1)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let a = s + span * t
            let (co, si) = sincos(Double(a))
            pts.append(CGPoint(x: c.x + CGFloat(co) * r, y: c.y + CGFloat(si) * r))
        }
        if current.isEmpty { current = pts } else { current.append(contentsOf: pts) }
    }
    // Tangent-arc corner rounding (CoreGraphics arcTo): an arc of the given radius
    // tangent to the line from the current point to tangent1End and the line from
    // tangent1End to tangent2End. Half-angle terms come from dot/cross so no acos/tan
    // helper is needed. Collinear / degenerate corners fall back to a straight line.
    public func addArc(tangent1End p1: CGPoint, tangent2End p2: CGPoint, radius r: CGFloat) {
        guard let p0 = current.last else { current = [p1]
        return }
        if r <= 0 { addLine(to: p1)
        return }
        let v1x = p0.x - p1.x, v1y = p0.y - p1.y
        let v2x = p2.x - p1.x, v2y = p2.y - p1.y
        let len1 = (v1x * v1x + v1y * v1y).squareRoot()
        let len2 = (v2x * v2x + v2y * v2y).squareRoot()
        if len1 < 1e-6 || len2 < 1e-6 { addLine(to: p1)
        return }
        let u1x = v1x / len1, u1y = v1y / len1
        let u2x = v2x / len2, u2y = v2y / len2
        let dot = u1x * u2x + u1y * u2y
        let crossAbs = abs(u1x * u2y - u1y * u2x)
        if crossAbs < 1e-6 { addLine(to: p1)
        return }
        let dist = r * (1 + dot) / crossAbs
        let t1 = CGPoint(x: p1.x + u1x * dist, y: p1.y + u1y * dist)
        let t2 = CGPoint(x: p1.x + u2x * dist, y: p1.y + u2y * dist)
        var bx = u1x + u2x, by = u1y + u2y
        let blen = (bx * bx + by * by).squareRoot()
        let sinHalf = ((1 - dot) / 2).squareRoot()
        if blen < 1e-6 || sinHalf < 1e-6 { addLine(to: p1)
        return }
        bx /= blen
        by /= blen
        let cx = p1.x + bx * (r / sinHalf), cy = p1.y + by * (r / sinHalf)
        addLine(to: t1)
        let a1 = atan2c(t1.y - cy, t1.x - cx)
        var da = atan2c(t2.y - cy, t2.x - cx) - a1
        let pi = CGFloat(3.141592653589793)
        while da > pi { da -= 2 * pi }
        while da < -pi { da += 2 * pi }
        let steps = 6
        for i in 1...steps {
            let a = a1 + da * CGFloat(i) / CGFloat(steps)
            current.append(CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r))
        }
    }
    // Rounded rectangle as a single closed polygon: four quarter-arcs whose
    // endpoints the fill/stroke poly connects with the straight edges. Coarse
    // (few segments per corner) since the radii are small; clamps the radius to
    // half the shorter side and falls back to a plain rect at radius 0.
    public func addRoundedRect(in r: CGRect, cornerRadius cr: CGFloat) {
        let rad = max(0, min(cr, min(r.width, r.height) / 2))
        if rad <= 0 { addRect(r)
        return }
        let seg = 4
        var pts: [CGPoint] = []
        func corner(_ cx: CGFloat, _ cy: CGFloat, from: Double, to: Double) {
            for i in 0...seg {
                let a = from + (to - from) * Double(i) / Double(seg)
                let (co, si) = sincos(a)
                pts.append(CGPoint(x: cx + CGFloat(co) * rad, y: cy + CGFloat(si) * rad))
            }
        }
        let q = Double.pi / 2
        corner(r.maxX - rad, r.minY + rad, from: q * 3, to: q * 4)   // bottom-right
        corner(r.maxX - rad, r.maxY - rad, from: 0,     to: q)       // top-right
        corner(r.minX + rad, r.maxY - rad, from: q,     to: q * 2)   // top-left
        corner(r.minX + rad, r.minY + rad, from: q * 2, to: q * 3)   // bottom-left
        flush()
        subpaths.append(pts)
    }
    public func closeSubpath() { flush() }
    func flush() { if !current.isEmpty { subpaths.append(current)
    current = [] } }
    var resolved: [[CGPoint]] { var s = subpaths
    if !current.isEmpty { s.append(current) }
    return s }

    // Polyline flattening across all subpaths — used by SKAction.follow to sample
    // a path by arc length. Each subpath is treated as a continuous polyline; we
    // join them tail-to-head so the action sweeps the whole path once.
    var flattenedPoints: [CGPoint] {
        var out: [CGPoint] = []
        for sub in resolved {
            if out.isEmpty { out.append(contentsOf: sub) }
            else { out.append(contentsOf: sub) }
        }
        return out
    }
    var arcLength: CGFloat {
        let pts = flattenedPoints
        var total: CGFloat = 0
        for i in 1..<pts.count { total += pts[i-1].distance(to: pts[i]) }
        return total
    }
}
public typealias CGPath = CGMutablePath

// Math helpers — C libm wrappers exposed to Swift so game code can call
// sin/cos/exp/tanh/pow without importing Foundation. Foundation drags ICU
// into the wasm binary; these free-function overloads replace it for Float
// and Double. (CGFloat == Double, so the CGFloat overloads cover Double.)
public func sincos(_ a: Double) -> (Double, Double) {
    let s = sb64_sin(a), c = sb64_cos(a)
    return (c, s)
}
public func atan2c(_ y: CGFloat, _ x: CGFloat) -> CGFloat { CGFloat(sb64_atan2(Double(y), Double(x))) }
public func cos(_ x: CGFloat) -> CGFloat { sb64_cos(x) }
public func sin(_ x: CGFloat) -> CGFloat { sb64_sin(x) }
public func sin(_ x: Float) -> Float { Float(sb64_sin(Double(x))) }
public func cos(_ x: Float) -> Float { Float(sb64_cos(Double(x))) }
public func exp(_ x: Float) -> Float { Float(sb64_exp(Double(x))) }
public func exp(_ x: Double) -> Double { sb64_exp(x) }
public func tanh(_ x: Float) -> Float { Float(sb64_tanh(Double(x))) }
public func tanh(_ x: Double) -> Double { sb64_tanh(x) }
public func pow(_ base: Float, _ exp: Float) -> Float { Float(sb64_pow(Double(base), Double(exp))) }
public func pow(_ base: Double, _ exp: Double) -> Double { sb64_pow(base, exp) }
public func floor(_ x: Float) -> Float { Float(sb64_floor(Double(x))) }
public func floor(_ x: Double) -> Double { sb64_floor(x) }

// 32-entry quarter-rotation unit circle for coarse ellipse/arc flattening.
func unitCircle(_ i: Int, of n: Int) -> (Double, Double) {
    let theta = 2 * 3.141592653589793 * Double(i) / Double(n)
    return sincos(theta)
}

public extension CGPoint {
    func distance(to o: CGPoint) -> CGFloat {
        let dx = x - o.x, dy = y - o.y
        return CGFloat((Double(dx*dx + dy*dy)).squareRoot())
    }
}


