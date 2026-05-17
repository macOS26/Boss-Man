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
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: return nil
        }
    }
}
