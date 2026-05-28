import KitABI

// SKKeyframeSequence: keyframe interpolation table for SKEmitterNode's
// per-particle color/alpha/scale sequences. SpriteKit games typically
// reference these through the Particle Editor (.sks files), then read
// them back via the SKEmitterNode property setters. We expose the API
// so emitter code compiles; sampling returns the linear-interpolated
// value across keyframes for the obvious numeric types (CGFloat, SKColor,
// CGVector).
public enum SKKeyframeInterpolationMode { case linear, spline, step }
public enum SKRepeatMode { case clamp, loop }

public final class SKKeyframeSequence {
    public var interpolationMode: SKKeyframeInterpolationMode = .linear
    public var repeatMode: SKRepeatMode = .clamp

    var values: [Any] = []
    var times: [Double] = []

    public init() {}
    public init(capacity: Int) { values.reserveCapacity(capacity); times.reserveCapacity(capacity) }
    public init(keyframeValues vs: [Any], times ts: [NSNumberLike]) {
        self.values = vs
        self.times = ts.map { $0.doubleValue }
    }
    public var count: Int { values.count }

    public func addKeyframeValue(_ value: Any, time: Double) {
        values.append(value); times.append(time)
    }
    public func removeKeyframe(at index: Int) {
        guard index >= 0, index < values.count else { return }
        values.remove(at: index); times.remove(at: index)
    }
    public func removeLastKeyframe() { _ = values.popLast(); _ = times.popLast() }
    public func getKeyframeValue(at index: Int) -> Any? {
        (index >= 0 && index < values.count) ? values[index] : nil
    }
    public func setKeyframeValue(_ value: Any, for index: Int) {
        if index >= 0, index < values.count { values[index] = value }
    }
    public func getKeyframeTime(at index: Int) -> Double {
        (index >= 0 && index < times.count) ? times[index] : 0
    }
    public func setKeyframeTime(_ time: Double, for index: Int) {
        if index >= 0, index < times.count { times[index] = time }
    }

    // Sample at arbitrary time. Numeric types are lerped; non-numeric types
    // return the nearest keyframe. Use the typed extensions below for
    // CGFloat / SKColor / CGVector sampling.
    public func sample(atTime t: Double) -> Any? {
        guard !values.isEmpty else { return nil }
        if t <= times[0] { return values[0] }
        if t >= times.last! { return values.last }
        for i in 1..<times.count {
            if t < times[i] {
                let span = times[i] - times[i-1]
                let p = span == 0 ? 0 : (t - times[i-1]) / span
                return lerp(values[i-1], values[i], CGFloat(p))
            }
        }
        return values.last
    }

    private func lerp(_ a: Any, _ b: Any, _ p: CGFloat) -> Any {
        if let af = a as? CGFloat, let bf = b as? CGFloat { return af + (bf - af) * p }
        if let af = a as? Double,  let bf = b as? Double  { return af + (bf - af) * Double(p) }
        if let av = a as? CGVector, let bv = b as? CGVector {
            return CGVector(dx: av.dx + (bv.dx - av.dx) * p, dy: av.dy + (bv.dy - av.dy) * p)
        }
        if let ac = a as? SKColor, let bc = b as? SKColor {
            return SKColor(red:   ac.r + (bc.r - ac.r) * p,
                           green: ac.g + (bc.g - ac.g) * p,
                           blue:  ac.b + (bc.b - ac.b) * p,
                           alpha: ac.a + (bc.a - ac.a) * p)
        }
        return p < 0.5 ? a : b
    }
}

// Apple uses [NSNumber] for the times array. Without Foundation, accept
// anything that exposes a double value.
public protocol NSNumberLike { var doubleValue: Double { get } }
extension Double: NSNumberLike { public var doubleValue: Double { self } }
extension Float:  NSNumberLike { public var doubleValue: Double { Double(self) } }
extension Int:    NSNumberLike { public var doubleValue: Double { Double(self) } }
