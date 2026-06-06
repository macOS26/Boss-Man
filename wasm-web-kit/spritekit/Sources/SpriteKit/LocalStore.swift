import KitABI

// Reusable key/value persistence backed by window.localStorage through the
// runtime's store_get / store_set. Strings only — callers encode richer types
// on top (e.g. a game's Persistence layer builds its int/double/bool engine on
// this). Any game ported onto SuperBox64 can use it for save data, so the
// localStorage plumbing lives here in the framework rather than in each game.
public enum LocalStore {
    public static func string(forKey key: String) -> String? {
        // Probe the byte length with a 1-byte buffer (store_get returns the real
        // length, or -1 when the key is absent), then read into a sized buffer.
        var probe: [Int8] = [0]
        let total = probe.withUnsafeMutableBufferPointer { p in
            withUTF8Ptr(key) { kp, kn in store_get(kp, kn, p.baseAddress, Int32(1)) }
        }
        if total < 0 { return nil }
        if total == 0 { return "" }
        var buf = [Int8](repeating: 0, count: Int(total) + 1)
        _ = buf.withUnsafeMutableBufferPointer { p -> Int32 in
            let cap = Int32(p.count)
            return withUTF8Ptr(key) { kp, kn in store_get(kp, kn, p.baseAddress, cap) }
        }
        return String(decoding: buf.prefix(Int(total)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func setString(_ value: String, forKey key: String) {
        withUTF8Ptr(key) { kp, kn in
            withUTF8Ptr(value) { vp, vn in store_set(kp, kn, vp, vn) }
        }
    }
}

// Browser "Save As" download: the host wraps the contents in a Blob and clicks a
// download anchor so the user keeps a real file. Web equivalent of revealing a
// saved file in Finder; the localStorage blob stays the source of truth.
public enum WebDownload {
    public static func file(named name: String, contents: String) {
        withUTF8Ptr(name) { np, nn in
            withUTF8Ptr(contents) { cp, cn in win_download(np, nn, cp, cn) }
        }
    }
}
