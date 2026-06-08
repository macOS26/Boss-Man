import KitABI

// Key codes match the kit runtime's SF_KEY table (SFML 2.6 enum values), which
// is what evt_poll / key_pressed report. Scenes poll skKeyIsDown for smooth
// movement or override keyDown/keyUp for discrete events.
public enum SKKey {
    public static let a = 0, c = 2, d = 3, e = 4, f = 5, p = 15, r = 17, s = 18, v = 21, w = 22, z = 25
    public static let escape = 36, space = 57, backspace = 59
    public static let left = 71, right = 72, up = 73, down = 74
}

public func skKeyIsDown(_ code: Int) -> Bool { key_pressed(Int32(code)) != 0 }
