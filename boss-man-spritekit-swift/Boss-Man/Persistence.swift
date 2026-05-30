#if os(macOS)
import Foundation
#elseif os(WASI)
import SpriteKit
import KitABI
#endif

// Key/value persistence with one API surface for shared code (LocalHighScores,
// HUD, title). The engine below is platform-neutral: numbers and bools are
// encoded as strings on top of a single raw string get/set primitive. The ONLY
// platform-specific code is `Backend` at the bottom — UserDefaults on apple,
// window.localStorage (via the kit's store_get/store_set) on wasm — so adding
// a platform means writing two functions, not editing every accessor.
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
    static func string(forKey key: String) -> String? {
        // Probe length with a 1-byte buffer; store_get returns the actual byte
        // length (or -1 if the key is absent), then read into a sized buffer.
        var probe: [Int8] = [0]
        let total = probe.withUnsafeMutableBufferPointer { p in
            withUTF8Bytes(key) { kp, kn in store_get(kp, kn, p.baseAddress, Int32(1)) }
        }
        if total < 0 { return nil }
        if total == 0 { return "" }
        var buf = [Int8](repeating: 0, count: Int(total) + 1)
        _ = buf.withUnsafeMutableBufferPointer { p -> Int32 in
            let cap = Int32(p.count)
            return withUTF8Bytes(key) { kp, kn in store_get(kp, kn, p.baseAddress, cap) }
        }
        return String(decoding: buf.prefix(Int(total)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    static func setString(_ value: String, forKey key: String) {
        withUTF8Bytes(key) { kp, kn in
            withUTF8Bytes(value) { vp, vn in store_set(kp, kn, vp, vn) }
        }
    }
    #endif
}

#if os(WASI)
// Hands a temporary C-string of `s` (UTF-8 bytes + length) to the closure.
@inline(__always)
private func withUTF8Bytes<R>(_ s: String, _ body: (UnsafePointer<CChar>, Int32) -> R) -> R {
    var str = s
    return str.withUTF8 { buf in
        guard let base = buf.baseAddress else { return body("".withCString { $0 }, 0) }
        return base.withMemoryRebound(to: CChar.self, capacity: buf.count) {
            body($0, Int32(buf.count))
        }
    }
}
#endif
