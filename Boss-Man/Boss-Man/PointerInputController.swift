import AppKit
import GameController

/// Receives directional intents from the input controller and tells it
/// when the game is over (so input is silently dropped on the game-over
/// screen). Implemented by GameScene.
@MainActor
protocol PointerInputControllerDelegate: AnyObject {
    var isGameOverForInput: Bool { get }
    func inputControllerDidRequest(_ direction: MoveDirection)
}

/// Aggregates the three non-keyboard input paths Boss-Man supports —
/// MFi gamepad (D-pad and left thumbstick), mouse/trackpad pointer
/// motion, and the AppKit cursor visibility — behind a single delegate
/// surface. GameScene forwards its NSResponder mouse-moved /
/// mouse-dragged events into handleMouseDelta(dx:dy:); the controller
/// thresholds and edge-detects, then calls back into the delegate with
/// a discrete MoveDirection.
@MainActor
final class PointerInputController: NSObject {
    weak var delegate: PointerInputControllerDelegate?

    // Gamepad: track the last dominant stick direction so we only
    // emit on edge transitions, not every analog-value update.
    private var lastPadDirection: MoveDirection?
    private let padDeadzone: Float = 0.35

    // Mouse / trackpad pointer: accumulate per-event deltas until the
    // dominant axis crosses a threshold, then emit and reset. A short
    // idle gap also resets so successive flicks read cleanly.
    private var mouseAccumX: CGFloat = 0
    private var mouseAccumY: CGFloat = 0
    private var lastMouseTime: TimeInterval = 0
    private let mouseThreshold: CGFloat = 18
    private let mouseRestartGap: TimeInterval = 0.25

    private var cursorIsHidden = false

    // MARK: - Lifecycle

    func start() {
        GCController.startWirelessControllerDiscovery()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleControllerDidConnect(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        GCController.controllers().forEach(configure(_:))
    }

    // MARK: - Cursor

    func hideCursor() {
        guard !cursorIsHidden else { return }
        NSCursor.hide()
        cursorIsHidden = true
    }

    func unhideCursor() {
        guard cursorIsHidden else { return }
        NSCursor.unhide()
        cursorIsHidden = false
    }

    // MARK: - Pointer

    func handleMouseDelta(dx: CGFloat, dy: CGFloat) {
        guard delegate?.isGameOverForInput == false else { return }
        let now = CACurrentMediaTime()
        if now - lastMouseTime > mouseRestartGap {
            mouseAccumX = 0
            mouseAccumY = 0
        }
        lastMouseTime = now
        mouseAccumX += dx
        mouseAccumY += dy
        let absX = abs(mouseAccumX), absY = abs(mouseAccumY)
        guard max(absX, absY) >= mouseThreshold else { return }
        let direction: MoveDirection
        if absX > absY {
            direction = mouseAccumX > 0 ? .right : .left
        } else {
            // AppKit's deltaY is positive when the cursor moves DOWN.
            direction = mouseAccumY < 0 ? .up : .down
        }
        delegate?.inputControllerDidRequest(direction)
        mouseAccumX = 0
        mouseAccumY = 0
    }

    // MARK: - Gamepad

    @objc private func handleControllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        configure(controller)
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.handlePadAxis(x: x, y: y)
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.handlePadAxis(x: x, y: y)
        }
    }

    private func handlePadAxis(x: Float, y: Float) {
        let absX = abs(x), absY = abs(y)
        let direction: MoveDirection?
        if max(absX, absY) < padDeadzone {
            direction = nil
        } else if absX > absY {
            direction = x < 0 ? .left : .right
        } else {
            // GCController y axis: up is positive.
            direction = y > 0 ? .up : .down
        }
        guard direction != lastPadDirection else { return }
        lastPadDirection = direction
        guard let direction, delegate?.isGameOverForInput == false else { return }
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.inputControllerDidRequest(direction)
        }
    }
}
