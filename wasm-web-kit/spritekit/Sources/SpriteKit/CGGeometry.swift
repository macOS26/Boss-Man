// Re-base the framework's geometry on the real (WASI) Foundation so ONE set of CG
// types exists framework-wide, and any game file can use Foundation APIs
// (NotificationCenter, DispatchQueue, …) with no CGSize/CGFloat ambiguity.
// @_exported so `import SpriteKit` transparently brings Foundation along — game
// code that never imported Foundation still compiles, and code that does no longer
// double-declares CGSize. Foundation supplies CGPoint/CGSize/CGRect/CGFloat; only
// CGVector is missing there, so it stays here.
@_exported import Foundation

public struct CGVector: Equatable, Hashable, Sendable {
    public var dx: CGFloat, dy: CGFloat
    public init() { dx = 0; dy = 0 }
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public static let zero = CGVector()
}

// Conveniences Foundation's CGPoint doesn't ship.
public func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
public func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
public func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
