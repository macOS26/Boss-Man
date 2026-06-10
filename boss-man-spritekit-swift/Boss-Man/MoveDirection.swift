enum MoveDirection: CaseIterable {
    case left, right, down, up

    var delta: (dx: Int, dy: Int) {
        switch self {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .down: (0, -1)
        case .up: (0, 1)
        }
    }

    // Arrow keys + WASD. The key-to-direction mapping is shared, only the raw
    // code values differ per platform (Carbon virtual codes on macOS, the web
    // runtime's codes on wasm).
    init?(keyCode: Int) {
        switch keyCode {
        case KeyCode.arrowLeft,  KeyCode.keyA: self = .left
        case KeyCode.arrowRight, KeyCode.keyD: self = .right
        case KeyCode.arrowDown,  KeyCode.keyS: self = .down
        case KeyCode.arrowUp,    KeyCode.keyW: self = .up
        default: return nil
        }
    }
}

// Physical movement key codes (macOS virtual codes; the wasm framework
// translates the runtime's codes to these, so one table serves every platform).
enum KeyCode {
    static let arrowLeft  = 123
    static let arrowRight = 124
    static let arrowDown  = 125
    static let arrowUp    = 126
    static let keyA = 0
    static let keyD = 2
    static let keyS = 1
    static let keyW = 13
    static let keyP = 35
    static let keyB = 11
    static let keyE = 14
    static let keyF = 3
    static let esc = 53
    static let space = 49
    static let keyC = 8
    static let keyV = 9
    static let keyZ = 6
    static let keyY = 16
    static let keyR = 15
    static let delete = 51
    static let digit0 = 29
    static let digit1 = 18
    static let digit2 = 19
    static let digit3 = 20
    static let digit4 = 21
    static let digit5 = 23
    static let digit6 = 22
    static let digit7 = 26
    static let digit8 = 28
}
