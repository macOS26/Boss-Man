import SpriteKit

// Per-blueprint config matching bossman-apple's BossController.blueprints.
// Indices 0..3 map to Bill / Dom / Bob / Stan with their personality + speed.
// Web-only: on apple the richer blueprint table (with colors + spawn) lives
// inline in BossController; the web reads colors from SpriteFactory instead, so
// only this slim name/personality/speed table is needed here. Kept out of the
// common BossAI.swift so that file can symlink to the apple master verbatim.
enum BossBlueprint {
    static let table: [(name: String, personality: BossPersonality, speed: Double)] = [
        (Strings.Boss.bill, .directChase,                                                  1.00),
        (Strings.Boss.dom,  .ambushAhead(tiles: 4),                                         0.85),
        (Strings.Boss.bob,  .flanker(pivotTiles: 2),                                        0.78),
        (Strings.Boss.stan, .timidScatter(scatterGrid: CGPoint(x: 1, y: 1), threshold: 8),  0.70),
    ]
}
