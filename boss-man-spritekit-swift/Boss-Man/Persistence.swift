#if os(macOS)
import Foundation
#elseif os(WASI)
import SpriteKit
import KitABI
#endif

// Key/value persistence with one API surface so shared code (LocalHighScores,
// HUD, title) reads and writes identically on both ports. Only the backend
// differs: UserDefaults on apple, window.localStorage (via the kit's
// store_get/store_set) on wasm.
enum Persistence {
    // MARK: - Reads

    static func int(forKey key: String) -> Int {
        #if os(macOS)
        return UserDefaults.standard.integer(forKey: key)
        #elseif os(WASI)
        guard let s = string(forKey: key), let v = Int(s) else { return 0 }
        return v
        #endif
    }

    static func double(forKey key: String) -> Double {
        #if os(macOS)
        return UserDefaults.standard.double(forKey: key)
        #elseif os(WASI)
        guard let s = string(forKey: key), let v = Double(s) else { return 0 }
        return v
        #endif
    }

    static func bool(forKey key: String) -> Bool {
        #if os(macOS)
        return UserDefaults.standard.bool(forKey: key)
        #elseif os(WASI)
        switch string(forKey: key) ?? "" {
        case "1", "true", "yes": return true
        default: return false
        }
        #endif
    }

    static func string(forKey key: String) -> String? {
        #if os(macOS)
        return UserDefaults.standard.string(forKey: key)
        #elseif os(WASI)
        // First pass: probe length with a 1-byte buffer; store_get returns the
        // actual byte length (or -1 if the key is absent).
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
        #endif
    }

    // MARK: - Writes

    static func set(_ value: Int, forKey key: String) {
        #if os(macOS)
        UserDefaults.standard.set(value, forKey: key)
        #elseif os(WASI)
        setString(String(value), forKey: key)
        #endif
    }

    static func set(_ value: Double, forKey key: String) {
        #if os(macOS)
        UserDefaults.standard.set(value, forKey: key)
        #elseif os(WASI)
        setString(String(value), forKey: key)
        #endif
    }

    static func set(_ value: Bool, forKey key: String) {
        #if os(macOS)
        UserDefaults.standard.set(value, forKey: key)
        #elseif os(WASI)
        setString(value ? "1" : "0", forKey: key)
        #endif
    }

    static func setString(_ value: String, forKey key: String) {
        #if os(macOS)
        UserDefaults.standard.set(value, forKey: key)
        #elseif os(WASI)
        withUTF8Bytes(key) { kp, kn in
            withUTF8Bytes(value) { vp, vn in store_set(kp, kn, vp, vn) }
        }
        #endif
    }
}

#if os(WASI)
// Hands a temporary C-string of `s` (UTF-8 bytes + length) to the closure.
// Locally defined so this file doesn't pull in the kit's withUTF8Ptr.
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
