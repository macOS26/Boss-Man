import Foundation

// UserDefaults-backed mirror of the wasm port's Persistence (which bridges to
// localStorage via store_get/set). Same API surface, so shared code such as
// LocalHighScores reads and writes identically on both platforms; only the
// storage backend differs per platform.
enum Persistence {
    static func int(forKey key: String) -> Int       { UserDefaults.standard.integer(forKey: key) }
    static func double(forKey key: String) -> Double  { UserDefaults.standard.double(forKey: key) }
    static func bool(forKey key: String) -> Bool      { UserDefaults.standard.bool(forKey: key) }
    static func string(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }

    static func set(_ value: Int, forKey key: String)        { UserDefaults.standard.set(value, forKey: key) }
    static func set(_ value: Double, forKey key: String)     { UserDefaults.standard.set(value, forKey: key) }
    static func set(_ value: Bool, forKey key: String)       { UserDefaults.standard.set(value, forKey: key) }
    static func setString(_ value: String, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}
