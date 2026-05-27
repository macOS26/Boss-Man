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
    public func closeSubpath() { flush() }
    func flush() { if !current.isEmpty { subpaths.append(current); current = [] } }
    var resolved: [[CGPoint]] { var s = subpaths; if !current.isEmpty { s.append(current) }; return s }
}
public typealias CGPath = CGMutablePath
