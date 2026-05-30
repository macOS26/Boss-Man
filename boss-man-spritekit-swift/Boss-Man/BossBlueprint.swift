import SpriteKit

// Per-boss AI config (name / personality / speed) for blueprint indices
// 0..3 = Bill / Dom / Bob / Stan. Shared by both ports: the wasm BossController
// reads it directly; apple's BossController builds its richer blueprint table
// (adding the per-boss NSColor palette + spawn slot) on top of this. Boss
// colors come from each port's SpriteFactory, spawn positions from the level map.
enum BossBlueprint {
    static let table: [(name: String, personality: BossPersonality, speed: Double)] = [
        (Strings.Boss.bill, .directChase,                                                  1.00),
        (Strings.Boss.dom,  .ambushAhead(tiles: 4),                                         0.85),
        (Strings.Boss.bob,  .flanker(pivotTiles: 2),                                        0.78),
        (Strings.Boss.stan, .timidScatter(scatterGrid: CGPoint(x: 1, y: 1), threshold: 8),  0.70),
    ]
}
