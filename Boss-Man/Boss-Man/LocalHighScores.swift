import Foundation

struct LocalHighScores {
    struct Entry: Codable {
        let name: String
        let score: Int
        let date: Date
    }

    static let storeKey = Strings.DefaultsKey.localHighScores
    static let maxEntries = 10

    static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    @discardableResult
    static func record(name: String, score: Int) -> Int? {
        guard score > 0 else {
            return nil
        }
        var all = load()

        // Only keep each player's highest score
        if let existing = all.firstIndex(where: { $0.name == name }) {
            guard score > all[existing].score else {
                return nil // Not a new high score — don't record
            }
            all.remove(at: existing)
        }

        let entry = Entry(name: name, score: score, date: Date())
        all.append(entry)
        all.sort { $0.score > $1.score }
        let trimmed = Array(all.prefix(maxEntries))
        guard let data = try? JSONEncoder().encode(trimmed) else {
            return nil
        }
        UserDefaults.standard.set(data, forKey: storeKey)
        UserDefaults.standard.synchronize()
        let rank = trimmed.firstIndex(where: { $0.date == entry.date }).map { $0 + 1 }
        return rank
    }

    /// Returns true if the given score would be a new entry or beat an existing one
    static func qualifies(name: String, score: Int) -> Bool {
        guard score > 0 else { return false }
        let all = load()
        if let existing = all.first(where: { $0.name == name }) {
            return score > existing.score
        }
        return all.count < maxEntries || score > (all.last?.score ?? 0)
    }

    // MARK: - Username persistence

    static let usernameKey = Strings.DefaultsKey.localLeaderboardUsername

    static var savedUsername: String? {
        get { UserDefaults.standard.string(forKey: usernameKey) }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }
}
