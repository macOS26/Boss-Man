import AppKit
import GameController

protocol PointerInputControllerDelegate: AnyObject {
    var isGameOverForInput: Bool { get }
    func inputControllerDidRequest(_ direction: MoveDirection)
}

final class PointerInputController: NSObject {
    weak var delegate: PointerInputControllerDelegate?

    private var lastPadDirection: MoveDirection?
    private let padDeadzone: Float = 0.35

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
