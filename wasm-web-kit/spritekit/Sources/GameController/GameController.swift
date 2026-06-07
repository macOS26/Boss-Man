import KitABI
import SpriteKit

// =============================================================================
// GameController shim — wraps the kit's gp_* (Web Gamepad API) imports in the
// shapes iOS/macOS games already know: GCController.controllers(),
// .extendedGamepad, .leftThumbstick.valueChangedHandler, etc.
//
// AsteroidZ uses this for keyboard + controller; Space-Bar mac version too.
// USB arcade joysticks register as standard gamepads to browsers, so this
// same module covers both arcade sticks and modern Xbox/PS/Switch pads.
//
// State refresh: GameController doesn't run an own update loop, so each
// property read pulls from the kit's frame-cached gp_* snapshot. Handlers
// fire when a snapshot change is detected during snapshotAll().
// =============================================================================

public final class GCController {
    public static let extendedGamepadProfile = "ExtendedGamepad"
    public static var current: GCController? { all().first }
    public static let didConnectNotification = "GCControllerDidConnect"
    public static let didDisconnectNotification = "GCControllerDidDisconnect"

    public let playerIndex: Int
    public var vendorName: String? = "Gamepad"
    public var productCategory: String = "Standard"
    public var isAttachedToDevice = false
    public var extendedGamepad: GCExtendedGamepad?
    public var microGamepad: GCMicroGamepad? { nil }
    public var motion: Any? { nil }
    public var battery: Any? { nil }

    private init(index: Int) {
        self.playerIndex = index
        self.extendedGamepad = GCExtendedGamepad(padIndex: Int32(index))
    }

    public static func controllers() -> [GCController] { all() }
    public static func startWirelessControllerDiscovery(completionHandler h: (() -> Void)? = nil) { h?() }
    public static func stopWirelessControllerDiscovery() {}

    // Internal: enumerates pads connected this frame via gp_connected.
    nonisolated(unsafe) private static var cache: [Int: GCController] = [:]
    private static func all() -> [GCController] {
        var out: [GCController] = []
        for i in 0..<4 where gp_connected(Int32(i)) != 0 {
            let c = cache[i] ?? GCController(index: i)
            cache[i] = c
            out.append(c)
        }
        return out
    }

    // Game code calls this once per frame to fire valueChangedHandler closures.
    // Drives change detection from the kit's snapshot.
    public func refresh() { extendedGamepad?.refresh() }
}

public final class GCMicroGamepad {
    public var valueChangedHandler: ((GCMicroGamepad, GCControllerElement) -> Void)?
    public init() {}
}

// =============================================================================
// GCExtendedGamepad — standard layout (W3C / Xbox-style). All elements pull
// from the kit's gp_button/gp_axis once per refresh and fire handlers on edges.
// =============================================================================
public final class GCExtendedGamepad {
    public let padIndex: Int32
    public var valueChangedHandler: ((GCExtendedGamepad, GCControllerElement) -> Void)?

    public let leftThumbstick:  GCControllerDirectionPad
    public let rightThumbstick: GCControllerDirectionPad
    public let dpad: GCControllerDirectionPad
    public let buttonA, buttonB, buttonX, buttonY: GCControllerButtonInput
    public let leftShoulder, rightShoulder: GCControllerButtonInput
    public let leftTrigger, rightTrigger: GCControllerButtonInput
    public let leftThumbstickButton, rightThumbstickButton: GCControllerButtonInput
    public let buttonMenu, buttonOptions, buttonHome: GCControllerButtonInput

    init(padIndex i: Int32) {
        self.padIndex = i
        leftThumbstick  = GCControllerDirectionPad(pad: i, kind: .leftStick)
        rightThumbstick = GCControllerDirectionPad(pad: i, kind: .rightStick)
        dpad            = GCControllerDirectionPad(pad: i, kind: .dpad)
        buttonA = GCControllerButtonInput(pad: i, btn: 0)
        buttonB = GCControllerButtonInput(pad: i, btn: 1)
        buttonX = GCControllerButtonInput(pad: i, btn: 2)
        buttonY = GCControllerButtonInput(pad: i, btn: 3)
        leftShoulder  = GCControllerButtonInput(pad: i, btn: 4)
        rightShoulder = GCControllerButtonInput(pad: i, btn: 5)
        leftTrigger   = GCControllerButtonInput(pad: i, btn: 6)
        rightTrigger  = GCControllerButtonInput(pad: i, btn: 7)
        buttonOptions = GCControllerButtonInput(pad: i, btn: 8)
        buttonMenu    = GCControllerButtonInput(pad: i, btn: 9)
        leftThumbstickButton  = GCControllerButtonInput(pad: i, btn: 10)
        rightThumbstickButton = GCControllerButtonInput(pad: i, btn: 11)
        buttonHome    = GCControllerButtonInput(pad: i, btn: 16)
    }

