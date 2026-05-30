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

    // NSColor/UIColor-style component accessors (Apple games read these off colors).
    public var redComponent:   CGFloat { r }
    public var greenComponent: CGFloat { g }
    public var blueComponent:  CGFloat { b }
    public var alphaComponent: CGFloat { a }
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
    // Apple's iOS light-mode sRGB system palette, so game source that uses
    // .systemRed / .systemPurple / etc. renders the same color it does on Apple.
    public static let systemRed    = SKColor(red: 1.0,   green: 0.231, blue: 0.188, alpha: 1)
    public static let systemOrange = SKColor(red: 1.0,   green: 0.584, blue: 0.0,   alpha: 1)
    public static let systemYellow = SKColor(red: 1.0,   green: 0.8,   blue: 0.0,   alpha: 1)
    public static let systemGreen  = SKColor(red: 0.204, green: 0.78,  blue: 0.349, alpha: 1)
    public static let systemMint   = SKColor(red: 0.0,   green: 0.78,  blue: 0.745, alpha: 1)
    public static let systemTeal   = SKColor(red: 0.188, green: 0.69,  blue: 0.78,  alpha: 1)
    public static let systemCyan   = SKColor(red: 0.196, green: 0.678, blue: 0.902, alpha: 1)
    public static let systemBlue   = SKColor(red: 0.0,   green: 0.48,  blue: 1.0,   alpha: 1)
    public static let systemIndigo = SKColor(red: 0.345, green: 0.337, blue: 0.839, alpha: 1)
    public static let systemPurple = SKColor(red: 0.686, green: 0.322, blue: 0.871, alpha: 1)
    public static let systemPink   = SKColor(red: 1.0,   green: 0.176, blue: 0.333, alpha: 1)
    public static let systemBrown  = SKColor(red: 0.635, green: 0.518, blue: 0.369, alpha: 1)
    public static let systemGray   = SKColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)

    // NSColor.blended(withFraction:of:): weighted RGBA mix of self and `color`.
    // Returns optional to match the Apple signature (never nil here).
    public func blended(withFraction fraction: CGFloat, of color: SKColor) -> SKColor? {
        let f = max(0, min(1, fraction))
        return SKColor(red:   r + (color.r - r) * f,
                       green: g + (color.g - g) * f,
                       blue:  b + (color.b - b) * f,
                       alpha: a + (color.a - a) * f)
    }
}
