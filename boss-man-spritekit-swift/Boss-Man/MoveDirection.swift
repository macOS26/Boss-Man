import Foundation

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

    // Arrow keys + WASD. The key-to-direction mapping is shared; only the raw
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

// Physical movement key codes. Values are platform-specific; the names are
// common so the key-to-direction logic lives in one place.
enum KeyCode {
#if os(macOS)
    static let arrowLeft  = 123
    static let arrowRight = 124
    static let arrowDown  = 125
    static let arrowUp    = 126
    static let keyA = 0
    static let keyD = 2
    static let keyS = 1
    static let keyW = 13
    static let keyP = 35
    static let keyE = 14
    static let keyF = 3
    static let esc = 53
    static let space = 49
#elseif os(WASI)
    static let arrowLeft  = 71
    static let arrowRight = 72
    static let arrowDown  = 74
    static let arrowUp    = 73
    static let keyA = 0
    static let keyD = 3
    static let keyS = 18
    static let keyW = 22
    static let keyP = 15
    static let keyE = 4
    static let keyF = 5
    static let esc = 36
    static let space = 57
#endif
}
