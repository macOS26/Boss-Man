import Foundation

enum MoveDirection {
    case left, right, down, up

    var delta: (dx: Int, dy: Int) {
        switch self {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .down: (0, -1)
        case .up: (0, 1)
        }
    }

    init?(keyCode: UInt16) {
        switch keyCode {
        case 123, 0:  self = .left   // ← / A
        case 124, 2:  self = .right  // → / D
        case 125, 1:  self = .down   // ↓ / S
        case 126, 13: self = .up     // ↑ / W
        default: return nil
        }
    }
}
