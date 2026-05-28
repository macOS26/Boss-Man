// One of the four maze cardinals. Used by both Pete (worker) and the boss as
// the unit step within the grid. delta is column/row deltas in tile space;
// the init(keyCode:) maps the kit's SF keyboard codes (see runtime.js SF_KEY
// table) onto a direction so WASD and arrow keys both work.
enum MoveDirection {
    case left, right, down, up

    var delta: (dx: Int, dy: Int) {
        switch self {
        case .left:  (-1, 0)
        case .right: ( 1, 0)
        case .down:  ( 0, -1)
        case .up:    ( 0,  1)
        }
    }

    init?(keyCode: Int) {
        switch keyCode {
        case 71, 0:  self = .left    // ArrowLeft / A
        case 72, 3:  self = .right   // ArrowRight / D
        case 74, 18: self = .down    // ArrowDown / S
        case 73, 22: self = .up      // ArrowUp / W
        default: return nil
        }
    }
}
