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
    public init(calibratedWhite: CGFloat, alpha: CGFloat) {
        self.init(white: calibratedWhite, alpha: alpha)
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
    // macOS NSColor light-mode sRGB system palette (the SpriteKit master is a Mac
    // app), so game source that uses .systemRed / .systemPurple / etc. renders the
    // same color the Xcode build does — iOS values differ and looked washed out.
    public static let systemRed    = SKColor(red: 1.0,   green: 0.259, blue: 0.271, alpha: 1)
    public static let systemOrange = SKColor(red: 1.0,   green: 0.573, blue: 0.188, alpha: 1)
    public static let systemYellow = SKColor(red: 1.0,   green: 0.839, blue: 0.0,   alpha: 1)
    public static let systemGreen  = SKColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1)
    public static let systemMint   = SKColor(red: 0.0,   green: 0.855, blue: 0.765, alpha: 1)
    public static let systemTeal   = SKColor(red: 0.0,   green: 0.824, blue: 0.878, alpha: 1)
    public static let systemCyan   = SKColor(red: 0.235, green: 0.827, blue: 0.996, alpha: 1)
    public static let systemBlue   = SKColor(red: 0.0,   green: 0.569, blue: 1.0,   alpha: 1)
    public static let systemIndigo = SKColor(red: 0.427, green: 0.486, blue: 1.0,   alpha: 1)
    public static let systemPurple = SKColor(red: 0.859, green: 0.204, blue: 0.949, alpha: 1)
    public static let systemPink   = SKColor(red: 1.0,   green: 0.216, blue: 0.373, alpha: 1)
    public static let systemBrown  = SKColor(red: 0.718, green: 0.541, blue: 0.400, alpha: 1)
    public static let systemGray   = SKColor(red: 0.596, green: 0.596, blue: 0.616, alpha: 1)

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
