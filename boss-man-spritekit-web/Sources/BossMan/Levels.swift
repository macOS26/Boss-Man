import SpriteKit

// Level data, wasm port. The original macOS build pulls a [String: [String]]
// dictionary from Bundle.main + JSONDecoder; on web the kit's MiniJSON parser
// reads it back out of asset_text("levels.json") after the runtime preloader
// registers it via manifest.json.
//
// Schema (matches the macOS levels.json one-for-one):
//   { "Level 1": ["<row 0>", "<row 1>", ...], "Level 2": [...], ... }
//
// Each row uses Strings.Tile.* characters. Length and column count are
// homogeneous within a level (the parser doesn't enforce padding — author
// responsibility).
enum Levels {
    static let names: [String] = (1...24).map { "Level \($0)" }

    // Lazily loaded; first access reads the asset, parses MiniJSON, caches.
    static var officeMaps: [[String]] {
        if let cached = _cache { return cached }
        let loaded = loadFromAsset() ?? Array(repeating: emptyLevelRows(), count: names.count)
        _cache = loaded
        return loaded
    }
    private nonisolated(unsafe) static var _cache: [[String]]? = nil

    // Force a reload — the LevelEditorScene rewrites the file when in dev mode.
    static func invalidateCache() { _cache = nil }

    private static func loadFromAsset() -> [[String]]? {
        guard let text = SKSceneLoader.loadAssetText("levels.json"),
              let obj = parseJSON(text) as? [String: Any] else { return nil }
        return names.map { name in
            guard let rowsAny = obj[name] as? [Any] else { return emptyLevelRows() }
            return rowsAny.compactMap { $0 as? String }
        }
    }

    private static func emptyLevelRows() -> [String] {
        // Same fallback shape the macOS build uses when the bundle resource
        // is missing: 38-wide, 17-tall outline with a row-8 tunnel cutout.
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
