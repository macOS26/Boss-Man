import KitABI

// Scene transitions. The kit renders straight to Canvas2D with no offscreen
// targets, so transitions are recorded as data only — SKView.presentScene
// swaps scenes immediately. Games keep their SKTransition factories intact;
// the visual effect simply collapses to an instant cut.
public final class SKTransition {
    public enum Kind {
        case crossFade, fade, doorway, push(Int), reveal(Int), moveIn(Int), flipHorizontal, flipVertical
    }
    public let kind: Kind
    public var duration: TimeInterval
    public var pausesIncomingScene = true
    public var pausesOutgoingScene = true

    init(_ kind: Kind, _ duration: TimeInterval) { self.kind = kind
    self.duration = duration }

    public static func crossFade(withDuration d: TimeInterval) -> SKTransition { SKTransition(.crossFade, d) }
    public static func fade(withDuration d: TimeInterval) -> SKTransition { SKTransition(.fade, d) }
    public static func fade(with color: SKColor, duration d: TimeInterval) -> SKTransition { SKTransition(.fade, d) }
    public static func doorway(withDuration d: TimeInterval) -> SKTransition { SKTransition(.doorway, d) }
    public static func push(with direction: Int, duration d: TimeInterval) -> SKTransition { SKTransition(.push(direction), d) }
    public static func reveal(with direction: Int, duration d: TimeInterval) -> SKTransition { SKTransition(.reveal(direction), d) }
    public static func moveIn(with direction: Int, duration d: TimeInterval) -> SKTransition { SKTransition(.moveIn(direction), d) }
    public static func flipHorizontal(withDuration d: TimeInterval) -> SKTransition { SKTransition(.flipHorizontal, d) }
    public static func flipVertical(withDuration d: TimeInterval) -> SKTransition { SKTransition(.flipVertical, d) }
}

// Mirror of SKTransitionDirection so call sites compile. Direction is recorded
// but the visual transition is a no-op (see above).
public enum SKTransitionDirection: Int { case up, down, right, left }