    func refresh() {
        leftThumbstick.refresh(handler: { self.fire($0) })
        rightThumbstick.refresh(handler: { self.fire($0) })
        dpad.refresh(handler: { self.fire($0) })
        for b in [buttonA, buttonB, buttonX, buttonY,
                  leftShoulder, rightShoulder, leftTrigger, rightTrigger,
                  buttonOptions, buttonMenu,
                  leftThumbstickButton, rightThumbstickButton, buttonHome] {
            b.refresh(handler: { self.fire($0) })
        }
    }
    private func fire(_ el: GCControllerElement) { valueChangedHandler?(self, el) }
}

// =============================================================================
public class GCControllerElement {
    public var isAnalog: Bool = true
    public var collection: GCControllerElement?
    public var aliases: Set<String> = []
    public init() {}
}

public final class GCControllerButtonInput: GCControllerElement {
    let padIndex: Int32, btn: Int32
    public var value: Float = 0
    public var isPressed: Bool { value > 0.5 }
    public var pressedChangedHandler: ((GCControllerButtonInput, Float, Bool) -> Void)?
    public var valueChangedHandler: ((GCControllerButtonInput, Float, Bool) -> Void)?
    private var lastPressed = false
    init(pad: Int32, btn: Int32) { self.padIndex = pad
    self.btn = btn }
    func refresh(handler outer: (GCControllerElement) -> Void) {
        let v = gp_button_value(padIndex, btn)
        let pressed = v > 0.5
        let changed = pressed != lastPressed || value != v
        value = v
        if changed {
            valueChangedHandler?(self, value, pressed)
            if pressed != lastPressed { pressedChangedHandler?(self, value, pressed) }
            outer(self)
        }
        lastPressed = pressed
    }
}

public final class GCControllerAxisInput: GCControllerElement {
    let padIndex: Int32, axis: Int32
    public var value: Float = 0
    public var valueChangedHandler: ((GCControllerAxisInput, Float) -> Void)?
    init(pad: Int32, axis: Int32) { self.padIndex = pad
    self.axis = axis }
    func refresh(handler outer: (GCControllerElement) -> Void) {
        let v = gp_axis(padIndex, axis)
        if v != value {
            value = v
            valueChangedHandler?(self, v)
            outer(self)
        }
    }
}

// =============================================================================
// GCControllerDirectionPad — bundles x/y axes (or 4 dpad buttons) into one
// element, mirroring the macOS/iOS API: .xAxis, .yAxis, .up, .down, .left, .right.
// =============================================================================
public final class GCControllerDirectionPad: GCControllerElement {
    enum Kind { case leftStick, rightStick, dpad }
    let padIndex: Int32
    let kind: Kind
    public let xAxis: GCControllerAxisInput
    public let yAxis: GCControllerAxisInput
    public let up, down, left, right: GCControllerButtonInput
    public var valueChangedHandler: ((GCControllerDirectionPad, Float, Float) -> Void)?
    private var lastX: Float = 0, lastY: Float = 0

    init(pad: Int32, kind: Kind) {
        self.padIndex = pad
        self.kind = kind
        switch kind {
        case .leftStick:
            xAxis = GCControllerAxisInput(pad: pad, axis: 0)
            yAxis = GCControllerAxisInput(pad: pad, axis: 1)
        case .rightStick:
            xAxis = GCControllerAxisInput(pad: pad, axis: 2)
            yAxis = GCControllerAxisInput(pad: pad, axis: 3)
        case .dpad:
            xAxis = GCControllerAxisInput(pad: pad, axis: -1)  // synthesized from buttons
            yAxis = GCControllerAxisInput(pad: pad, axis: -1)
        }
        up    = GCControllerButtonInput(pad: pad, btn: 12)
        down  = GCControllerButtonInput(pad: pad, btn: 13)
        left  = GCControllerButtonInput(pad: pad, btn: 14)
        right = GCControllerButtonInput(pad: pad, btn: 15)
    }
    func refresh(handler outer: (GCControllerElement) -> Void) {
        let x: Float, y: Float
        switch kind {
        case .dpad:
            x = (gp_button(padIndex, 15) != 0 ? 1 : 0) - (gp_button(padIndex, 14) != 0 ? 1 : 0)
            y = (gp_button(padIndex, 12) != 0 ? 1 : 0) - (gp_button(padIndex, 13) != 0 ? 1 : 0)
            up.refresh(handler: outer)
            down.refresh(handler: outer)
            left.refresh(handler: outer)
            right.refresh(handler: outer)
        default:
            x = gp_axis(padIndex, kind == .leftStick ? 0 : 2)
            y = -gp_axis(padIndex, kind == .leftStick ? 1 : 3)  // y-up to match SpriteKit
        }
        if x != lastX || y != lastY {
            valueChangedHandler?(self, x, y)
            outer(self)
            lastX = x
            lastY = y
        }
    }
}

// Notification.Name stand-ins (no Foundation dependency).
public extension String {
    static let GCControllerDidConnect = "GCControllerDidConnect"
    static let GCControllerDidDisconnect = "GCControllerDidDisconnect"
}


