import SpriteKit
import AppKit
import KitABI

// =============================================================================
// UIKit shim so SpriteKit games written for iOS drop in on wasm.
//
// FidgetX uses UIViewController/UITouch/UIGesture*; UFOEmoji likely does too.
// We map UI types to either SpriteKit equivalents (UIColor=SKColor) or to
// stub classes that compile and behave like the iOS originals at the call
// sites games actually hit (touchesBegan reports nothing, etc.).
// =============================================================================

public typealias UIColor = SKColor
public typealias UIBezierPath = NSBezierPath
public typealias UIFont = NSFont
public typealias UIImage = NSImage

// UIScreen.main.bounds backed by SKView size when available.
public final class UIScreen {
    public static let main = UIScreen()
    public var bounds: CGRect { CGRect(x: 0, y: 0, width: CGFloat(win_width()), height: CGFloat(win_height())) }
    public var nativeBounds: CGRect { bounds }
    public var scale: CGFloat = 1
    public var nativeScale: CGFloat = 1
}

// =============================================================================
// UIApplication / UIApplicationDelegate / UIResponder — protocol stubs.
// =============================================================================
public protocol UIApplicationDelegate: AnyObject {}
public protocol UISceneDelegate: AnyObject {}

public final class UIApplication {
    public static let shared = UIApplication()
    public weak var delegate: UIApplicationDelegate?
    public var isIdleTimerDisabled = false
    public func open(_ url: SKAudioURL, options: [String: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        completionHandler?(false)
    }
}

open class UIResponder {
    public init() {}
    open var next: UIResponder? { nil }
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {}
}

// =============================================================================
// UIView / UIViewController / UIWindow — visible scaffolding.
//
// On wasm we don't run UIKit; the game's SKScene is presented through SKView.
// These stubs keep init paths and lifecycle hooks compiling.
// =============================================================================
open class UIView: UIResponder {
    public var frame: CGRect = .zero
    public var bounds: CGRect = .zero
    public var center: CGPoint = .zero
    public var backgroundColor: UIColor? = nil
    public var isUserInteractionEnabled = true
    public var isHidden = false
    public var alpha: CGFloat = 1
    public var tag: Int = 0
    public var subviews: [UIView] = []
    public weak var superview: UIView?
    public var clipsToBounds = false
    public var transform: Any = ()  // CGAffineTransform stand-in

    public override init() { super.init() }
    public init(frame: CGRect) { self.frame = frame; self.bounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height); super.init() }

    public func addSubview(_ v: UIView) { v.superview = self; subviews.append(v) }
    public func removeFromSuperview() { superview?.subviews.removeAll { $0 === self }; superview = nil }
    public func bringSubviewToFront(_ v: UIView) {}
    public func sendSubviewToBack(_ v: UIView) {}
    public func addGestureRecognizer(_ g: UIGestureRecognizer) { g.view = self }
    public func removeGestureRecognizer(_ g: UIGestureRecognizer) { g.view = nil }
    public func setNeedsLayout() {}
    public func setNeedsDisplay() {}
    public func layoutIfNeeded() {}
    public func layoutSubviews() {}
}

open class UIViewController: UIResponder {
    public var view: UIView = UIView()
    public var title: String?
    public var presentingViewController: UIViewController?
    public var presentedViewController: UIViewController?
    public var children: [UIViewController] = []
    public var parent: UIViewController?

    public override init() { super.init() }
    open func loadView() {}
    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewDidDisappear(_ animated: Bool) {}
    open func viewDidLayoutSubviews() {}
    public func present(_ vc: UIViewController, animated: Bool, completion: (() -> Void)? = nil) { completion?() }
    public func dismiss(animated: Bool, completion: (() -> Void)? = nil) { completion?() }
    public func addChild(_ vc: UIViewController) { children.append(vc); vc.parent = self }
}

public final class UIWindow: UIView {
    public var rootViewController: UIViewController?
    public var windowScene: Any?
    public func makeKeyAndVisible() {}
}

// =============================================================================
// UITouch / UIEvent — runtime feeds these into SKScene.touchesBegan via the
// kit's mouse events. For now they're addressable compile stubs.
// =============================================================================
public final class UITouch: Hashable {
    public var phase: UITouchPhase = .began
    public var tapCount: Int = 1
    public var force: CGFloat = 0
    public var maximumPossibleForce: CGFloat = 1
    public var timestamp: TimeInterval = 0
    public weak var view: UIView?
    private let id = UUID()
    public init() {}
    public func location(in view: UIView?) -> CGPoint { CGPoint(x: CGFloat(mouse_x()), y: CGFloat(mouse_y())) }
    public func location(in node: SKNode) -> CGPoint {
        // Mouse coords are in y-down view space; flip to scene y-up against the active scene size.
        let h = CGFloat(node.scene?.size.height ?? CGFloat(win_height()))
        return CGPoint(x: CGFloat(mouse_x()), y: h - CGFloat(mouse_y()))
    }
    public func previousLocation(in view: UIView?) -> CGPoint { location(in: view) }
    public func hash(into h: inout Hasher) { h.combine(id) }
    public static func == (a: UITouch, b: UITouch) -> Bool { a.id == b.id }
}

