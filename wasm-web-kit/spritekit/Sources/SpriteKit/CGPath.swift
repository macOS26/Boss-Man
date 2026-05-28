import KitABI

// Minimal CGPath/CGMutablePath: records subpaths of points for SKShapeNode.
public final class CGMutablePath {
    var subpaths: [[CGPoint]] = []
    var current: [CGPoint] = []
    public init() {}
    public func move(to p: CGPoint) { flush(); current = [p] }
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
    public func closeSubpath() { flush() }
    func flush() { if !current.isEmpty { subpaths.append(current); current = [] } }
    var resolved: [[CGPoint]] { var s = subpaths; if !current.isEmpty { s.append(current) }; return s }

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

// Trig helper: per-frame action math needs sin/cos/atan2 once in a while. We
// piggyback on Foundation/libm; the 16-entry unit-circle is for tight loops.
public func sincos(_ a: Double) -> (Double, Double) {
    let s = sb64_sin(a), c = sb64_cos(a)
    return (c, s)
}
public func atan2c(_ y: CGFloat, _ x: CGFloat) -> CGFloat { CGFloat(sb64_atan2(Double(y), Double(x))) }

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
