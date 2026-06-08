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
    var waterGunCount = 0
    var collectedWaterGuns = 0
    var waterPelletCount = 0
    var collectedWaterPellets = 0
    var tpsReportsDelivered = 0
    var reportItems: Set<String> = []
    var currentReportScore = 0
    private(set) var highScore = Persistence.int(forKey: RoundState.highScoreKey)
    var practiceMode = false
    static var demoMode = false

    func bumpScore(by points: Int) {
        score += points
        guard !practiceMode else { return }
        if score > highScore {
            highScore = score
            Persistence.set(highScore, forKey: Self.highScoreKey)
        }
    }

    func resetForNewGame() {
        level = 1
        lives = HUD.startingLives
        score = 0
        tpsReportsDelivered = 0
        clearCollected()
    }

    func advanceLevel() {
        level += 1
        tpsReportsDelivered = 0
        clearCollected()
    }

    private func clearCollected() {
        collectedDots = 0
        collectedGoldDiscs = 0
        collectedWaterGuns = 0
        collectedWaterPellets = 0
        reportItems.removeAll()
        currentReportScore = 0
    }

    var pickupsComplete: Bool {
        (RoundState.demoMode || collectedDots >= dotCount)
            && collectedGoldDiscs >= goldDiscCount
            && collectedWaterGuns >= waterGunCount
            && collectedWaterPellets >= waterPelletCount
    }
}

// MARK: - Shared level completion (one path for every game mode)

@MainActor
protocol LevelCompletionHost: AnyObject {
    var state: RoundState { get }
    var hud: HUD! { get }
    func startNextLevel()
}

extension LevelCompletionHost {
    func checkLevelComplete() {
        guard state.pickupsComplete else { return }
        if state.tpsReportsDelivered >= 1 {
            startNextLevel()
        } else {
            hud.showMessage(Strings.Message.needTPSReport, duration: 3)
        }
    }
}
