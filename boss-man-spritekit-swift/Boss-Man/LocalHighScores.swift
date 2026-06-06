// Local high-score leaderboard, shared verbatim by the apple and wasm builds.
// Storage goes through Persistence (UserDefaults on apple, localStorage on web);
// the payload is hand-rolled JSON ([{"n":NAME,"s":SCORE}, ...]) because
// Foundation's JSONEncoder/Codable isn't available on the WASI toolchain.
//
// Game-Center-style local rules: ONE entry per unique name; a submission only
// overwrites that name's entry when it beats their own best (otherwise it is not
// recorded, so the same name is never logged twice); sorted, top-10.
struct LocalHighScores {
    struct Entry: Equatable {
        let name: String
        let score: Int
    }

    static let maxEntries = 10
    private static let storeKey = Strings.DefaultsKey.localHighScores
    private static let usernameKey = Strings.DefaultsKey.localLeaderboardName

    // MARK: - Username
    static var savedUsername: String? {
        get { Persistence.string(forKey: usernameKey) }
        set { if let v = newValue { Persistence.setString(v, forKey: usernameKey) } }
    }

    // MARK: - Read
    static func load() -> [Entry] {
        guard let raw = Persistence.string(forKey: storeKey), !raw.isEmpty else { return [] }
        return decode(raw).filter { !isAnonymous($0.name) }
    }

    // An anonymous / blank entry never belongs on the leaderboard. ASCII-only
    // upcase compare: String.uppercased() would drag ICU's tables into the wasm.
    private static func isAnonymous(_ name: String) -> Bool {
        if name.isEmpty { return true }
        let up = String(String.UnicodeScalarView(name.unicodeScalars.map {
            ($0.value >= 97 && $0.value <= 122) ? Unicode.Scalar($0.value - 32)! : $0
        }))
        return up == "ANON"
    }

    // MARK: - Write (per-name best)
    @discardableResult
    static func record(name: String, score: Int) -> Int? {
        guard score > 0, !isAnonymous(name) else { return nil }
        var all = load()
        if let i = all.firstIndex(where: { $0.name == name }) {
            guard score > all[i].score else { return nil }
            all.remove(at: i)
        }
        all.append(Entry(name: name, score: score))
        all.sort { $0.score > $1.score }
        all = Array(all.prefix(maxEntries))
        Persistence.setString(encode(all), forKey: storeKey)
        return all.firstIndex(where: { $0.name == name && $0.score == score }).map { $0 + 1 }
    }

    static func qualifies(name: String, score: Int) -> Bool {
        guard score > 0 else { return false }
        let all = load()
        if let existing = all.first(where: { $0.name == name }) { return score > existing.score }
        return all.count < maxEntries || score > (all.last?.score ?? 0)
    }

    // Name-independent: would this score land on the board at all (open slot, or
    // beats the lowest entry)? Drives whether the game-over screen offers name
    // entry, matching the C++ LocalLeaderboard.qualifies.
    static func qualifiesForBoard(score: Int) -> Bool {
        guard score > 0 else { return false }
        let all = load()
        return all.count < maxEntries || score > (all.last?.score ?? 0)
    }

    @discardableResult
    static func submit(name: String, score: Int) -> [Entry] {
        record(name: name, score: score)
        return load()
    }

    static func clear() {
        Persistence.setString("", forKey: storeKey)
    }

    // MARK: - Hand-rolled JSON (no Codable; runs on apple + WASI)
    private static func encode(_ entries: [Entry]) -> String {
        var out = "["
        for (i, e) in entries.enumerated() {
            if i > 0 { out += "," }
            out += "{\"n\":\"\(jsonEscape(e.name))\",\"s\":\(e.score)}"
        }
        return out + "]"
    }

    private static func decode(_ raw: String) -> [Entry] {
        var out: [Entry] = []
        let a = Array(raw)
        let n = a.count
        var i = 0
        while out.count < maxEntries {
            guard let ns = indexAfter(a, n, from: i, of: "\"n\":\"") else { break }
            var k = ns
            var name = ""
            while k < n, a[k] != "\"" {
                if a[k] == "\\", k + 1 < n {
                    switch a[k + 1] {
                    case "n": name.append("\n")
                    case "t": name.append("\t")
                    case "r": name.append("\r")
                    default:  name.append(a[k + 1])
                    }
                    k += 2
                } else {
                    name.append(a[k]); k += 1
                }
            }
            guard let ss = indexAfter(a, n, from: k, of: "\"s\":") else { break }
            var j = ss
            var num = ""
            while j < n, a[j].isNumber || a[j] == "-" { num.append(a[j]); j += 1 }
            guard let s = Int(num) else { break }
            out.append(Entry(name: name, score: s))
            i = j
        }
        return out
    }

    private static func indexAfter(_ a: [Character], _ n: Int, from: Int, of token: String) -> Int? {
        let t = Array(token)
        let tn = t.count
        guard tn > 0 else { return from }
        var i = from
        while i + tn <= n {
            var match = true
            for x in 0..<tn where a[i + x] != t[x] { match = false; break }
            if match { return i + tn }
            i += 1
        }
        return nil
    }

}
