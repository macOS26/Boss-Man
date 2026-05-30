#if os(macOS)
import Foundation
#elseif os(WASI)
import SpriteKit
#endif

// Key/value persistence with one API surface for shared code (LocalHighScores,
// HUD, title). The engine below is platform-neutral: numbers and bools are
// encoded as strings on top of a single raw string get/set primitive. The ONLY
// platform-specific code is `Backend` at the bottom — UserDefaults on apple,
// the framework's LocalStore (window.localStorage) on wasm — so adding a
// platform means writing two functions, not editing every accessor.
enum Persistence {
    // MARK: - Reads
    static func int(forKey key: String) -> Int {
        guard let s = Backend.string(forKey: key), let v = Int(s) else { return 0 }
        return v
    }
    static func double(forKey key: String) -> Double {
        guard let s = Backend.string(forKey: key), let v = Double(s) else { return 0 }
        return v
    }
    static func bool(forKey key: String) -> Bool {
        switch Backend.string(forKey: key) ?? "" {
        case "1", "true", "yes": return true
        default: return false
        }
    }
    static func string(forKey key: String) -> String? { Backend.string(forKey: key) }

    // MARK: - Writes
    static func set(_ value: Int, forKey key: String)    { Backend.setString(String(value), forKey: key) }
    static func set(_ value: Double, forKey key: String) { Backend.setString(String(value), forKey: key) }
    static func set(_ value: Bool, forKey key: String)   { Backend.setString(value ? "1" : "0", forKey: key) }
    static func setString(_ value: String, forKey key: String) { Backend.setString(value, forKey: key) }
}

// MARK: - Platform backend (the only per-platform code)
private enum Backend {
    #if os(macOS)
    static func string(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    static func setString(_ value: String, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
    #elseif os(WASI)
    static func string(forKey key: String) -> String? { LocalStore.string(forKey: key) }
    static func setString(_ value: String, forKey key: String) { LocalStore.setString(value, forKey: key) }
    #endif
}
