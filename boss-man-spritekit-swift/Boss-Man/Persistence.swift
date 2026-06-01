import SpriteKit

// Key/value persistence with one API surface for shared code (LocalHighScores,
// HUD, title). The engine is platform-neutral: numbers and bools are encoded as
// strings on top of a single raw string get/set primitive. The backend is
// UserDefaults on every platform — Foundation's on Apple, the framework's
// localStorage-backed shim on wasm — so this whole file is common.
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
    static func bool(forKey key: String) -> Bool { bool(forKey: key, default: false) }
    // Returns `def` when the key was never written, so callers can default a
    // toggle to true (e.g. Boss Tracks defaults to Square).
    static func bool(forKey key: String, default def: Bool) -> Bool {
        guard let s = Backend.string(forKey: key), !s.isEmpty else { return def }
        switch s {
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

// MARK: - Backend (common: UserDefaults on every platform)
private enum Backend {
    static func string(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    static func setString(_ value: String, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}
