import KitABI

public enum SKSceneScaleMode { case fill, aspectFill, aspectFit, resizeFill }

open class SKScene: SKNode {
    public var size: CGSize
    public var backgroundColor: SKColor = SKColor(white: 0.06, alpha: 1)
    public var anchorPoint = CGPoint.zero
    public var scaleMode: SKSceneScaleMode = .aspectFit
    public let physicsWorld = SKPhysicsWorld()
    public weak var view: SKView?
    public weak var camera: SKCameraNode?      // active camera; nil = default top-down

    public init(size: CGSize) { self.size = size; super.init() }
    public convenience override init() { self.init(size: CGSize(width: 1184, height: 666)) }

    open func didMove(to view: SKView) {}
    open func willMove(from view: SKView) {}
    open func didChangeSize(_ oldSize: CGSize) {}
    open func sceneDidLoad() {}                // called once before didMove
    open func update(_ currentTime: TimeInterval) {}
    open func didEvaluateActions() {}          // after actions, before physics
    open func didSimulatePhysics() {}
    open func didApplyConstraints() {}         // before didFinishUpdate
    open func didFinishUpdate() {}

    // SKView's debug render path looks for `convertPoint(fromView:)` and the
    // inverse so games can map mouse coordinates from view space.
    open func convertPoint(fromView p: CGPoint) -> CGPoint { p }
    open func convertPoint(toView p: CGPoint) -> CGPoint { p }

    // input hooks the demo/game can override
    open func keyDown(_ key: Int) { keyDown(with: NSEvent(keyCode: UInt16(truncatingIfNeeded: key))) }
    open func keyUp(_ key: Int) {}
    open func mouseDown(at p: CGPoint) { mouseDown(with: NSEvent(location: p)) }
    open func mouseUp(at p: CGPoint) { mouseUp(with: NSEvent(location: p)) }
    open func mouseMoved(to p: CGPoint) { mouseDragged(with: NSEvent(location: p)) }
    open func rightMouseDown(at p: CGPoint) { rightMouseDown(with: NSEvent(location: p)) }
    open func rightMouseUp(at p: CGPoint) {}

    // AppKit-shaped input entry points so a game's input overrides can be common
    // with the macOS build (NSResponder uses these signatures). The Int/CGPoint
    // dispatch above forwards into them; a pointer-move maps to mouseDragged (the
    // host only reports moves while a button is held, matching AppKit's drag).
    open func keyDown(with event: NSEvent) {}
    open func mouseDown(with event: NSEvent) {}
    open func mouseDragged(with event: NSEvent) {}
    open func mouseUp(with event: NSEvent) {}
    open func rightMouseDown(with event: NSEvent) {}
}

public typealias TimeInterval = Double

// Mimics the slice of AppKit's NSEvent that SpriteKit input handlers read, so a
// game's keyDown(with:)/mouseDown(with:) overrides can be common across macOS
// and wasm. Backed by a key code plus a scene-space point.
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
    public var keyCode: UInt16
    public var modifierFlags: ModifierFlags
    private let point: CGPoint
    public init(keyCode: UInt16 = 0, location: CGPoint = .zero, modifierFlags: ModifierFlags = []) {
        self.keyCode = keyCode
        self.point = location
        self.modifierFlags = modifierFlags
    }
    public func location(in node: SKNode) -> CGPoint { point }
}
