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
// Level travelers ported verbatim from bossman-apple's Levels.swift.
// Each level cycles through this table to pick the bonus emoji that flies
// across the maze for a bonus pickup. The HUD shows the upcoming sequence
// in the top-right corner.
enum TravelerSound {
    case water, glaze, crunch, alienBleep, jelly, crispTap, bellDing
    case radioStatic, magicChime, ufoWhoosh, eyeDrone, bigEye
}

struct LevelTraveler {
    let emoji: String
    let sound: TravelerSound
    let points: Int
    let image: String?
    let facesRight: Bool

    init(emoji: String, sound: TravelerSound, points: Int, image: String? = nil, facesRight: Bool = false) {
        self.emoji = emoji
        self.sound = sound
        self.points = points
        self.image = image
        self.facesRight = facesRight
    }
}

let levelTravelers: [LevelTraveler] = [
    LevelTraveler(emoji: "\u{1F41F}", sound: .water,       points: 100),     // 🐟
    LevelTraveler(emoji: "\u{1F369}", sound: .glaze,       points: 200),     // 🍩
    LevelTraveler(emoji: "\u{2615}\u{FE0F}", sound: .crunch,    points: 400),// ☕
    LevelTraveler(emoji: "\u{1F964}", sound: .alienBleep,  points: 800),     // 🥤
    LevelTraveler(emoji: "\u{1F34E}", sound: .jelly,       points: 1000),    // 🍎
    LevelTraveler(emoji: "\u{2702}\u{FE0F}", sound: .crispTap,  points: 2000,
                  image: "red-stapler", facesRight: true),                    // ✂
    LevelTraveler(emoji: "\u{1F349}", sound: .bellDing,    points: 3000),    // 🍉
    LevelTraveler(emoji: "\u{1F9C7}", sound: .radioStatic, points: 4000),    // 🧇
    LevelTraveler(emoji: "\u{1F366}", sound: .magicChime,  points: 5000),    // 🍦
    LevelTraveler(emoji: "\u{1F370}", sound: .ufoWhoosh,   points: 6000),    // 🍰
    LevelTraveler(emoji: "\u{1F440}", sound: .eyeDrone,    points: 7000),    // 👀
    LevelTraveler(emoji: "\u{1F441}\u{FE0F}", sound: .bigEye, points: 8000), // 👁
]

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
