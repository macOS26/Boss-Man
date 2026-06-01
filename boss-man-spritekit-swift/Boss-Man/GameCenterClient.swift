import Foundation
import GameKit

@MainActor
enum GameCenterClient {
    static var authenticationResolved = false

    static func currentPlayerName() -> String {
        let displayName = GKLocalPlayer.local.displayName
        if GKLocalPlayer.local.isAuthenticated, displayName.count > 3 {
            return displayName
        }
        return Strings.Player.unknownTag
    }

    static func submitScore(_ score: Int, to leaderboardID: String) {
        guard GKLocalPlayer.local.isAuthenticated else {
            return
        }
        guard score > 0 else {
            return
        }
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { _ in }
    }
}
