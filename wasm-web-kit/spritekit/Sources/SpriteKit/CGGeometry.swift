// CoreGraphics geometry types (CoreGraphics is Apple-only; we provide the subset
// SpriteKit games use). CGFloat is Double to match 64-bit Apple behavior.

public typealias CGFloat = Double

public struct CGPoint: Equatable, Hashable, Sendable {
    public var x: CGFloat, y: CGFloat
    public init() { x = 0; y = 0 }
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public init(x: Int, y: Int) { self.x = CGFloat(x); self.y = CGFloat(y) }
    public static let zero = CGPoint()
}

public struct CGSize: Equatable, Hashable, Sendable {
    public var width: CGFloat, height: CGFloat
    public init() { width = 0; height = 0 }
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
    public init(width: Int, height: Int) { self.width = CGFloat(width); self.height = CGFloat(height) }
    public static let zero = CGSize()
}

public struct CGVector: Equatable, Hashable, Sendable {
    public var dx: CGFloat, dy: CGFloat
    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public static let zero = CGVector()
}

public struct CGRect: Equatable, Sendable {
    public var origin: CGPoint, size: CGSize
    public init() { origin = .zero; size = .zero }
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        origin = CGPoint(x: x, y: y); size = CGSize(width: width, height: height)
    }
    public var minX: CGFloat { origin.x }
    public var minY: CGFloat { origin.y }
    public var maxX: CGFloat { origin.x + size.width }
    public var maxY: CGFloat { origin.y + size.height }
    public var midX: CGFloat { origin.x + size.width / 2 }
    public var midY: CGFloat { origin.y + size.height / 2 }
    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public func contains(_ p: CGPoint) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }
    public func contains(_ r: CGRect) -> Bool {
        r.minX >= minX && r.maxX <= maxX && r.minY >= minY && r.maxY <= maxY
    }
    public func intersects(_ r: CGRect) -> Bool {
        !(maxX <= r.minX || minX >= r.maxX || maxY <= r.minY || minY >= r.maxY)
    }
    public func intersection(_ r: CGRect) -> CGRect {
        let x = max(minX, r.minX), y = max(minY, r.minY)
        let xx = min(maxX, r.maxX), yy = min(maxY, r.maxY)
        if xx <= x || yy <= y { return .zero }
        return CGRect(x: x, y: y, width: xx - x, height: yy - y)
    }
    public func union(_ r: CGRect) -> CGRect {
        let x = min(minX, r.minX), y = min(minY, r.minY)
        return CGRect(x: x, y: y, width: max(maxX, r.maxX) - x, height: max(maxY, r.maxY) - y)
    }
    public func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: minX + dx, y: minY + dy, width: width - dx * 2, height: height - dy * 2)
    }
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRect(x: minX + dx, y: minY + dy, width: width, height: height)
    }
    public static let zero = CGRect()
}

public func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
public func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
public func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
