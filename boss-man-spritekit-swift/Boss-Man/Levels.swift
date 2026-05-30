import Foundation
import SpriteKit

enum Levels {
    static let levelNames: [String] = (1...24).map { "Level \($0)" }

    // Lazily loaded; first access reads + parses the level data, caches it.
    static var officeMaps: [[String]] {
        if let cached = _cache { return cached }
        let loaded = loadFromAsset() ?? Array(repeating: emptyLevelRows(), count: levelNames.count)
        _cache = loaded
        return loaded
    }
    private nonisolated(unsafe) static var _cache: [[String]]? = nil

    // Force a reload — the in-game LevelEditorScene rewrites the level data.
    static func invalidateCache() { _cache = nil }

    private static func loadFromAsset() -> [[String]]? {
#if os(macOS)
        guard let url = Bundle.main.url(forResource: Strings.Resource.levelsFile,
                                         withExtension: Strings.Resource.levelsExtension),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return nil }
        return levelNames.map { dict[$0] ?? emptyLevelRows() }
#elseif os(WASI)
        guard let text = SKSceneLoader.loadAssetText("levels.json"),
              let obj = parseJSON(text) as? [String: Any] else { return nil }
        return levelNames.map { name in
            guard let rowsAny = obj[name] as? [Any] else { return emptyLevelRows() }
            return rowsAny.compactMap { $0 as? String }
        }
#endif
    }

    private static func emptyLevelRows() -> [String] {
        // 38-wide, 17-tall outline with a row-8 tunnel cutout — the fallback
        // shape used when the level resource is missing.
        let topBottom = String(repeating: "#", count: 18) + " " + String(repeating: "#", count: 17)
        var rows: [String] = [topBottom]
        for r in 1...15 {
            let edge: Character = (r == 8) ? " " : "#"
            rows.append(String(edge) + String(repeating: ".", count: 34) + String(edge))
        }
        rows.append(topBottom)
        return rows
    }
}
