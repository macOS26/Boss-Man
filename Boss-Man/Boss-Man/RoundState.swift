import Foundation

@MainActor
final class RoundState {
    static let highScoreKey = Strings.DefaultsKey.highScore

    var level = 1
    var lives = HUD.startingLives
    var score = 0
    var dotCount = 0
    var collectedDots = 0
    var goldDiscCount = 0
    var collectedGoldDiscs = 0
    var tpsReportsDelivered = 0
    var reportItems: Set<String> = []
    var currentReportScore = 0
    private(set) var highScore = UserDefaults.standard.integer(forKey: RoundState.highScoreKey)
    var practiceMode = false

    func bumpScore(by points: Int) {
        score += points
        guard !practiceMode else { return }
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: Self.highScoreKey)
        }
    }

    func resetForNewGame() {
        level = 1
        lives = HUD.startingLives
        score = 0
        tpsReportsDelivered = 0
        collectedDots = 0
        collectedGoldDiscs = 0
        reportItems.removeAll()
        currentReportScore = 0
    }

    func advanceLevel() {
        level += 1
        collectedDots = 0
        collectedGoldDiscs = 0
        tpsReportsDelivered = 0
        reportItems.removeAll()
        currentReportScore = 0
    }
}
