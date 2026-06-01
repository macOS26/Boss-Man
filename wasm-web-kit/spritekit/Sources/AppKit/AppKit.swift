import SpriteKit

// Tiny AppKit shim so SpriteKit games written for macOS can drop in on wasm.
// We re-export just enough of the API surface that asset loaders, fonts and
// color types compile. Anything visual collapses to a no-op or an SKColor.

public typealias NSColor = SKColor

// NSCoder drives NSCoding archiving on Apple; the web port never archives, so
// this name-only stub lets shared `required init?(coder: NSCoder)` signatures
// compile. Those inits all trap with fatalError and are never reached.
public final class NSCoder {
    public init() {}
}

// NSColorSpace + NSColor.usingColorSpace: SKColor is already device-RGB, so the
// conversion is the identity. Sendable enum avoids any actor-isolation friction.
public enum NSColorSpace: Sendable { case deviceRGB, genericRGB, sRGB, displayP3, genericGray }
public extension SKColor {
    func usingColorSpace(_ space: NSColorSpace) -> SKColor? { self }
}

// NSImage: an opaque handle to a pre-loaded asset (looked up by name via the kit's
// asset table). The image is never decoded in Swift — it lives in the runtime as a
// managed texture. init?(named:) mirrors NSImage(named:) and fails when the asset
// is absent (so `NSImage(named:) ?? fallback` works as on Apple); size reads the
// real pixel dimensions back through the texture so aspect math is correct.
public final class NSImage {
    public let name: String
    public init?(named name: String) {
        guard textureNamed(name) != nil else { return nil }
        self.name = name
    }
    public init?(contentsOfFile path: String) {
        guard textureNamed(path) != nil else { return nil }
        self.name = path
    }
    public convenience init?(contentsOf url: URL) { self.init(named: url.resource) }
    public var size: CGSize { textureNamed(name)?.size ?? .zero }
}

// NSFont: name + size only; SKLabelNode resolves the font through the kit's
// txt_ API by name and ignores everything else.
public final class NSFont {
    public let fontName: String
    public let pointSize: CGFloat
    public init(name: String, size: CGFloat) { self.fontName = name; self.pointSize = size }
    public static func systemFont(ofSize size: CGFloat) -> NSFont { NSFont(name: "system", size: size) }
    public static func boldSystemFont(ofSize size: CGFloat) -> NSFont { NSFont(name: "system-bold", size: size) }
}

// NSBezierPath shim that funnels into CGMutablePath, so games can construct
// shape paths with the AppKit API and hand them to SKShapeNode(path:).
public final class NSBezierPath {
    public let cgPath = CGMutablePath()
    public init() {}
    public init(rect r: CGRect) { cgPath.addRect(r) }
    public init(ovalIn r: CGRect) { cgPath.addEllipse(in: r) }
    public func move(to p: CGPoint) { cgPath.move(to: p) }
    public func line(to p: CGPoint) { cgPath.addLine(to: p) }
    public func close() { cgPath.closeSubpath() }
}

// NSEvent: only the bits SpriteKit games typically read. Modifier flags + key
// codes are routed through SKScene.keyDown/keyUp already; this type exists so
// `NSEvent.ModifierFlags` references compile.
public struct NSEvent {
    public struct ModifierFlags: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let shift   = ModifierFlags(rawValue: 1 << 0)
        public static let control = ModifierFlags(rawValue: 1 << 1)
        public static let option  = ModifierFlags(rawValue: 1 << 2)
        public static let command = ModifierFlags(rawValue: 1 << 3)
        public static let function = ModifierFlags(rawValue: 1 << 4)
    }
}

// NSScreen / NSWindow stubs so module-level references compile. Games that
// query window size should read SKScene.size instead.
public final class NSScreen {
    public static let main: NSScreen? = NSScreen()
    public var frame: CGRect = .zero
    public var backingScaleFactor: CGFloat = 1
}

public final class NSWindow {
    public var title: String = ""
    public init() {}
}

// SKTexture(image:) bridge — registers the asset by name with the kit and
// returns a texture that resolves the same way SKTexture(imageNamed:) does.
public extension SKTexture {
    convenience init(image: NSImage) { self.init(imageNamed: image.name) }
}
