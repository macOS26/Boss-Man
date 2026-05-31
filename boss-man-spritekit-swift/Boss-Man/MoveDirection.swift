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

#if os(macOS)
    init?(keyCode: UInt16) {
        switch keyCode {
        case 123, 0:  self = .left
        case 124, 2:  self = .right
        case 125, 1:  self = .down
        case 126, 13: self = .up
        default: return nil
        }
    }
#elseif os(WASI)
    init?(keyCode: Int) {
        switch keyCode {
        case 71, 0:  self = .left
        case 72, 3:  self = .right
        case 74, 18: self = .down
        case 73, 22: self = .up
        default: return nil
        }
    }
#endif
}
