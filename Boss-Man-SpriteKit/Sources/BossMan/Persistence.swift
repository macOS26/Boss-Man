import SpriteKit
import KitABI

// Thin localStorage wrapper. The kit's runtime persists keys via store_get /
// store_set which back into window.localStorage. We mirror just enough of
// the UserDefaults surface that title/HUD/leaderboard code can read and write
// numbers, strings, and JSON-encoded payloads with one-line calls.
enum Persistence {
    // MARK: - Reads

    static func int(forKey key: String) -> Int {
        guard let s = string(forKey: key), let v = Int(s) else { return 0 }
        return v
    }
    static func double(forKey key: String) -> Double {
        guard let s = string(forKey: key), let v = Double(s) else { return 0 }
        return v
    }
    static func bool(forKey key: String) -> Bool {
        switch string(forKey: key) ?? "" {
        case "1", "true", "yes": return true
        default: return false
        }
    }
    static func string(forKey key: String) -> String? {
        // First pass: probe length with a 1-byte buffer; store_get returns
        // the actual byte length (or -1 if the key is absent).
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

    // MARK: - Writes

    static func set(_ value: Int, forKey key: String)    { setString(String(value), forKey: key) }
    static func set(_ value: Double, forKey key: String) { setString(String(value), forKey: key) }
    static func set(_ value: Bool, forKey key: String)   { setString(value ? "1" : "0", forKey: key) }
    static func setString(_ value: String, forKey key: String) {
        withUTF8Bytes(key) { kp, kn in
            withUTF8Bytes(value) { vp, vn in store_set(kp, kn, vp, vn) }
        }
    }
}

// Helper that hands a temporary C-string of `s` (UTF-8 bytes + length) to the
// closure. Locally defined so this file doesn't need to import the kit's
// SpriteKit module just to reuse withUTF8Ptr.
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
