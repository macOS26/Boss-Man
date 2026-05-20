import Foundation

/// Device-local top-N high scores backed by UserDefaults. Used by
/// LeaderboardPanel as a fallback when Game Center isn't configured
/// (no .gamekit bundle, no App Store Connect leaderboard) so the title
/// screen still has something meaningful to display.
struct LocalHighScores {
    struct Entry: Codable {
        let name: String
        let score: Int
        let date: Date
    }

    static let storeKey = "Boss-Man.localHighScores"
    static let maxEntries = 10

    static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    /// Inserts the score if it qualifies for the top-N, returns the
    /// rank (1-based) of the newly-inserted entry or nil if it didn't
    /// make the cut.
    @discardableResult
    static func record(name: String, score: Int) -> Int? {
        guard score > 0 else { return nil }
        var all = load()
        all.append(Entry(name: name, score: score, date: Date()))
        all.sort { $0.score > $1.score }
        let trimmed = Array(all.prefix(maxEntries))
        guard let data = try? JSONEncoder().encode(trimmed) else { return nil }
        UserDefaults.standard.set(data, forKey: storeKey)
        return trimmed.firstIndex(where: { $0.score == score && $0.name == name }).map { $0 + 1 }
    }
}
