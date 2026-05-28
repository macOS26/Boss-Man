import SpriteKit

// Top-10 local leaderboard, persisted as JSON in localStorage under
// Strings.DefaultsKey.leaderboard. The macOS build does the same trick with
// UserDefaults; on web we go through Persistence's store_get/set bridge.
//
// JSON shape (deliberately short keys to keep the stored string compact):
//   [ { "n": "TOD", "s": 1234 }, ... ]
struct LocalHighScores {
    struct Entry: Equatable {
        let name: String
        let score: Int
    }

    static let cap = 10

    // Persisted username from the last "save" in the game-over dialog.
    // bossman-apple keeps this in UserDefaults; we go through Persistence's
    // localStorage bridge under the same conceptual key.
    static var savedUsername: String? {
        get { Persistence.string(forKey: Strings.DefaultsKey.localLeaderboardUsername) }
        set {
            if let v = newValue { Persistence.setString(v, forKey: Strings.DefaultsKey.localLeaderboardUsername) }
        }
    }

    // MARK: - Read
    static func load() -> [Entry] {
        guard let raw = Persistence.string(forKey: Strings.DefaultsKey.leaderboard),
              !raw.isEmpty,
              let arr = parseJSON(raw) as? [Any] else { return [] }
        var out: [Entry] = []
        for item in arr.prefix(cap) {
            guard let row = item as? [String: Any],
                  let n = row["n"] as? String,
                  let s = (row["s"] as? Double).map({ Int($0) }) ?? (row["s"] as? Int) else { continue }
            out.append(Entry(name: n, score: s))
        }
        return out
    }

    // MARK: - Write
    @discardableResult
    static func submit(name: String, score: Int) -> [Entry] {
        var current = load()
        current.append(Entry(name: name, score: score))
        current.sort { $0.score > $1.score }
        let trimmed = Array(current.prefix(cap))
        Persistence.setString(encode(trimmed), forKey: Strings.DefaultsKey.leaderboard)
        return trimmed
    }

    // MARK: - JSON encoder (hand-rolled — Foundation's JSONEncoder isn't
    // available on every WASI toolchain configuration; the schema is tiny
    // enough that emitting it directly is clearer than threading a generic
    // Codable through).
    private static func encode(_ entries: [Entry]) -> String {
        var out = "["
        for (i, e) in entries.enumerated() {
            if i > 0 { out += "," }
            out += "{\"n\":\"\(escape(e.name))\",\"s\":\(e.score)}"
        }
        out += "]"
        return out
    }
    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:   out.append(ch)
            }
        }
        return out
    }
}