public enum UITouchPhase { case began, moved, stationary, ended, cancelled, regionEntered, regionMoved, regionExited }

public final class UIEvent {
    public init() {}
    public func allTouches() -> Set<UITouch>? { nil }
    public func touches(for view: UIView?) -> Set<UITouch>? { nil }
}

// Minimal UUID without Foundation.
public struct UUID: Hashable {
    private let a: UInt64, b: UInt64
    public init() {
        // Pull two 64-bit words from the wasm runtime's random_get via libc rand.
        a = (UInt64(__rand32()) << 32) | UInt64(__rand32())
        b = (UInt64(__rand32()) << 32) | UInt64(__rand32())
    }
}
@_silgen_name("rand") func __rand32() -> Int32

// =============================================================================
// UIGestureRecognizer family — compile-only.
//
// FidgetX uses UISwipe / UIRotation / UILongPress. Web has equivalent JS
// gestures we could later route through the runtime; for now these accept
// targets/actions so iOS code compiles and runs (without firing).
// =============================================================================
open class UIGestureRecognizer {
    public weak var view: UIView?
    public var state: UIGestureRecognizerState = .possible
    public var isEnabled = true
    var target: AnyObject?
    var action: Selector?
    public init(target: AnyObject? = nil, action: Selector? = nil) { self.target = target; self.action = action }
    public func addTarget(_ target: AnyObject, action: Selector) { self.target = target; self.action = action }
    public func removeTarget(_ target: AnyObject?, action: Selector?) {}
    open func location(in v: UIView?) -> CGPoint { CGPoint(x: CGFloat(mouse_x()), y: CGFloat(mouse_y())) }
    open func locationOfTouch(_ i: Int, in v: UIView?) -> CGPoint { location(in: v) }
    public var numberOfTouches: Int { 0 }
}
public enum UIGestureRecognizerState: Int { case possible, began, changed, ended, cancelled, failed; public static let recognized = ended }

public final class UISwipeGestureRecognizer: UIGestureRecognizer {
    public struct Direction: OptionSet, Sendable {
        public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let right = Direction(rawValue: 1 << 0)
        public static let left  = Direction(rawValue: 1 << 1)
        public static let up    = Direction(rawValue: 1 << 2)
        public static let down  = Direction(rawValue: 1 << 3)
    }
    public var direction: Direction = .right
    public var numberOfTouchesRequired: Int = 1
}
public final class UIRotationGestureRecognizer: UIGestureRecognizer {
    public var rotation: CGFloat = 0
    public var velocity: CGFloat = 0
}
public final class UIPinchGestureRecognizer: UIGestureRecognizer {
    public var scale: CGFloat = 1
    public var velocity: CGFloat = 0
}
public final class UILongPressGestureRecognizer: UIGestureRecognizer {
    public var minimumPressDuration: TimeInterval = 0.5
    public var allowableMovement: CGFloat = 10
    public var numberOfTapsRequired: Int = 0
    public var numberOfTouchesRequired: Int = 1
}
public final class UITapGestureRecognizer: UIGestureRecognizer {
    public var numberOfTapsRequired: Int = 1
    public var numberOfTouchesRequired: Int = 1
}
public final class UIPanGestureRecognizer: UIGestureRecognizer {
    public func translation(in v: UIView?) -> CGPoint { .zero }
    public func velocity(in v: UIView?) -> CGPoint { .zero }
    public func setTranslation(_ t: CGPoint, in v: UIView?) {}
}

// Selector stand-in — iOS games pass `#selector(handleSwipe)` to gesture inits.
// We accept the value but never invoke it.
public struct Selector { public let raw: String; public init(_ raw: String) { self.raw = raw } }

// =============================================================================
// UIDevice — basic identity surface.
// =============================================================================
public final class UIDevice {
    public static let current = UIDevice()
    public var name: String = "web"
    public var systemName: String = "Web"
    public var systemVersion: String = "1.0"
    public var model: String = "Browser"
    public var userInterfaceIdiom: UIUserInterfaceIdiom = .unspecified
    public var orientation: UIDeviceOrientation = .portrait
    public var isMultitaskingSupported = true
    public func playInputClick() {}
}
public enum UIUserInterfaceIdiom: Int { case unspecified = -1, phone, pad, tv, carPlay, mac, vision }
public enum UIDeviceOrientation: Int { case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown }
