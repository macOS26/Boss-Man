// SKColor on Apple is NSColor/UIColor. We provide an RGBA value type with the
// common constructors and palette the games use, plus packing for the kit ABI.

public struct SKColor: Equatable, Sendable {
    public var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        r = red; g = green; b = blue; a = alpha
    }
    public init(white: CGFloat, alpha: CGFloat) { r = white; g = white; b = white; a = alpha }
    public init(calibratedRed: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: calibratedRed, green: green, blue: blue, alpha: alpha)
    }

    func u8(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, Int(v * 255 + 0.5)))) }
    public var rgba: UInt32 { (u8(r) << 24) | (u8(g) << 16) | (u8(b) << 8) | u8(a) }
    public func withAlphaComponent(_ alpha: CGFloat) -> SKColor {
        SKColor(red: r, green: g, blue: b, alpha: alpha)
    }

    public static let clear   = SKColor(white: 0, alpha: 0)
    public static let black   = SKColor(white: 0, alpha: 1)
    public static let white   = SKColor(white: 1, alpha: 1)
    public static let gray    = SKColor(white: 0.5, alpha: 1)
    public static let darkGray = SKColor(white: 0.33, alpha: 1)
    public static let lightGray = SKColor(white: 0.67, alpha: 1)
    public static let red     = SKColor(red: 1, green: 0, blue: 0, alpha: 1)
    public static let green   = SKColor(red: 0, green: 1, blue: 0, alpha: 1)
    public static let blue    = SKColor(red: 0, green: 0, blue: 1, alpha: 1)
    public static let yellow  = SKColor(red: 1, green: 1, blue: 0, alpha: 1)
    public static let orange  = SKColor(red: 1, green: 0.5, blue: 0, alpha: 1)
    public static let cyan    = SKColor(red: 0, green: 1, blue: 1, alpha: 1)
    public static let magenta = SKColor(red: 1, green: 0, blue: 1, alpha: 1)
    public static let systemYellow = SKColor(red: 1, green: 0.8, blue: 0, alpha: 1)
    public static let systemBlue   = SKColor(red: 0, green: 0.48, blue: 1, alpha: 1)
    public static let systemGreen  = SKColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
}
