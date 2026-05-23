//
//  levels.swift
//  Boss-Man
//
//  Created by Todd Bruss on 5/16/26.
//

import Foundation

// Level names for the editor (one per officeMaps entry)
struct Levels {
    static let levelNames: [String] = [
        "Level 1 - 🐟",  "Level 2 - 🍩",  "Level 3 - 🥨",
        "Level 4 - 👾",  "Level 5 - 🪼",  "Level 6 - 🍏",
        "Level 7 - 🍎",  "Level 8 - 📻",  "Level 9 - 🦄",
        "Level 10 - 👽", "Level 11 - 👀", "Level 12 - 👁️"
    ]
}

enum TravelerSound {
    case water, glaze, crunch, alienBleep, jelly, crispTap, bellDing, radioStatic, magicChime, ufoWhoosh, eyeDrone, bigEye
}

struct LevelTraveler {
    let emoji: String
    let sound: TravelerSound
    let points: Int
}

// Ms. Pac-Man-style level mascots: each level has a roaming emoji that
// crosses the floor twice and plays a distinct distant sound on arrival.
let levelTravelers: [LevelTraveler] = [
    LevelTraveler(emoji: "🐟", sound: .water,       points: 100),
    LevelTraveler(emoji: "🍩", sound: .glaze,       points: 200),
    LevelTraveler(emoji: "🥨", sound: .crunch,      points: 400),
    LevelTraveler(emoji: "👾", sound: .alienBleep,  points: 800),
    LevelTraveler(emoji: "🪼", sound: .jelly,       points: 1000),
    LevelTraveler(emoji: "🍏", sound: .crispTap,    points: 2000),
    LevelTraveler(emoji: "🍎", sound: .bellDing,    points: 3000),
    LevelTraveler(emoji: "📻", sound: .radioStatic, points: 4000),
    LevelTraveler(emoji: "🦄", sound: .magicChime,  points: 5000),
    LevelTraveler(emoji: "👽", sound: .ufoWhoosh,   points: 6000),
    LevelTraveler(emoji: "👀", sound: .eyeDrone,    points: 7000),
    LevelTraveler(emoji: "👁️", sound: .bigEye,    points: 8000)
]

// Bundled default levels. The source of truth is `Boss-Man/levels.json`
// in the app bundle — same JSON format LevelStore uses for user edits:
//
//   { "Level 1 - Office": ["row1", "row2", ...], ... }
//
// Edit that file directly to update defaults, or copy/paste between it
// and the user's Application Support file. Falls back to a single empty
// 17×36 level if the bundle file is missing or malformed.
let officeMaps: [[String]] = loadOfficeMapsFromBundle()

private func loadOfficeMapsFromBundle() -> [[String]] {
    guard let url = Bundle.main.url(forResource: "levels", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
    else {
        return Array(repeating: emptyLevelRows(), count: Levels.levelNames.count)
    }
    // Keep the order of Levels.levelNames; missing entries get an empty
    // template so the indexed lookups in GameScene never crash.
    return Levels.levelNames.map { dict[$0] ?? emptyLevelRows() }
}

private func emptyLevelRows() -> [String] {
    var rows: [String] = []
    let topBottom = String(repeating: "#", count: 18) + " " + String(repeating: "#", count: 17)
    rows.append(topBottom)
    for r in 1...15 {
        let leftEdge: Character = (r == 8) ? " " : "#"
        let rightEdge: Character = (r == 8) ? " " : "#"
        rows.append(String(leftEdge) + String(repeating: ".", count: 34) + String(rightEdge))
    }
    rows.append(topBottom)
    return rows
}
