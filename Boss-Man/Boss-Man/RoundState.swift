import Foundation

/// Per-run / per-floor mutable state for Boss-Man. Holds level, lives,
/// score (with persisted high-score side effect), and TPS-report
/// progress, plus the small mutators GameScene uses to reset between
/// rounds and advance between floors.
@MainActor
final class RoundState {
    static let highScoreKey = "Boss-Man.highScore"

    var level = 1
    var lives = HUD.maxLives
    var score = 0
    var dotCount = 0
    var collectedDots = 0
    var tpsReportsCreated = 0
    var reportItems: Set<String> = []
    private(set) var highScore = UserDefaults.standard.integer(forKey: RoundState.highScoreKey)

    func bumpScore(by points: Int) {
        score += points
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: Self.highScoreKey)
        }
    }

    func resetForNewGame() {
        level = 1
        lives = HUD.maxLives
        score = 0
        tpsReportsCreated = 0
        collectedDots = 0
        reportItems.removeAll()
    }

    func advanceLevel() {
        level += 1
        collectedDots = 0
        reportItems.removeAll()
    }
}
