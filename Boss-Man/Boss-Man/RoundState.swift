import Foundation

/// Per-run / per-floor mutable state for Boss-Man. Holds level, lives,
/// score (with persisted high-score side effect), and TPS-report
/// progress, plus the small mutators GameScene uses to reset between
/// rounds and advance between floors.
@MainActor
final class RoundState {
    static let highScoreKey = "Boss-Man.highScore"

    var level = 12 // DEBUG: starts on MIB level for testing
    var lives = HUD.maxLives
    var score = 0
    var dotCount = 0
    var collectedDots = 0
    var tpsReportsDelivered = 0
    var reportItems: Set<String> = []
    /// Points accumulated from collecting individual report items in the
    /// current TPS report cycle (10, 25, 50, 100).  Lost when the boss
    /// catches PETE, shown as a red negative popup.
    var currentReportScore = 0
    private(set) var highScore = UserDefaults.standard.integer(forKey: RoundState.highScoreKey)

    func bumpScore(by points: Int) {
        score += points
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: Self.highScoreKey)
        }
    }

    func resetForNewGame() {
        level = 12 // DEBUG: restart also lands on MIB level for testing
        lives = HUD.maxLives
        score = 0
        tpsReportsDelivered = 0
        collectedDots = 0
        reportItems.removeAll()
        currentReportScore = 0
    }

    func advanceLevel() {
        level += 1
        collectedDots = 0
        tpsReportsDelivered = 0
        reportItems.removeAll()
        currentReportScore = 0
    }
}
