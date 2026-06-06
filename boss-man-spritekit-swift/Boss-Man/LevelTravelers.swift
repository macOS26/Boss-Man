// Bonus "traveler" pickups: the emoji that flies across the maze each level for
// a bonus. Each level cycles through this table to pick the next one; the HUD
// shows the upcoming sequence in the top-right corner. Shared verbatim across
// apple + wasm. The per-platform level-map loader stays in each port's own
// Levels.swift.
enum TravelerSound {
    case water, glaze, crunch, alienBleep, jelly, crispTap, bellDing, radioStatic, magicChime, ufoWhoosh, eyeDrone, bigEye
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
    LevelTraveler(emoji: "🐟", sound: .water,       points: 100),
    LevelTraveler(emoji: "🍩", sound: .glaze,       points: 200),
    LevelTraveler(emoji: "☕️", sound: .crunch,      points: 400),
    LevelTraveler(emoji: "🥤", sound: .alienBleep,  points: 800),
    LevelTraveler(emoji: "🍎", sound: .jelly,       points: 1000),
    LevelTraveler(emoji: "✂️", sound: .crispTap,    points: 2000, image: Strings.Resource.travelerStaplerFile, facesRight: true),
    LevelTraveler(emoji: "🍉", sound: .bellDing,    points: 3000),
    LevelTraveler(emoji: "🧇", sound: .radioStatic, points: 4000),
    LevelTraveler(emoji: "🍦", sound: .magicChime,  points: 5000),
    LevelTraveler(emoji: "🍰", sound: .ufoWhoosh,   points: 6000),
    LevelTraveler(emoji: "👀", sound: .eyeDrone,    points: 7000),
    LevelTraveler(emoji: "👁️", sound: .bigEye,      points: 8000)
]
