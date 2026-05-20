import Foundation
import GameKit

/// Thin wrapper around the GameKit calls Boss-Man cares about: pulling
/// the local player's display name for high-score tagging and
/// submitting a run's score to the global leaderboard. Game Center
/// keeps each player's best on its own — we always submit the run
/// total, not the local UserDefaults high score.
@MainActor
enum GameCenterClient {
    /// Game Center display name when the player is signed in and the
    /// name is at least 4 characters; otherwise a generic "Player" tag.
    /// Matches Space-Bar's >3-char guard.
    static func currentPlayerName() -> String {
        let displayName = GKLocalPlayer.local.displayName
        if GKLocalPlayer.local.isAuthenticated, displayName.count > 3 {
            return displayName
        }
        return "Player"
    }

    static func submitScore(_ score: Int, to leaderboardID: String) {
        guard GKLocalPlayer.local.isAuthenticated else {
            print("[GC] submit skipped: not authenticated")
            return
        }
        guard score > 0 else {
            print("[GC] submit skipped: score 0")
            return
        }
        print("[GC] submitting score=\(score) to '\(leaderboardID)' as \(GKLocalPlayer.local.displayName)")
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { error in
            if let error {
                print("[GC] submit FAILED: \(error.localizedDescription) | \(error)")
            } else {
                print("[GC] submit OK")
            }
        }
    }
}
