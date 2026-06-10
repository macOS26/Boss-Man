#if os(macOS)
import AppKit
#else
import SpriteKit
#endif

// Translates a physical key event (mac virtual keyCode on every platform; the
// wasm framework translates the runtime's codes) into the
// GameOverScreen.handleKey index space (0-25 = A-Z, 26-35 = 0-9, 57 = space,
// 58 = enter, 59 = backspace, 36 = esc). Shared by the 2D GameScene and the 3D
// DoomScene so both type a qualifying score's name into the same field.
func usernameKeyCode(for event: NSEvent) -> Int {
    switch event.keyCode {
    case 36, 76: return 58
    case 53:     return 36
    case 51:     return 59
    case 49:     return 57
    default:
        guard let u = (event.charactersIgnoringModifiers ?? "").uppercased().unicodeScalars.first else { return -1 }
        if u.value >= 65, u.value <= 90 { return Int(u.value) - 65 }
        if u.value >= 48, u.value <= 57 { return 26 + Int(u.value) - 48 }
        return -1
    }
}
