import SpriteKit

// Per-boss AI config (name / personality / speed) + body/tie palette for
// blueprint indices 0..3 = Bill / Dom / Bob / Stan. Shared verbatim by both
// ports: the wasm BossController reads table directly and SpriteFactory reads
// colors, apple's BossController layers the pants color + spawn slot on top.
// Spawn positions come from the level map. SKColor's .system* constants resolve
// identically on apple (= NSColor) and on the SuperBox64 kit, so this is the
// single source of boss colors.
enum BossBlueprint {
    static let table: [(name: String, personality: BossPersonality, speed: Double)] = [
        (Strings.Boss.bill, .directChase,                                                   0.90),
        (Strings.Boss.dom,  .ambushAhead(tiles: 4),                                         0.80),
        (Strings.Boss.bob,  .flanker(pivotTiles: 2),                                        0.70),
        (Strings.Boss.stan, .timidScatter(scatterGrid: CGPoint(x: 1, y: 1), threshold: 8),  0.60),
    ]

    // blended(withFraction:of:) returns an optional on both ports, hence the ?? fallbacks.
    static let colors: [(body: SKColor, tie: SKColor)] = [
        (.systemRed,    .black),
        (SKColor.systemPink.withAlphaComponent(0.75), SKColor.systemPurple.blended(withFraction: 0.40, of: .black) ?? .systemPurple),
        (.systemTeal,   SKColor.systemBlue.blended(withFraction: 0.20, of: .black) ?? .systemBlue),
        (.systemOrange, SKColor.systemRed.blended(withFraction: 0.10, of: .black) ?? .systemRed),
    ]
}
